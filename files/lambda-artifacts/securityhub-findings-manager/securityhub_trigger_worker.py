import json

from aws_lambda_powertools import Logger
from awsfindingsmanagerlib import FindingsManager
#from strategize_findings_manager import manage

LOGGER = Logger()

# Todo:
#   integrate this with strategize_findings_manager
#   error handling
@LOGGER.inject_lambda_context(log_event=True)
def lambda_handler(event, context):
    for record in event['Records']:
        rule = json.loads(record['body'])
        print(f"Processing rule: {rule}")
        findings_manager_per_rule = FindingsManager()
        findings_manager_per_rule.register_rules([rule])
        LOGGER.info(findings_manager_per_rule.rules_errors)
        success, suppressed_payload = findings_manager_per_rule.suppress_matching_findings()
        suppressed_payload_count = len(suppressed_payload)
        if suppressed_payload_count > 0:
            for chunk in suppressed_payload:
                note_text = chunk['Note']['Text']
                workflow_status = chunk['Workflow']['Status']
                count = len(chunk['FindingIdentifiers'])
                LOGGER.info(f"{count} finding(s) {workflow_status} with note: {note_text}.")
