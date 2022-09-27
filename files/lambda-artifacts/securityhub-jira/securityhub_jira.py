import json
import boto3
import os
import base64
import urllib.request
import urllib
from aws_lambda_powertools import Logger

logger = Logger()
EXCLUDE_ACCOUNT_FILTER = os.environ['EXCLUDE_ACCOUNT_FILTER']
JIRA_ISSUE_TYPE = os.environ['JIRA_ISSUE_TYPE']
JIRA_SECRET_ARN = os.environ['JIRA_SECRET_ARN']
JIRA_PROJECT_KEY = os.environ['JIRA_PROJECT_KEY']


def jira_rest_call(data, url, apiuser, apikey):
    # Encode the username and password
    base64string = base64.encodebytes(('%s:%s' % (apiuser, apikey)).encode()).decode().strip()  # noqa: E501
    jiraurl = url + "/rest/api/latest/issue/"

    # Build the request
    restreq = urllib.request.Request(jiraurl)
    restreq.add_header('Content-Type', 'application/json')
    restreq.add_header("Authorization", "Basic %s" % base64string)

    # Send the request and grab JSON response
    response = urllib.request.urlopen(restreq, data.encode('utf-8'))

    # Load into a JSON object and return that to the calling function
    return json.loads(response.read())


def jira_build_sechub_data(issueType, accountId, region, event, projectKey):
    finding = event['findings'][0]
    description = finding['Description'] + "\n\n A Security Hub finding has \
        been detected: \n{code}\n" \
        + json.dumps(event, indent=4, sort_keys=True) + "\n{code}\n"

    title = "Security Hub (" + finding['Title'] + ") detected in " + accountId
    labels = [region, accountId, finding['Severity']['Label'].lower()]
    if finding['ProductFields'].get("RuleId"):
        labels.append(finding['ProductFields']['RuleId'])
    if finding['ProductFields'].get("ControlId"):
        labels.append(finding['ProductFields']['ControlId'])
    if finding['ProductFields'].get("ControlId"):
        labels.append(finding['ProductFields']['aws/securityhub/ProductName'].replace(" ", ""))  # noqa: E501

    issue = {
        'fields': {
            'project': {'key': projectKey},
            'summary': title,
            'description': description,
            'issuetype': {'name': issueType},
            'labels': labels,
            'customfield_11101': {'value': 'Vulnerability Management'}
        }
    }
    return json.dumps(issue)


def get_jira_secret(boto3, secretarn):
    service_client = boto3.client('secretsmanager')
    secret = service_client.get_secret_value(SecretId=secretarn)
    plaintext = secret['SecretString']
    secret_dict = json.loads(plaintext)

    # Run validations against the secret
    required_fields = ['apiuser', 'apikey', 'url']
    for field in required_fields:
        if field not in secret_dict:
            raise KeyError("%s key is missing from secret JSON" % field)
    return secret_dict


def update_workflowstatus(boto3, finding):
    service_client = boto3.client('securityhub')
    try:
        response = service_client.batch_update_findings(
            FindingIdentifiers=[
                {
                    'Id': finding['Id'],
                    'ProductArn': finding['ProductArn']
                }
            ],
            Workflow={
                'Status': 'NOTIFIED'
            }
        )
        return response
    except Exception as e:
        logger.exception(
            "Updating finding workflow failed, please troubleshoot further", e)
        raise


def create_issue_for_account(accountId, excludeAccountFilter):
    if accountId in excludeAccountFilter:
        return False
    else:
        return True


@logger.inject_lambda_context(log_event=True)
def lambda_handler(event, context):
    # Get Sechub event details
    eventDetails = event['detail']
    finding = eventDetails['findings'][0]
    findingAccountId = finding["AwsAccountId"]
    findingRegion = finding["Region"]
    if create_issue_for_account(findingAccountId, EXCLUDE_ACCOUNT_FILTER):  # noqa: E501
        jiraSecretData = get_jira_secret(boto3, JIRA_SECRET_ARN)
        jiraUrl = jiraSecretData['url']
        jiraApiUser = jiraSecretData['apiuser']
        jiraApiKey = jiraSecretData['apikey']

        json_data = jira_build_sechub_data(JIRA_ISSUE_TYPE, findingAccountId,
                                           findingRegion, eventDetails,
                                           JIRA_PROJECT_KEY)
        logger.info("Jira issue ", json_data)
        json_response = jira_rest_call(json_data, jiraUrl, jiraApiUser,
                                       jiraApiKey)
        logger.info("Created Jira issue ", json_response['key'])
        response = update_workflowstatus(boto3, finding)
        logger.info("Updated sechub finding workflow: ", response)
