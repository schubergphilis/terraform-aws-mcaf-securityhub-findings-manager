from os import environ

from aws_lambda_powertools import Logger
from awsfindingsmanagerlib import FindingsManager, S3

LOGGER = Logger()
S3_BUCKET_NAME = environ.get("S3_BUCKET_NAME")
S3_OBJECT_NAME = environ.get("S3_OBJECT_NAME")

_s3_backend = S3(S3_BUCKET_NAME, S3_OBJECT_NAME)
RULES = _s3_backend.get_rules()
FINDINGS_MANAGER = FindingsManager()
FINDINGS_MANAGER.register_rules(RULES)


@LOGGER.inject_lambda_context(log_event=True)
def lambda_handler(event, context):
    LOGGER.info(RULES)
    if FINDINGS_MANAGER.suppress_findings_on_matching_rules(event["detail"]["findings"]):
        LOGGER.info("Successfully applied all suppression rules.")
        return {"finding_state": "suppressed"}
    else:
        LOGGER.warning(
            "No explicit error was raised, but not all suppression rules were applied successfully, please investigate."
        )
        return {"finding_state": "skipped"}
