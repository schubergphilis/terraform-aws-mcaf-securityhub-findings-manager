import json
import os
import boto3
from aws_lambda_powertools import Logger
from aws_lambda_powertools.utilities.typing import LambdaContext
from jira.exceptions import JIRAError
import helpers

logger = Logger()
securityhub = boto3.client('securityhub')
secretsmanager = boto3.client('secretsmanager')
ssm = boto3.client('ssm')

REQUIRED_ENV_VARS = [
    'EXCLUDE_ACCOUNT_FILTER',
    'JIRA_INSTANCES_CONFIG'
]

DEFAULT_JIRA_AUTOCLOSE_COMMENT = 'Security Hub finding has been resolved. Autoclosing the issue.'
DEFAULT_JIRA_AUTOCLOSE_TRANSITION = 'Close Issue'

STATUS_NEW = 'NEW'
STATUS_NOTIFIED = 'NOTIFIED'
STATUS_RESOLVED = 'RESOLVED'
STATUS_SUPPRESSED = 'SUPPRESSED'
COMPLIANCE_STATUS_FAILED = 'FAILED'
COMPLIANCE_STATUS_NOT_AVAILABLE = 'NOT_AVAILABLE'
COMPLIANCE_STATUS_PASSED = 'PASSED'
COMPLIANCE_STATUS_WARNING = 'WARNING'
COMPLIANCE_STATUS_MISSING = 'MISSING'
RECORD_STATE_ACTIVE = 'ACTIVE'
RECORD_STATE_ARCHIVED = 'ARCHIVED'


