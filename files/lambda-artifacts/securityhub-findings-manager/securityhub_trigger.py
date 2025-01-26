from boto3 import client
from json import dumps
from os import environ
from aws_lambda_powertools import Logger
from strategize_findings_manager import get_rules

SQS_QUEUE_NAME = environ.get("SQS_QUEUE_NAME")
LOGGER = Logger()


@LOGGER.inject_lambda_context(log_event=True)
def lambda_handler(event, context):
    try:
        sqs = client("sqs")
        for rule in get_rules(LOGGER):
                message_body = dumps(rule.data)
                LOGGER.info(f"Putting rule on SQS. Rule details: {message_body}")
                sqs.send_message(
                    QueueUrl=SQS_QUEUE_NAME,
                    MessageBody=message_body
                )
    except Exception as e:
        LOGGER.error(f"Failed putting rule(s) on SQS.")
        LOGGER.info(f"Original error: {e}", exc_info=True)
        raise Exception
