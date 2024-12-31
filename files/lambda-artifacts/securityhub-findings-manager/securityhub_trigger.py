from aws_lambda_powertools import Logger
from boto3 import client
from json import dumps
#from awsfindingsmanagerlib import FindingsManager
from strategize_findings_manager import get_rules

LOGGER = Logger()

sqs = client('sqs')
queue_url =  "SecurityHubSuppressorRuleQueue" #os.environ['SQS_QUEUE_URL']

@LOGGER.inject_lambda_context(log_event=True)
def lambda_handler(event, context):
    for rule in get_rules(LOGGER):
        message_body = dumps(rule.data)
        LOGGER.info(f'putting rule {message_body} on SQS')
        sqs.send_message(
            QueueUrl=queue_url,
            MessageBody=message_body
        )