@logger.inject_lambda_context
def lambda_handler(event: dict, context: LambdaContext):
    # Validate required environment variables
    try:
        helpers.validate_env_vars(REQUIRED_ENV_VARS)
    except Exception as e:
        logger.error(f"Environment variable validation failed: {e}")
        raise RuntimeError("Required environment variables are missing.") from e

    # Get finding account ID (needed for instance lookup)
    event_detail = event['detail']
    finding = event_detail['findings'][0]
    finding_account_id = finding['AwsAccountId']
    
    # Extract global settings
    jira_autoclose_comment = os.getenv('JIRA_AUTOCLOSE_COMMENT', DEFAULT_JIRA_AUTOCLOSE_COMMENT)
    exclude_account_filter = json.loads(os.environ['EXCLUDE_ACCOUNT_FILTER'])
    
    if finding_account_id in exclude_account_filter:
        logger.info(
            f"Account {finding_account_id} is in the global exclude list. Skipping Jira ticket creation."
        )
        return
    
    # Load multi-instance configuration
    instances_config = json.loads(os.environ.get('JIRA_INSTANCES_CONFIG', '{}'))

    # Find which instance matches this account
    instance_name, instance_config = helpers.find_instance_for_account(finding_account_id, instances_config)

    if not instance_config:
        logger.info(f"No Jira instance configured for account {finding_account_id}")
        return

    # Extract per-instance settings with defaults
    instance_include_product_names = instance_config.get('include_product_names', [])
    instance_threshold = instance_config.get('finding_severity_normalized_threshold', 70)

    # Apply per-instance product name filter (for both create and autoclose)
    if instance_include_product_names:
        product_name = finding.get('ProductName', '')
        if product_name not in instance_include_product_names:
            logger.info(
                f"Product '{product_name}' not in include list {instance_include_product_names} for instance {instance_name}. Skipping."
            )
            return

    # Get remaining Security Hub finding details
    workflow_status = finding['Workflow']['Status']
    compliance_status = finding['Compliance']['Status'] if 'Compliance' in finding else COMPLIANCE_STATUS_MISSING
    record_state = finding['RecordState']

    # Apply per-instance severity threshold (only for CREATE new findings, not autoclose)
    if (workflow_status == STATUS_NEW
            and compliance_status in [COMPLIANCE_STATUS_FAILED, COMPLIANCE_STATUS_WARNING, COMPLIANCE_STATUS_MISSING]
            and record_state == RECORD_STATE_ACTIVE):
        normalized_severity = finding.get('Severity', {}).get('Normalized', 0)
        if normalized_severity < instance_threshold:
            logger.info(
                f"Severity {normalized_severity} below threshold {instance_threshold} for instance {instance_name}. Skipping."
            )
            return

    # Get remaining Security Hub finding details
    jira_issue_custom_fields = instance_config.get('issue_custom_fields', {})
    jira_issue_type = instance_config.get('issue_type', 'Security Advisory')
    jira_project_key = instance_config['project_key']
    jira_secret_arn = instance_config.get('credentials_secretsmanager_arn') or instance_config.get('credentials_ssm_secret_arn')
    jira_secret_type = 'SECRETSMANAGER' if instance_config.get('credentials_secretsmanager_arn') else 'SSM'

    # Parse custom fields
    try:
        jira_issue_custom_fields = {k: {"value": v} for k, v in jira_issue_custom_fields.items()}
    except Exception as e:
        logger.error(f"Failed to parse custom fields: {e}.")
        raise ValueError(f"Invalid custom fields format: {e}") from e

    # Retrieve Jira client
    try:
        if jira_secret_arn:
            if jira_secret_type == 'SECRETSMANAGER':
                jira_secret = helpers.get_secret(secretsmanager, jira_secret_arn)
            elif jira_secret_type == "SSM":
                jira_secret = helpers.get_ssm_secret(ssm, jira_secret_arn)
            else:
                raise ValueError(
                    f"Invalid JIRA_SECRET_TYPE {jira_secret_type}. Must be SECRETSMANAGER or SSM.")
        else:
            raise ValueError(f"JIRA SECRET ARN {jira_secret_arn} is set to empty. Cannot proceed without JIRA Credentials.")
        jira_client = helpers.get_jira_client(jira_secret)
    except Exception as e:
        logger.error(f"Failed to retrieve Jira client: {e}")
        raise RuntimeError("Could not initialize Jira client.") from e

    # Handle new findings
    # Ticket is created when Workflow Status is NEW and Compliance Status is FAILED, WARNING or is missing from the finding (case with e.g. Inspector findings)
    # Compliance status check is necessary because some findings from AWS Config can have Workflow Status NEW but Compliance Status NOT_AVAILABLE
    # In such case, we don't want to create a Jira ticket, because the finding is not actionable
    if (workflow_status == STATUS_NEW
            and compliance_status in [COMPLIANCE_STATUS_FAILED,
                                      COMPLIANCE_STATUS_WARNING,
                                      COMPLIANCE_STATUS_MISSING]
            and record_state == RECORD_STATE_ACTIVE):
        # Create Jira issue and updates Security Hub status to NOTIFIED
        # and adds Jira issue key to note (in JSON format)
        try:
            issue = helpers.create_jira_issue(
                jira_client, jira_project_key, jira_issue_type, event_detail, jira_issue_custom_fields)
            # Create note with instance tracking for proper autoclose handling
            note = json.dumps({
                'jiraIssue': issue.key,
                'jiraInstance': instance_name
            })
            helpers.update_security_hub(
                securityhub, finding["Id"], finding["ProductArn"], STATUS_NOTIFIED, note)
        except Exception as e:
            logger.error(
                f"Error processing new finding for findingID {finding['Id']}: {e}")
            raise RuntimeError(f"Failed to create Jira issue or update Security Hub for finding ID {finding['Id']}.") from e

    # Handle resolved findings - Close Jira issue when:
    # 1. Workflow status is RESOLVED (finding explicitly resolved)
    # 2. Workflow status is SUPPRESSED (finding suppressed, step function only passed these type of findings when autoclose_suppressed_findings = true)
    # 3. Workflow status is NOTIFIED AND any of:
    #    - Compliance status is PASSED (resolved but not yet marked in SecurityHub)
    #    - Compliance status is NOT_AVAILABLE (resource deleted)
    #    - Record state is ARCHIVED
    # Note: Findings closed from NOTIFIED status are automatically marked as RESOLVED in SecurityHub.
    #       SecurityHub will reopen and create a new ticket if the finding becomes relevant again.
    elif (workflow_status == STATUS_RESOLVED
            or workflow_status == STATUS_SUPPRESSED
            or (workflow_status == STATUS_NOTIFIED
                and (compliance_status in [COMPLIANCE_STATUS_PASSED,
                                           COMPLIANCE_STATUS_NOT_AVAILABLE]
                     or record_state == RECORD_STATE_ARCHIVED))):
        # Close Jira issue if finding is resolved.
        # Note text should contain Jira issue key in JSON format
        try:
            note_text = finding['Note']['Text']
            note_text_json = json.loads(note_text)
            jira_issue_id = note_text_json.get('jiraIssue')
            note_instance_name = note_text_json.get('jiraInstance')

            # Determine which instance to use for autoclose
            # Priority: note_instance_name > default_instance > error
            autoclose_instance_config = None
            autoclose_instance_name = None

            if note_instance_name and note_instance_name in instances_config:
                # Use the instance that created the ticket
                autoclose_instance_config = instances_config[note_instance_name]
                autoclose_instance_name = note_instance_name
                logger.info(f"Using Jira instance '{note_instance_name}' from note for autoclose")
            else:
                # Fallback to default instance for old notes without jiraInstance field
                for inst_name, inst_config in instances_config.items():
                    if inst_config.get('enabled', True) and inst_config.get('default_instance', False):
                        autoclose_instance_config = inst_config
                        autoclose_instance_name = inst_name
                        logger.info(f"Using default Jira instance '{inst_name}' for autoclose (note has no jiraInstance field)")
                        break

                if not autoclose_instance_config:
                    logger.error(f"Cannot autoclose: jiraInstance '{note_instance_name}' not found in config and no default instance configured")
                    return

            # Get credentials from the autoclose instance
            autoclose_secret_arn = autoclose_instance_config.get('credentials_secretsmanager_arn') or autoclose_instance_config.get('credentials_ssm_secret_arn')
            autoclose_secret_type = 'SECRETSMANAGER' if autoclose_instance_config.get('credentials_secretsmanager_arn') else 'SSM'
            autoclose_intermediate_transition = autoclose_instance_config.get('include_intermediate_transition', '')
            # Get per-instance autoclose transition
            autoclose_transition = autoclose_instance_config.get('autoclose_transition_name', DEFAULT_JIRA_AUTOCLOSE_TRANSITION)

            # Initialize Jira client with the autoclose instance's credentials
            try:
                if autoclose_secret_type == 'SECRETSMANAGER':
                    autoclose_secret = helpers.get_secret(secretsmanager, autoclose_secret_arn)
                elif autoclose_secret_type == "SSM":
                    autoclose_secret = helpers.get_ssm_secret(ssm, autoclose_secret_arn)
                else:
                    raise ValueError(f"Invalid secret type {autoclose_secret_type} for instance '{autoclose_instance_name}'")
                autoclose_jira_client = helpers.get_jira_client(autoclose_secret)
            except Exception as e:
                logger.error(f"Failed to get credentials for autoclose instance '{autoclose_instance_name}': {e}")
                raise RuntimeError(f"Could not initialize Jira client for autoclose.") from e

            if jira_issue_id:
                try:
                    issue = autoclose_jira_client.issue(jira_issue_id)
                except JIRAError as e:
                    logger.error(
                        f"Failed to retrieve Jira issue {jira_issue_id}: {e}. Cannot autoclose.")
                    return  # Skip further processing for this finding
                helpers.close_jira_issue(
                    autoclose_jira_client, issue, autoclose_transition, jira_autoclose_comment, autoclose_intermediate_transition)

                # Update note to prevent re-processing: remove 'jiraIssue' to prevent Step Function filter match
                # Add 'jiraClosedIssue' for audit trail, preserving all other note content
                updated_note_json = note_text_json.copy()
                if 'jiraIssue' in updated_note_json:
                    updated_note_json['jiraClosedIssue'] = updated_note_json.pop('jiraIssue')
                updated_note = json.dumps(updated_note_json)

                # Update Security Hub note for NOTIFIED and SUPPRESSED findings
                # NOTIFIED: Change to RESOLVED (finding will reopen if compliance fails again)
                # SUPPRESSED: Keep SUPPRESSED status
                if workflow_status in [STATUS_NOTIFIED, STATUS_SUPPRESSED]:
                    target_status = STATUS_RESOLVED if workflow_status == STATUS_NOTIFIED else STATUS_SUPPRESSED
                    helpers.update_security_hub(
                        securityhub, finding["Id"], finding["ProductArn"], target_status, updated_note)
                    
        except json.JSONDecodeError as e:
            logger.error(
                f"Failed to decode JSON from note text: {e}. Cannot autoclose.")
            raise ValueError(f"Invalid JSON in note text for finding ID {finding['Id']}.") from e
        except Exception as e:
            logger.error(
                f"Error processing resolved finding for findingId {finding['Id']}: {e}. Cannot autoclose.")
            return

    else:
        logger.info(
            f"Finding {finding['Id']} is not in a state to be processed. Workflow status: {workflow_status}, Compliance status: {compliance_status}, Record state: {record_state}")
