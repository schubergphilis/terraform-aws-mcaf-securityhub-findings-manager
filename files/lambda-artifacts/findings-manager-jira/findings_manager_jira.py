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
DEFAULT_JIRA_AUTOCLOSE_TRANSITION = 'Done'

STATUS_NEW = 'NEW'
STATUS_NOTIFIED = 'NOTIFIED'
STATUS_RESOLVED = 'RESOLVED'
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

    # Extract event details and finding information
    event_detail = event['detail']
    finding = event_detail['findings'][0]
    finding_account_id = finding['AwsAccountId']
    
    # Extract global settings
    jira_autoclose_comment = os.getenv('JIRA_AUTOCLOSE_COMMENT', DEFAULT_JIRA_AUTOCLOSE_COMMENT)
    jira_autoclose_transition = os.getenv('JIRA_AUTOCLOSE_TRANSITION', DEFAULT_JIRA_AUTOCLOSE_TRANSITION)
    exclude_account_filter = json.loads(os.environ['EXCLUDE_ACCOUNT_FILTER'])
    
    # Get workflow status early to determine processing path
    workflow_status = finding['Workflow']['Status']
    compliance_status = finding['Compliance']['Status'] if 'Compliance' in finding else COMPLIANCE_STATUS_MISSING
    record_state = finding['RecordState']
    
    # Load multi-instance configuration (needed for both paths)
    instances_config = json.loads(os.environ.get('JIRA_INSTANCES_CONFIG', '{}'))

    # Handle new findings
    # Ticket is created when Workflow Status is NEW and Compliance Status is FAILED, WARNING or is missing from the finding (case with e.g. Inspector findings)
    # Compliance status check is necessary because some findings from AWS Config can have Workflow Status NEW but Compliance Status NOT_AVAILABLE
    # In such case, we don't want to create a Jira ticket, because the finding is not actionable
    if (workflow_status == STATUS_NEW
            and compliance_status in [COMPLIANCE_STATUS_FAILED,
                                      COMPLIANCE_STATUS_WARNING,
                                      COMPLIANCE_STATUS_MISSING]
            and record_state == RECORD_STATE_ACTIVE):
        
        # Check if account is in global exclude list
        if finding_account_id in exclude_account_filter:
            logger.info(
                f"Account {finding_account_id} is in the global exclude list. Skipping Jira ticket creation."
            )
            return
        
        # Find which instance matches this account (only for NEW findings)
        instance_name, instance_config = helpers.find_instance_for_account(finding_account_id, instances_config)

        if not instance_config:
            logger.info(f"No Jira instance configured for account {finding_account_id}")
            return

        # Extract instance-specific configuration
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

        # Retrieve Jira client for ticket creation
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

    # Handle resolved findings
    # Close Jira issue if finding in SecurityHub has Workflow Status RESOLVED
    # or if the finding is in NOTIFIED status and compliance is PASSED (finding resoloved) or NOT_AVAILABLE (when the resource is deleted, for example) or the finding's Record State is ARCHIVED
    # If closed from NOTIFIED status, also resolve the finding in SecurityHub. If the finding becomes relevant again, Security Hub will reopen it and new ticket will be created.
    elif (workflow_status == STATUS_RESOLVED
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
                    autoclose_jira_client, issue, jira_autoclose_transition, jira_autoclose_comment, autoclose_intermediate_transition)
                if workflow_status == STATUS_NOTIFIED:
                    # Resolve SecHub finding as it will be reopened anyway in case the compliance fails
                    # Also change the note to prevent a second run with RESOLVED status.
                    helpers.update_security_hub(
                        securityhub, finding["Id"], finding["ProductArn"], STATUS_RESOLVED, f"Closed Jira issue {jira_issue_id}")
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
