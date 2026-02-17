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
                    "Variable": "$.TaskResult.Payload.finding_state",
                    "IsPresent": false
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
%{~ if length(include_product_names) > 0 }
              {
                "Comment": "PRODUCT NAME FILTER: Only process findings with ProductName in the include list",
                "Or": [
%{~ for idx, product_name in include_product_names }
                  {
                    "Variable": "$.detail.findings[0].ProductName",
                    "StringEquals": "${product_name}"
                  }%{if idx < length(include_product_names) - 1},%{endif}
%{~ endfor }
                ]
              },
%{ endif ~}
              %{~ if jira_autoclose_enabled }
              {
                "Or": [
                  {
                    "Comment": "CREATE JIRA TICKET: Requires severity >= threshold AND no existing Jira issue",
                    "And": [
                      {
                        "Variable": "$.detail.findings[0].Severity.Normalized",
                        "NumericGreaterThanEquals": ${finding_severity_normalized}
                      },
                      {
                        "Variable": "$.detail.findings[0].Workflow.Status",
                        "StringEquals": "NEW"
                      },
                      {
                        "Variable": "$.detail.findings[0].RecordState",
                        "StringEquals": "ACTIVE"
                      },
                      {
                        "Or": [
                          {
                            "Variable": "$.detail.findings[0].Compliance.Status",
                            "IsPresent": false
                          },
                          {
                            "And": [
                              {
                                "Variable": "$.detail.findings[0].Compliance.Status",
                                "IsPresent": true
                              },
                              {
                                "Or": [
                                  {
                                    "Variable": "$.detail.findings[0].Compliance.Status",
                                    "StringEquals": "FAILED"
                                  },
                                  {
                                    "Variable": "$.detail.findings[0].Compliance.Status",
                                    "StringEquals": "WARNING"
                                  }
                                ]
                              }
                            ]
                          }
                        ]
                      },
                      {
                        "Comment": "Prevent duplicate Jira creation: Ensure no existing jiraIssue in Note",
                        "Not": {
                          "And": [
                            {
                              "Variable": "$.detail.findings[0].Note.Text",
                              "IsPresent": true
                            },
                            {
                              "Variable": "$.detail.findings[0].Note.Text",
                              "StringMatches": "*jiraIssue*"
                            }
                          ]
                        }
                      }
                    ]
                  },
                  {
                    "Comment": "CLOSE JIRA TICKET: Works at ANY severity (ticket already exists)",
                    "And": [
                      {
                        "Or": [
                          {
                            "Variable": "$.detail.findings[0].Workflow.Status",
                            "StringEquals": "RESOLVED"
                          },
                          {
                            "And": [
                              {
                                "Variable": "$.detail.findings[0].Workflow.Status",
                                "StringEquals": "NOTIFIED"
                              },
                              {
                                "Or": [
                                  {
                                    "Variable": "$.detail.findings[0].RecordState",
                                    "StringEquals": "ARCHIVED"
                                  },
                                  {
                                    "And": [
                                      {
                                        "Variable": "$.detail.findings[0].Compliance.Status",
                                        "IsPresent": true
                                      },
                                      {
                                        "Or": [
                                          {
                                            "Variable": "$.detail.findings[0].Compliance.Status",
                                            "StringEquals": "PASSED"
                                          },
                                          {
                                            "Variable": "$.detail.findings[0].Compliance.Status",
                                            "StringEquals": "NOT_AVAILABLE"
                                          }
                                        ]
                                      }
                                    ]
                                  }
                                ]
                              }
                            ]
                          }
                        ]
                      },
                      {
                        "Variable": "$.detail.findings[0].Note.Text",
                        "IsPresent": true
                      },
                      {
                        "Variable": "$.detail.findings[0].Note.Text",
                        "StringMatches": "*jiraIssue*"
                      }
                    ]
                  }
                ]
              }
              %{ else }
              {
                "And": [
                  {
                    "Variable": "$.detail.findings[0].Severity.Normalized",
                    "NumericGreaterThanEquals": ${finding_severity_normalized}
                  },
                  {
                    "Variable": "$.detail.findings[0].Workflow.Status",
                    "StringEquals": "NEW"
                  }
                ]
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
