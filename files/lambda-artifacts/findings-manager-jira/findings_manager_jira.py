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

REQUIRED_ENV_VARS = [
    'EXCLUDE_ACCOUNT_FILTER', 'JIRA_ISSUE_TYPE', 'JIRA_PROJECT_KEY', 'JIRA_SECRET_ARN'
]
DEFAULT_JIRA_AUTOCLOSE_COMMENT = 'Security Hub finding has been resolved. Autoclosing the issue.'
DEFAULT_JIRA_AUTOCLOSE_TRANSITION = 'Done'

STATUS_NEW = 'NEW'
STATUS_NOTIFIED = 'NOTIFIED'
STATUS_RESOLVED = 'RESOLVED'

@logger.inject_lambda_context
def lambda_handler(event: dict, context: LambdaContext):
    # Validate required environment variables
    helpers.validate_env_vars(REQUIRED_ENV_VARS)

    # Retrieve environment variables
    exclude_account_filter = os.environ['EXCLUDE_ACCOUNT_FILTER']
    jira_autoclose_comment = os.getenv(
        'JIRA_AUTOCLOSE_COMMENT', DEFAULT_JIRA_AUTOCLOSE_COMMENT)
    jira_autoclose_transition = os.getenv(
        'JIRA_AUTOCLOSE_TRANSITION', DEFAULT_JIRA_AUTOCLOSE_TRANSITION)
    jira_issue_type = os.environ['JIRA_ISSUE_TYPE']
    jira_project_key = os.environ['JIRA_PROJECT_KEY']
    jira_secret_arn = os.environ['JIRA_SECRET_ARN']

    # Retrieve JIRA client
    jira_secret = helpers.get_secret(secretsmanager, jira_secret_arn)
    jira_client = helpers.get_jira_client(jira_secret)

    # Get Sechub event details
    event_detail = event['detail']
    finding = event_detail['findings'][0]
    finding_account_id = finding['AwsAccountId']
    workflow_status = finding['Workflow']['Status']

    # Only process finding if account is not excluded
    if finding_account_id in exclude_account_filter:
        logger.info(
            f"Account {finding_account_id} is excluded from JIRA ticket creation.")
        return

    # Handle new findings
    if workflow_status == STATUS_NEW:
        # Create JIRA issue and updates Security Hub status to NOTIFIED
        # and adds JIRA issue key to note (in JSON format)
        try:
            issue = helpers.create_jira_issue(
                jira_client, jira_project_key, jira_issue_type, event_detail)
            note = json.dumps({'jiraIssue': issue.key})
            helpers.update_security_hub(
                securityhub, finding["Id"], finding["ProductArn"], STATUS_NOTIFIED, note)
        except Exception as e:
            logger.error(f"Error processing new finding for findingID {finding["Id"]}: {e}")
    
    # Handle resolved findings
    elif workflow_status == STATUS_RESOLVED:
        # Close JIRA issue if finding is resolved.
        # Note text should contain JIRA issue key in JSON format
        try:
            note_text = finding['Note']['Text']
            note_text_json = json.loads(note_text)
            jira_issue_id = note_text_json.get('jiraIssue')

            if jira_issue_id:
                try:
                    issue = jira_client.issue(jira_issue_id)
                except JIRAError as e:
                    logger.error(f"Failed to retrieve JIRA issue {jira_issue_id}: {e}. Cannot autoclose.")
                    return
                helpers.close_jira_issue(
                    jira_client, issue, jira_autoclose_transition, jira_autoclose_comment)
        except json.JSONDecodeError as e:
            logger.error(f"Failed to decode JSON from note text: {e}. Cannot autoclose.")
        except Exception as e:
            logger.error(f"Error processing resolved finding for findingId {finding["Id"]}: {e}. Cannot autoclose.")
