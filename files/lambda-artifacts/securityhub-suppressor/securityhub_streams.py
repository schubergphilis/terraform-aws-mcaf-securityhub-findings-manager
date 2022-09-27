import itertools
from typing import Any
from typing import Dict

import boto3
from aws_lambda_powertools import Logger
from aws_lambda_powertools.utilities.data_classes import DynamoDBStreamEvent
from aws_lambda_powertools.utilities.data_classes.dynamo_db_stream_event import DynamoDBRecordEventName

from securityhub_events import suppress
from securityhub_events import SUPPRESSED_FINDINGS

logger = Logger()
security_hub = boto3.client('securityhub')
paginator = security_hub.get_paginator('get_findings')


def get_findings(control_value: str) -> Dict[str, list]:
    findings = paginator.paginate(Filters={'ProductFields': [
        {
            'Key': 'RuleId',
            'Value': control_value,
            'Comparison': 'EQUALS'
        },
        {
            'Key': 'ControlId',
            'Value': control_value,
            'Comparison': 'EQUALS'
        }
    ],
        'ComplianceStatus': [{'Value': 'FAILED', 'Comparison': 'EQUALS'}],
    })
    return {'findings': list(itertools.chain.from_iterable([finding.get('Findings') for finding in findings]))}


def process_findings(findings_list):
    for finding in findings_list:
        try:
            suppress({'detail': {'findings': [finding]}})
        except ValueError:
            continue
    return len(SUPPRESSED_FINDINGS)


@logger.inject_lambda_context(log_event=True)
def lambda_handler(event: Dict[str, Any], context):
    total_findings = 0
    event: DynamoDBStreamEvent = DynamoDBStreamEvent(event)
    if event.records:
        for record in event.records:
            if record.event_name != DynamoDBRecordEventName.REMOVE:
                control_id = record.dynamodb.keys.get('controlId', {}).s_value
                findings_list = get_findings(control_id)
                if len(findings_list.get('findings')) == 0:
                    logger.warning(f'Could not find any findings with controlId {control_id}')
                    continue
                total_findings = process_findings(findings_list.get('findings'))
        logger.info(f'Total findings processed: {total_findings}')
