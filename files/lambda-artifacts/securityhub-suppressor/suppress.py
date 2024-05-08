from awsfindingsmanagerlib import FindingsManager, S3
from os import environ
from typing import Any
from typing import Dict
from typing import Optional
from typing import Tuple
from typing import Union

from aws_lambda_powertools import Logger
from aws_lambda_powertools.utilities.data_classes import EventBridgeEvent
from aws_lambda_powertools.utilities.typing import LambdaContext

logger = Logger()

S3_BUCKET_NAME = environ.get("S3_BUCKET_NAME")
suppressions = S3(S3_BUCKET_NAME, 'suppressions.yml')
manager = FindingsManager('eu-west-1')

manager.register_rules(suppressions.get_rules())
manager.suppress_matching_findings()

@logger.inject_lambda_context(log_event=True)
def lambda_handler(event: Dict[str, Any], context: LambdaContext):
    event: EventBridgeEvent = EventBridgeEvent(event)
    validate_event(event)
    if suppress(event):
        logger.info(f'Total findings processed: {len(SUPPRESSED_FINDINGS)}')
        return {
            'finding_state': 'suppressed'
        }
    return {
        'finding_state': 'skipped'
    }

@logger.inject_lambda_context(log_event=True)
def lambda_handler(event: Dict[str, Any], context):
    total_findings = 0
    event: DynamoDBStreamEvent = DynamoDBStreamEvent(event)
    if event.records:
        for record in event.records:
            if record.event_name != DynamoDBRecordEventName.REMOVE:
                control_id = record.dynamodb.keys.get('controlId', {})
                findings_list = get_findings(control_id)
                if len(findings_list.get('findings')) == 0:
                    logger.warning(f'Could not find any findings with controlId {control_id}')
                    continue
                total_findings = process_findings(findings_list.get('findings'))
        logger.info(f'Total findings processed: {total_findings}')
