from os import environ

from aws_lambda_powertools import Logger
from awsfindingsmanagerlib import S3, FindingsManager

S3_BUCKET_NAME = environ.get("S3_BUCKET_NAME")
S3_OBJECT_NAME = environ.get("S3_OBJECT_NAME")

def _initialize_findings_manager(logger: Logger) -> FindingsManager:
    s3_backend = S3(S3_BUCKET_NAME, S3_OBJECT_NAME)
    rules = s3_backend.get_rules()
    logger.info(rules)
    findings_manager = FindingsManager()
    findings_manager.register_rules(rules)
    return findings_manager

def manage(func, args, logger: Logger):
    try:
        findings_manager = _initialize_findings_manager(logger)
    except Exception as e:
        logger.warning("Findings manager failed to initialize, please investigate.")
        logger.info(f"Original error: {e}", exc_info=True)
        return {"finding_state": "skipped"}

    try:
        success = getattr(findings_manager, func.__name__)(*args)
    except Exception as e:
        logger.warning("Findings manager failed to apply findings management rules, please investigate.")
        logger.info(f"Original error: {e}", exc_info=True)
        return {"finding_state": "skipped"}

    if success:
        logger.info("Successfully applied all findings management rules.")
        return {"finding_state": "suppressed"}
    else:
        logger.warning(
            "No explicit error was raised, but not all findings management rules were applied successfully, please investigate."
        )
        return {"finding_state": "skipped"}
