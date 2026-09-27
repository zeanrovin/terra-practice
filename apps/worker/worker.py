"""Background worker: no port, no load balancer.
Writes a heartbeat to DynamoDB every 60 seconds."""
import os
import time

import boto3

table = boto3.resource("dynamodb", region_name=os.environ.get("AWS_REGION", "us-west-2")).Table(os.environ["TABLE_NAME"])

while True:
    now = int(time.time())
    table.put_item(Item={"pk": "heartbeat#worker", "updated_at": now})
    print(f"heartbeat written at {now}")
    time.sleep(60)
