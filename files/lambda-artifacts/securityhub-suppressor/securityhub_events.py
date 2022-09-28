import os
from dataclasses import dataclass
from datetime import datetime
from re import search
from typing import Any
from typing import Dict
from typing import Optional
from typing import Tuple
from typing import Union

import boto3
import jmespath
from aws_lambda_powertools import Logger
from aws_lambda_powertools.utilities.data_classes import EventBridgeEvent
from aws_lambda_powertools.utilities.typing import LambdaContext

from yaml_parser import get_file_contents

logger = Logger()
VALID_STATUSES = ['FAILED', 'HIGH']
DYNAMODB_TABLE_NAME = os.environ['DYNAMODB_TABLE_NAME']
YAML_CONFIGURATION_FILE = 'suppressor.yml'
SUPPRESSED_FINDINGS = []


@dataclass
class Finding:
    finding_id: str
    product_arn: str
    product_name: str


@dataclass
class SuppressionRule:
    action: str
    rules: [str]
    notes: str
    dry_run: Optional[bool]


@dataclass
class SuppressionEntry:
    control_id: str
    data: [SuppressionRule]


class SuppressionList:
    def __init__(self, boto_client, hash_key) -> None:
        self._entries = []
        self.hash_key = hash_key
        self.boto_client = boto_client
        self.table = self.data_source

    @property
    def data_source(self):
        dynamodb = self.boto_client.resource('dynamodb')
        return dynamodb.Table(name=DYNAMODB_TABLE_NAME)

    @property
    def entries(self) -> list:
        if not self.hash_key:
            logger.info(f'Invalid hash key: {self.hash_key}')
            return self._entries
        if not self._entries:
            logger.info(f'Fetching suppression list from dynamoDB {DYNAMODB_TABLE_NAME}, hash key: {self.hash_key}')
            rules = self.table.get_item(Key={"controlId": self.hash_key})
            for rule in rules.get('Item', {}).get('data', {}):
                self._entries.append(
                    SuppressionRule(action=rule.get('action'),
                                    rules=rule.get('rules'),
                                    notes=rule.get('notes'),
                                    dry_run=rule.get('dry_run', False))
                )
        return self._entries


class Suppressor:
    def __init__(self, boto_client,
                 finding: Finding,
                 resource_id: str,
                 suppression_list: SuppressionList) -> None:
        self.boto_client = boto_client
        self._finding = finding
        self._security_hub = boto_client.client('securityhub')
        self.resource_id = resource_id
        self.suppression_list = suppression_list
        self._suppression_rule = None
        self.matched_rule = None
        SUPPRESSED_FINDINGS.clear()

    @property
    def finding(self) -> Finding:
        return self._finding

    @property
    def rule(self) -> SuppressionRule:
        if not self._suppression_rule:
            self._suppression_rule = self.evaluate_rule()
        return self._suppression_rule

    @staticmethod
    def validate(finding_event: Dict[str, Any]) -> Union[bool, Finding]:
        product_arn = finding_event.get('ProductArn', '')
        if not product_arn:
            raise ValueError('Error: no product_arn found')
        finding_id = finding_event.get('Id', '')
        if not finding_id:
            raise ValueError('Error: no finding_id found')
        product_details = finding_event.get('ProductFields', {})
        if not product_details:
            raise ValueError('Error: no product fields found')
        product_name = product_details.get('aws/securityhub/ProductName', '')
        if not product_name:
            raise ValueError('Error: no product name found')
        return Finding(product_arn=product_arn, finding_id=finding_id, product_name=product_name)

    @staticmethod
    def get_product_details(finding_event: Dict[str, Any], product_name: str) -> Tuple[None, None]:
        key, status = None, None
        yaml_config = get_file_contents(YAML_CONFIGURATION_FILE)
        if not yaml_config.get(product_name):
            logger.warning(f'No YAML configuration for product {product_name}')
            return key, status
        key = jmespath.search(yaml_config.get(product_name, {}).get('key'), finding_event)
        status = jmespath.search(yaml_config.get(product_name, {}).get('status'), finding_event)
        return key, status

    def evaluate_rule(self) -> Optional[SuppressionRule]:
        for entry in self.suppression_list.entries:
            match = next((rule for rule in entry.rules if search(rule, self.resource_id)), None)
            if match:
                self.matched_rule = match
                return entry
        return None

    def suppress_finding(self) -> bool:
        if not self.rule:
            logger.info(f'Skipping finding because {self.resource_id} is not in the suppression list')
            return False
        if not self.rule.notes:
            logger.error('Error: a valid notes must be added to the dynamoDB entry')
            return False
        if self.rule.dry_run:
            action_output = 'DRY RUN - Would'
        else:
            action_output = 'Will'

        logger.info(f'{action_output} perform Suppression on finding {self.finding.finding_id}, '
                    f'matched rule: {self.matched_rule}, '
                    f'action: {self.rule.action}')
        SUPPRESSED_FINDINGS.append(self.finding.finding_id)
        now = datetime.now()

        if self.rule.dry_run:
            return True

        return self._security_hub.batch_update_findings(FindingIdentifiers=[
            {
                'Id': self.finding.finding_id,
                'ProductArn': self.finding.product_arn
            }],
            Workflow={'Status': self.rule.action},
            Note={'Text': f'{self.rule.notes} - '
                          f'Suppressed by the Security Hub Suppressor at {now.strftime("%Y-%m-%d %H:%M:%S")}',
                  'UpdatedBy': 'landingzone'})


def validate_event(event: EventBridgeEvent):
    for event_entries in event.detail.get('findings', []):
        finding = Suppressor.validate(event_entries)
        hash_key, status = Suppressor.get_product_details(event_entries, finding.product_name)
        if status not in VALID_STATUSES:
            raise ValueError(f'Skipping execution because status is {status}. Valid statuses: {VALID_STATUSES}')
        if not hash_key:
            raise ValueError(f'Error: no hash_key found for product {finding.product_name}')
        workflow_status = event_entries.get('Workflow', {}).get('Status', {})
        if workflow_status == "SUPPRESSED":
            raise ValueError(f'Skipping execution because workflow status is {workflow_status}')
    return True


def _parse_fields(event):
    finding, resource_id, hash_key = None, None, None
    for event_entries in event.get('detail').get('findings', []):
        finding = Suppressor.validate(event_entries)
        hash_key, status = Suppressor.get_product_details(event_entries, finding.product_name)
        resource_id = [resource.get('Id') for resource in event_entries.get('Resources', [])].pop()
    return finding, resource_id, hash_key


def suppress(event):
    finding, resource_id, hash_key = _parse_fields(event)
    suppression_list = get_suppression_list(hash_key)
    return Suppressor(boto_client=boto3,
                      finding=finding,
                      resource_id=resource_id,
                      suppression_list=suppression_list).suppress_finding()


def get_suppression_list(hash_key) -> SuppressionList:
    suppression_list = SuppressionList(hash_key=hash_key, boto_client=boto3)
    if not suppression_list.entries:
        logger.error(f'Could not find any rules for control {hash_key}')
    return suppression_list


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
