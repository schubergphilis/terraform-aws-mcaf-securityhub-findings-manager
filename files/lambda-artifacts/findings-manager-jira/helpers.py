import base64
import json
import os
from typing import List, Dict

from aws_lambda_powertools import Logger
from botocore.client import BaseClient
from botocore.exceptions import ClientError
from jira import JIRA
from jira.resources import Issue

logger = Logger()


def validate_env_vars(env_vars: List[str]) -> None:
    """
    Validate that all specified environment variables are set.

    Args:
        env_vars (List[str]): A list of environment variable names to check.

    Raises:
        ValueError: If any of the specified environment variables are not set.
    """

    missing_vars = [var for var in env_vars if var not in os.environ]

    for var in missing_vars:
        logger.error(f"Environment variable {var} is not set!")

    if missing_vars:
        missing_str = ', '.join(missing_vars)
        logger.error(f"Missing environment variables: {missing_str}")
        raise ValueError(f"Missing environment variables: {missing_str}")


def get_jira_client(jira_secret: Dict[str, str]) -> JIRA:
    """
    Create a Jira client instance using the specified secret.

    Args:
        jira_secret (Dict[str, str]): A dictionary containing the Jira connection details.

    Returns:
        JIRA: A Jira client instance.

    Raises:
        ValueError: If the Jira connection details are not valid.
    """

    jira_url = jira_secret.get('url')
    jira_user = jira_secret.get('apiuser')
    jira_password = jira_secret.get('apikey')

    if not jira_url or not jira_user or not jira_password:
        raise ValueError("Jira connection details are not valid!")

    return JIRA(server=jira_url, basic_auth=(jira_user, jira_password))


def get_secret(client: BaseClient, secret_arn: str) -> Dict[str, str]:
    """
    Retrieve a secret from AWS Secrets Manager.

    Args:
        client (BaseClient): A boto3 client instance for Secrets Manager.
        secret_arn (str): The ARN of the secret to retrieve.

    Returns:
        Dict[str, str]: The secret value as a dictionary.

    Raises:
        ValueError: If the client is not an instance of Secrets Manager.
        ClientError: If there is an error retrieving the secret.
    """

    # Validate that the client is an instance of botocore.client.SecretsManager
    if client.meta.service_model.service_name != 'secretsmanager':
        raise ValueError(f"Client must be an instance of botocore.client.SecretsManager. Got {
                         type(client)} instead.")

    try:
        response = client.get_secret_value(SecretId=secret_arn)
        secret = response.get('SecretString')

        if secret is None:
            secret = base64.b64decode(response['SecretBinary']).decode('utf-8')

        logger.info(f"Secret fetched from ARN {secret_arn}")
        return json.loads(secret)
    except Exception as e:
        logger.error(f"Error retrieving secret from ARN {secret_arn}: {e}")
        raise e

def get_ssm_secret(client: BaseClient, ssm_secret_arn: str) -> Dict[str, str]:
    """
    Retrieve a secret from AWS Secrets Manager.

    Args:
        client (BaseClient): A boto3 client instance for Secrets Manager.
        secret_arn (str): The ARN of the secret to retrieve.

    Returns:
        Dict[str, str]: The secret value as a dictionary.

    Raises:
        ValueError: If the client is not an instance of Secrets Manager.
        ClientError: If there is an error retrieving the secret.
    """

    # Validate that the client is an instance of botocore.client.SecretsManager
    if client.meta.service_model.service_name != 'ssm':
        raise ValueError(f"Client must be an instance of botocore.client.SSM. Got {type(client)} instead.")

    try:
        response = client.get_parameter(
            Name=ssm_secret_arn,
            WithDecryption=True  # Decrypt the parameter if it is encrypted
        )
        parameter_value = response['Parameter']['Value']

        logger.info(f"Parameter fetched from ARN {ssm_secret_arn}")
        return json.loads(parameter_value)

    except ClientError as e:
        logger.error(f"Error retrieving parameter from ARN {ssm_secret_arn}: {e}")
        raise e
    except Exception as e:
        logger.error(f"Unexpected error retrieving parameter from ARN {ssm_secret_arn}: {e}")
        raise e

