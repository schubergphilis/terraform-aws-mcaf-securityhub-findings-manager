import boto3
import os
import yaml

table_name = os.environ.get("SUPPRESSIONS_TABLE_NAME", "securityhub-suppression-list")

with open("suppressions.yml") as f:
    suppressions = yaml.safe_load(f.read())

dynamodb_client = boto3.client("dynamodb")

# Upsert existing items
for suppression_id in suppressions.get("Suppressions", {}):
    dynamodb_client.put_item(
        TableName=table_name,
        Item={
            "controlId": {
                "S": suppression_id
            },
            "data": {
                "L": [
                    {
                        "M": {
                            "action": {"S": item["action"]},
                            "rules": {"SS": item["rules"]},
                            "notes": {"S": item["notes"]}
                        }
                    }
                    for item in suppressions["Suppressions"][suppression_id]
                ]
            }
        }
    )
    print("Upserted rule with control ID {} in suppression table.".format(
        suppression_id
    ))

# Remove rules no longer in the suppressions config
scan_paginator = dynamodb_client.get_paginator("scan")
scan_pages = scan_paginator.paginate(
    TableName=table_name
)

for scan_page in scan_pages:
    for item in scan_page.get("Items", []):
        if item["controlId"]["S"] not in suppressions.get("Suppressions", {}).keys():
            dynamodb_client.delete_item(
                TableName=table_name,
                Key={
                    "controlId": {"S": item["controlId"]["S"]}
                }
            )
            print("Removed rule with control ID {} from suppression table.".format(
                item["controlId"]["S"]
            ))
