import boto3
import json
import os
from aws_lambda_powertools import Logger
from aws_lambda_powertools.utilities.typing import LambdaContext

import helpers

logger = Logger()

securityhub = boto3.client('securityhub')
secretsmanager = boto3.client('secretsmanager')

REQUIRED_ENV_VARS = [
    'EXCLUDE_ACCOUNT_FILTER', 'JIRA_ISSUE_TYPE', 'JIRA_PROJECT_KEY', 'JIRA_SECRET_ARN'
]
DEFAULT_JIRA_AUTOCLOSE_COMMENT = 'Security Hub finding has been resolved. Autoclosing the issue.'
DEFAULT_JIRA_AUTOCLOSE_TRANSITION = 'Done'

@logger.inject_lambda_context
def lambda_handler(event: dict, context: LambdaContext):
  # Validate required environment variables
  helpers.validate_env_vars(REQUIRED_ENV_VARS)

  # Retrieve environment variables
  EXCLUDE_ACCOUNT_FILTER = os.environ['EXCLUDE_ACCOUNT_FILTER']
  JIRA_AUTOCLOSE_ENABLED = os.getenv('JIRA_AUTOCLOSE_ENABLED', DEFAULT_JIRA_AUTOCLOSE_ENABLED)
  JIRA_AUTOCLOSE_COMMENT = os.getenv('JIRA_AUTOCLOSE_COMMENT', DEFAULT_JIRA_AUTOCLOSE_COMMENT)
  JIRA_AUTOCLOSE_TRANSITION = os.getenv('JIRA_AUTOCLOSE_TRANSITION', DEFAULT_JIRA_AUTOCLOSE_TRANSITION)
  JIRA_ISSUE_TYPE = os.environ['JIRA_ISSUE_TYPE']
  JIRA_PROJECT_KEY = os.environ['JIRA_PROJECT_KEY']
  JIRA_SECRET_ARN = os.environ['JIRA_SECRET_ARN']

  # Retrieve JIRA client
  jira_secret = helpers.get_secret(secretsmanager, JIRA_SECRET_ARN)
  jira_client = helpers.get_jira_client(jira_secret)

  # Get Sechub event details
  event_detail = event['detail']
  finding = event_detail['findings'][0]
  finding_account_id = finding['AwsAccountId']
  workflow_status = finding['Workflow']['Status']

  # Only process finding if account is not excluded
  if finding_account_id in EXCLUDE_ACCOUNT_FILTER:
    logger.info(f"Account {finding_account_id} is excluded from JIRA ticket creation.")
    return

  if workflow_status == "NEW":
    # Create JIRA issue and updates Security Hub status to NOTIFIED and adds JIRA issue key to note (in JSON format)
    issue = helpers.create_jira_issue(jira_client, JIRA_PROJECT_KEY, JIRA_ISSUE_TYPE, event_detail)
    note = json.dumps({'jiraIssue': issue.key})
    helpers.update_security_hub(securityhub, finding["Id"], finding["ProductArn"], "NOTIFIED", note)
  elif workflow_status == "RESOLVED":
    # Close JIRA issue if finding is resolved. Note text should contain JIRA issue key in JSON format
    try:
      note_text = finding['Note']['Text']
      note_text_json = json.loads(note_text)
      jira_issue_id = note_text_json.get('jiraIssue')

      if jira_issue_id:
        issue = jira_client.issue(jira_issue_id)
        helpers.close_jira_issue(jira_client, issue, JIRA_AUTOCLOSE_TRANSITION, JIRA_AUTOCLOSE_COMMENT)
    except json.JSONDecodeError as e:
      logger.error(f"Failed to decode JSON from note text: {e}. Cannot autoclose.")
    except Exception as e:
      logger.error(f"Failed to get JIRA issue: {e}. Cannot autoclose.")
