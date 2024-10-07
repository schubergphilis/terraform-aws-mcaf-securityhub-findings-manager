{
    "Comment": "Step Function to orchestrate Security Hub findings manager Lambda functions",
    "StartAt": "ChoiceSuppressor",
    "States": {
      "ChoiceSuppressor": {
        "Type": "Choice",
        "Choices": [
          {
            "Or": [
              {
                "Variable": "$.detail.findings[0].Workflow.Status",
                "StringEquals": "NEW"
              },
              {
                "Variable": "$.detail.findings[0].Workflow.Status",
                "StringEquals": "NOTIFIED"
              }
            ],
            "Next": "invoke-securityhub-findings-manager-events"
          }
        ],
        "Default": "ChoiceJiraIntegration"
      },
      "invoke-securityhub-findings-manager-events": {
        "Type": "Task",
        "Resource": "arn:aws:states:::lambda:invoke",
        "Parameters": {
          "Payload.$": "$",
          "FunctionName": "${findings_manager_events_lambda}"
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
            "Next": "ChoiceJiraIntegration",
            "ResultPath": "$.error"
          }
        ],
        "Next": "ChoiceJiraIntegration",
        "ResultPath": "$.TaskResult"
      },
      "ChoiceJiraIntegration": {
        "Type": "Choice",
        "Choices": [
          {
            "And": [
              {
                "Or": [
                  {
                    "Not": {
                      "Variable": "$.TaskResult.Payload.finding_state",
                      "IsPresent": true
                    }
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
                      }
                    ]
                  }
                ]
              },
              {
                "Variable": "$.detail.findings[0].Severity.Normalized",
                "NumericGreaterThanEquals": ${finding_severity_normalized}
              },
              %{~ if jira_autoclose_enabled }
              {
                "Or": [
                  {
                    "Variable": "$.detail.findings[0].Workflow.Status",
                    "StringEquals": "NEW"
                  },
                  {
                    "Variable": "$.detail.findings[0].Workflow.Status",
                    "StringEquals": "RESOLVED"
                  }
                ]
              }
              %{ else }
              {
                "Variable": "$.detail.findings[0].Workflow.Status",
                "StringEquals": "NEW"
              }
              %{ endif ~}
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
          "FunctionName": "${jira_lambda}"
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
