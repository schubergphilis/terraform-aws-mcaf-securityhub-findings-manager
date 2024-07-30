from aws_lambda_powertools import Logger
from awsfindingsmanagerlib import FindingsManager
from strategize_findings_manager import manage

LOGGER = Logger()


@LOGGER.inject_lambda_context(log_event=True)
def lambda_handler(event, context):
    return manage(
        FindingsManager.suppress_findings_on_matching_rules,
        (event["detail"]["findings"],),
        LOGGER
    )
