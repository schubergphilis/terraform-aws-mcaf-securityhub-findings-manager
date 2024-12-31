import json

from aws_lambda_powertools import Logger
from awsfindingsmanagerlib import FindingsManager
from strategize_findings_manager import manage

LOGGER = Logger()

# import requests
# import os

@LOGGER.inject_lambda_context(log_event=True)
def lambda_handler(event, context):
    for record in event['Records']:  # SQS sends messages in batches
        rule = json.loads(record['body'])
        print(f"Processing rule: {rule}")
        findings_manager_per_rule = FindingsManager()
        findings_manager_per_rule.register_rules([rule])
        LOGGER.info(findings_manager_per_rule.rules_errors)
        success, suppressed_payload = findings_manager_per_rule.suppress_matching_findings()
        number_of_suppressions = len(suppressed_payload)
        # need the other way of reporting
        LOGGER.info(f'Success ?? : {success}')
        LOGGER.info(f'Suppressed number of findings: {number_of_suppressions}')
