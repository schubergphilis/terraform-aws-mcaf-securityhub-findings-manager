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
    'EXCLUDE_ACCOUNT_FILTER', 'JIRA_ISSUE_CUSTOM_FIELDS', 'JIRA_ISSUE_TYPE', 'JIRA_PROJECT_KEY', 'JIRA_SECRET_ARN', 'JIRA_SECRET_TYPE'
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

    # Retrieve environment variables
    exclude_account_filter = os.environ['EXCLUDE_ACCOUNT_FILTER']
    jira_autoclose_comment = os.getenv(
        'JIRA_AUTOCLOSE_COMMENT', DEFAULT_JIRA_AUTOCLOSE_COMMENT)
    jira_autoclose_transition = os.getenv(
        'JIRA_AUTOCLOSE_TRANSITION', DEFAULT_JIRA_AUTOCLOSE_TRANSITION)
    jira_issue_custom_fields = os.environ['JIRA_ISSUE_CUSTOM_FIELDS']
    jira_issue_type = os.environ['JIRA_ISSUE_TYPE']
    jira_project_key = os.environ['JIRA_PROJECT_KEY']
    jira_secret_arn = os.environ['JIRA_SECRET_ARN']
    jira_secret_type = os.environ['JIRA_SECRET_TYPE']

    # Parse custom fields
    try:
        jira_issue_custom_fields = json.loads(jira_issue_custom_fields)
        jira_issue_custom_fields = {k: {"value": v}
                                    for k, v in jira_issue_custom_fields.items()}
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse JSON for custom fields: {e}.")
        raise ValueError(f"Invalid JSON in JIRA_ISSUE_CUSTOM_FIELDS: {e}") from e

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

    # Get Sechub event details
    event_detail = event['detail']
    finding = event_detail['findings'][0]
    finding_account_id = finding['AwsAccountId']
    workflow_status = finding['Workflow']['Status']
    compliance_status = finding['Compliance']['Status'] if 'Compliance' in finding else COMPLIANCE_STATUS_MISSING
    record_state = finding['RecordState']

    # Only process finding if account is not excluded
    if finding_account_id in exclude_account_filter:
        logger.info(
            f"Account {finding_account_id} is excluded from Jira ticket creation.")
        return

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
            note = json.dumps({'jiraIssue': issue.key})
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
            if jira_issue_id:
                try:
                    issue = jira_client.issue(jira_issue_id)
                except JIRAError as e:
                    logger.error(
                        f"Failed to retrieve Jira issue {jira_issue_id}: {e}. Cannot autoclose.")
                    return  # Skip further processing for this finding
                helpers.close_jira_issue(
                    jira_client, issue, jira_autoclose_transition, jira_autoclose_comment)
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
