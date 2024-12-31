from json import loads
from aws_lambda_powertools import Logger
from strategize_findings_manager import manager_per_rule

LOGGER = Logger()


@LOGGER.inject_lambda_context(log_event=True)
def lambda_handler(event, context):
    for record in event["Records"]:
        try:
            rule = loads(record["body"])
            manager_per_rule(rule, LOGGER)
        except Exception as e:
            LOGGER.error(f"Failed to process rule. Rule details; {rule}")
            LOGGER.info(f"Original error: {e}", exc_info=True)
