from os import environ

import boto3
import yaml
from aws_lambda_powertools import Logger
from awsfindingsmanagerlib.awsfindingsmanagerlib import FindingsManager
from awsfindingsmanagerlib.backends import Backend

LOGGER = Logger()
S3_BUCKET_NAME = environ.get("S3_BUCKET_NAME")
S3_OBJECT_NAME = environ.get("S3_OBJECT_NAME")


class S3(Backend):
    def __init__(self, bucket_name, file_name):
        self._file_contents = self._get_file_contents(bucket_name, file_name)

    @staticmethod
    def _get_file_contents(bucket_name, file_name):
        s3 = boto3.resource("s3")
        return s3.Object(bucket_name, file_name).get()["Body"].read()

    def _get_rules(self):
        data = yaml.safe_load(self._file_contents)
        return data.get("Rules")


@LOGGER.inject_lambda_context(log_event=True)
def lambda_handler(event, context):
    s3_backend = S3(S3_BUCKET_NAME, S3_OBJECT_NAME)
    rules = s3_backend.get_rules()
    LOGGER.info(rules)
    findings_manager = FindingsManager()
    findings_manager.register_rules(rules)
    if findings_manager.suppress_matching_findings():
        LOGGER.info("Successfully applied all suppression rules.")
        return True
    else:
        raise RuntimeError(
            "No explicit error was raised, but not all suppression rules were applied successfully, please investigate."
        )
