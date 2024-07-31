{
    "Comment": "Step Function to orchestrate Security Hub findings manager Lambda functions",
    "StartAt": "invoke-securityhub-findings-manager-events",
    "States": {
      "invoke-securityhub-findings-manager-events": {
        "Type": "Task",
        "Resource": "arn:aws:states:::lambda:invoke",
        "Parameters": {
          "Payload.$": "$",
          "FunctionName": "${lambda_findings_manager_events_arn}"
        },
        "Retry": [
          {
            "ErrorEquals": [
              "Lambda.ServiceException",
              "Lambda.AWSLambdaException",
              "Lambda.SdkClientException"
            ],
            "IntervalSeconds": 2,
            "MaxAttempts": 6,
            "BackoffRate": 2
          }
        ],
        "Catch": [
          {
            "ErrorEquals": [
              "States.TaskFailed"
            ],
            "Comment": "Catch all task failures",
            "Next": "Choice",
            "ResultPath": "$.error"
          }
        ],
        "Next": "Choice",
        "ResultPath": "$.TaskResult"
      },
      "Choice": {
        "Type": "Choice",
        "Choices": [
          {
            "And": [
              {
                "Not": {
                  "Variable": "$.TaskResult.Payload.finding_state",
                  "IsPresent": true
                }
              },
              {
                "Variable": "$.detail.findings[0].Severity.Normalized",
                "NumericGreaterThanEquals": ${finding_severity_normalized}
              },
              {
                "Variable": "$.detail.findings[0].Workflow.Status",
                "StringEquals": "NEW"
              }
            ],
            "Next": "invoke-securityhub-jira"
          },
          {
            "And": [
              {
                "Variable": "$.TaskResult.Payload.finding_state",
                "IsPresent": true
              },
              {
                "Variable": "$.TaskResult.Payload.finding_state",
                "StringEquals": "skipped"
              },
              {
                "Variable": "$.detail.findings[0].Severity.Normalized",
                "NumericGreaterThanEquals": ${finding_severity_normalized}
              },
              {
                "Variable": "$.detail.findings[0].Workflow.Status",
                "StringEquals": "NEW"
              }
            ],
            "Next": "invoke-securityhub-jira"
          }
        ],
        "Default": "Success"
      },
      "Success": {
        "Type": "Succeed"
      },
      "invoke-securityhub-jira": {
        "Type": "Task",
        "Resource": "arn:aws:states:::lambda:invoke",
        "OutputPath": "$.Payload",
        "Parameters": {
          "Payload.$": "$",
          "FunctionName": "${lambda_securityhub_jira_arn}"
        },
        "Retry": [
          {
            "ErrorEquals": [
              "Lambda.ServiceException",
              "Lambda.AWSLambdaException",
              "Lambda.SdkClientException"
            ],
            "IntervalSeconds": 2,
            "MaxAttempts": 6,
            "BackoffRate": 2
          }
        ],
        "End": true
      }
    }
  }