def create_jira_issue(jira_client: JIRA, project_key: str, issue_type: str, event: dict, custom_fields: dict) -> Issue:
    """
    Create a Jira issue based on a Security Hub event.

    Args:
        jira_client (JIRA): An authenticated Jira client instance.
        project_key (str): The key of the Jira project.
        issue_type (str): The type of the Jira issue.
        event (Dict): The Security Hub event data.
        custom_fields (Dict): The custom fields to include in the Jira issue.

    Returns:
        Issue: The created Jira issue.

    Raises:
        Exception: If there is an error creating the Jira issue.
    """

    finding = event['findings'][0]
    finding_account_id = finding['AwsAccountId']
    finding_account_name = finding['AwsAccountName']
    finding_title = finding['Title']

    issue_title = f"Security Hub ({finding_title}) detected in {
        finding_account_id} ({finding_account_name})"

    issue_description = f"""
      {finding['Description']}

      A Security Hub finding has been detected:
      {{code}}{json.dumps(event, indent=2, sort_keys=True)}{{code}}
    """

    issue_labels = [
        finding["Region"],
        finding_account_id,
        finding_account_name,
        finding['Severity']['Label'].lower(),
        *[finding['ProductFields'][key].replace(" ", "")
          for key in ["RuleId", "ControlId", "aws/securityhub/ProductName"]
          if key in finding['ProductFields']]
    ]

    issue_dict = {
        **custom_fields,
        'project': {'key': project_key},
        'issuetype': {'name': issue_type},
        'summary': issue_title,
        'description': issue_description,
        'labels': issue_labels,
    }

    try:
        issue = jira_client.create_issue(fields=issue_dict)
        logger.info(f"Created Jira issue: {issue.key}")
        return issue
    except Exception as e:
        logger.error(f"Failed to create Jira issue for finding {finding['Id']}: {e}")
        raise e


def close_jira_issue(jira_client: JIRA, issue: Issue, transition_name: str, comment: str) -> None:
    """
    Close a Jira issue.

    Args:
        jira_client (JIRA): An authenticated Jira client instance.
        issue (Issue): The Jira issue to close.

    Raises:
        Exception: If there is an error closing the Jira issue.
    """

    try:
        transition_id = jira_client.find_transitionid_by_name(issue, transition_name)
        if transition_id is None:
            logger.warning(f"Failed to close Jira issue: Invalid transition.")
            return
        jira_client.add_comment(issue, comment)
        jira_client.transition_issue(issue, transition_id, comment=comment)
        logger.info(f"Closed Jira issue: {issue.key}")
    except Exception as e:
        logger.error(f"Failed to close Jira issue {issue.key}: {e}")
        raise e


def update_security_hub(client: BaseClient, finding_id: str,
                        product_arn: str, status: str, note: str = "") -> None:
    """
    Update a Security Hub finding with the given status and note.

    Args:
        client (BaseClient): A boto3 client instance for Security Hub.
        finding_id (str): The ID of the finding to update.
        product_arn (str): The ARN of the product associated with the finding.
        status (str): The new status for the finding.
        note (str): A note to add to the finding.

    Raises:
        ValueError: If the client is not an instance of Security Hub.
        ClientError: If there is an error updating the finding.
    """

    # Validate that the client is an instance of botocore.client.SecurityHub
    if client.meta.service_model.service_name != 'securityhub':
        raise ValueError(f"Client must be an instance of botocore.client.SecurityHub. Got {
                         type(client)} instead.")

    try:
        kwargs = {}
        if note:
            kwargs['Note'] = {
                'Text': note,
                'UpdatedBy': 'securityhub-findings-manager-jira'
            }
        logger.info(f"Updating SecurityHub finding {finding_id} to status {status} with note '{note}'.")
        response = client.batch_update_findings(
            FindingIdentifiers=[
                {
                    'Id': finding_id,
                    'ProductArn': product_arn
                }
            ],
            Workflow={'Status': status},
            **kwargs
        )

        if response.get('FailedFindings'):
            for element in response['FailedFindings']:
                logger.error(f"Updating SecurityHub finding failed: FindingId {
                    element['Id']}, ErrorCode {element['ErrorCode']}, ErrorMessage {
                        element['ErrorMessage']}")
        else:
            logger.info("SecurityHub finding updated successfully.")

    except Exception as e:
        logger.exception(f"Updating SecurityHub finding failed: {e}")
        raise e
