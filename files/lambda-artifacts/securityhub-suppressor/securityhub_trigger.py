from os import environ

from aws_lambda_powertools import Logger
from awsfindingsmanagerlib import FindingsManager, S3

LOGGER = Logger()
S3_BUCKET_NAME = environ.get("S3_BUCKET_NAME")
S3_OBJECT_NAME = environ.get("S3_OBJECT_NAME")


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
