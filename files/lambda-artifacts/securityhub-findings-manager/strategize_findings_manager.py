from os import environ
from aws_lambda_powertools import Logger
from awsfindingsmanagerlib import S3, FindingsManager, NoteTextConfig

S3_BUCKET_NAME = environ.get("S3_BUCKET_NAME")
S3_OBJECT_NAME = environ.get("S3_OBJECT_NAME")


def _initialize_findings_manager(logger: Logger) -> FindingsManager:
    s3_backend = S3(S3_BUCKET_NAME, S3_OBJECT_NAME)
    rules = s3_backend.get_rules()
    logger.info(rules)
    # Note: NoteTextConfig(format="json") enables awsfindingsmanagerlib 1.4.0+ to merge suppression notes
    # with existing Jira ticket metadata, preserving jiraIssue and jiraInstance fields for autoclose functionality
    findings_manager = FindingsManager(note_text=NoteTextConfig(format="json"))
    findings_manager.register_rules(rules)
    return findings_manager


def manage(func, args, logger: Logger):
    try:
        findings_manager = _initialize_findings_manager(logger)
    except Exception as e:
        logger.error("Findings manager failed to initialize, please investigate.")
        logger.error(f"Original error: {e}", exc_info=True)
        return {"finding_state": "skipped"}

    try:
        success, suppressed_payload = getattr(findings_manager, func.__name__)(*args)
    except Exception as e:
        logger.error("Findings manager failed to apply findings management rules, please investigate.")
        logger.error(f"Original error: {e}", exc_info=True)
        return {"finding_state": "skipped"}

    if success:
        logger.info("Successfully applied all findings management rules.")
        return suppression_logging(logger, suppressed_payload)
    else:
        logger.error(
            "No explicit error was raised, but not all findings management rules were applied successfully, please investigate."
        )
        return {"finding_state": "skipped"}


def manager_per_rule(rule: list, logger: Logger):
    try:
        logger.info(f"Processing rule: {rule}")
        # Note: NoteTextConfig(format="json") enables awsfindingsmanagerlib 1.4.0+ to merge suppression notes
        # with existing Jira ticket metadata, preserving jiraIssue and jiraInstance fields for autoclose functionality
        findings_manager_per_rule = FindingsManager(note_text=NoteTextConfig(format="json"))
        findings_manager_per_rule.register_rules([rule])
        success, suppressed_payload = findings_manager_per_rule.suppress_matching_findings()
    except Exception as e:
        logger.error("Findings manager failed to apply findings management rules, please investigate.")
        logger.error(f"Original error: {e}", exc_info=True)
        return {"finding_state": "skipped"}

    if success:
        logger.info("Successfully applied all findings management rules.")
        return suppression_logging(logger, suppressed_payload)
    else:
        logger.error(
            "No explicit error was raised, but not all findings management rules were applied successfully, please investigate."
        )
        return {"finding_state": "skipped"}


def get_rules(logger: Logger):
    try:
        findings_manager = _initialize_findings_manager(logger)
    except Exception as e:
        logger.error("Findings manager failed to initialize, please investigate.")
        logger.error(f"Original error: {e}", exc_info=True)
        return {"finding_state": "skipped"}
    return findings_manager.rules


def suppression_logging(logger: Logger, suppressed_payload: list):
    if len(suppressed_payload) > 0:
        for chunk in suppressed_payload:
            note_text = chunk["Note"]["Text"]
            workflow_status = chunk["Workflow"]["Status"]
            count = len(chunk["FindingIdentifiers"])
            logger.info(f"{count} finding(s) {workflow_status} with note: {note_text}.")
        return {"finding_state": "suppressed"}
    else:
        logger.info("No findings were suppressed.")
        return {"finding_state": "skipped"}
