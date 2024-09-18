import boto3
import os
from aws_lambda_powertools import Logger
from aws_lambda_powertools.utilities.typing import LambdaContext

import helpers

logger = Logger()

securityhub = boto3.client('securityhub')
secretsmanager = boto3.client('secretsmanager')

@logger.inject_lambda_context
def lambda_handler(event: dict, context: LambdaContext):
  helpers.validate_env_vars(['EXCLUDE_ACCOUNT_FILTER', 'JIRA_ISSUE_TYPE', 'JIRA_PROJECT_KEY', 'JIRA_SECRET_ARN'])

  EXCLUDE_ACCOUNT_FILTER = os.environ['EXCLUDE_ACCOUNT_FILTER']
  JIRA_AUTOCLOSE_ENABLED = os.getenv('JIRA_AUTOCLOSE_ENABLED', 'false')
  JIRA_AUTOCLOSE_COMMENT = os.getenv('JIRA_AUTOCLOSE_COMMENT', 'Security Hub finding has been resolved. Autoclosing the issue.')
  JIRA_AUTOCLOSE_TRANSITION = os.getenv('JIRA_AUTOCLOSE_TRANSITION', 'Done')
  JIRA_ISSUE_TYPE = os.environ['JIRA_ISSUE_TYPE']
  JIRA_PROJECT_KEY = os.environ['JIRA_PROJECT_KEY']
  JIRA_SECRET_ARN = os.environ['JIRA_SECRET_ARN']

  jira_secret = helpers.get_secret(secretsmanager, JIRA_SECRET_ARN)
  jira_client = helpers.get_jira_client(jira_secret)
  
  # Get Sechub event details
  eventDetails = event['detail']
  finding = eventDetails['findings'][0]
  findingAccountId = finding["AwsAccountId"]
  workflowStatus = finding["Workflow"]["Status"]
  noteText = finding["Note"]["Text"]

  if findingAccountId in EXCLUDE_ACCOUNT_FILTER:
    logger.info(f"Account {findingAccountId} is excluded from JIRA ticket creation.")
    return
  
  if workflowStatus == "NEW":
    issue = helpers.create_jira_issue(jira_client, JIRA_PROJECT_KEY, JIRA_ISSUE_TYPE, eventDetails)
    helpers.update_security_hub(securityhub, finding["Id"], finding["ProductArn"], "NOTIFIED", issue.key)
  elif workflowStatus == "RESOLVED" and JIRA_AUTOCLOSE_ENABLED == "true":
    issue = None
    try:
      issue = jira_client.issue(noteText)
    except Exception as e:
      logger.error(f"Failed to get JIRA issue: {e}. Cannot autoclose.")
    
    if issue:
      helpers.close_jira_issue(jira_client, issue, JIRA_AUTOCLOSE_TRANSITION, JIRA_AUTOCLOSE_COMMENT)
  