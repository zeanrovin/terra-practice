"""Tiny notes API. Routes:
  GET  /api/health     -> load balancer health check
  GET  /api/notes      -> list notes
  POST /api/notes      -> {"text": "..."} creates a note
  GET  /api/heartbeat  -> last time the worker checked in
"""
import json
import os
import time
import uuid
from decimal import Decimal
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

import boto3

TABLE_NAME = os.environ["TABLE_NAME"]
table = boto3.resource("dynamodb", region_name=os.environ.get("AWS_REGION", "us-west-2")).Table(TABLE_NAME)


def to_json(obj):
    return json.dumps(obj, default=lambda o: int(o) if isinstance(o, Decimal) else str(o)).encode()


class Handler(BaseHTTPRequestHandler):
    def send(self, code, body):
        data = to_json(body)
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/api/health":
            return self.send(200, {"status": "ok"})
        if path == "/api/notes":
            items = table.scan(Limit=200).get("Items", [])
            return self.send(200, [i for i in items if i["pk"].startswith("note#")])
        if path == "/api/heartbeat":
            item = table.get_item(Key={"pk": "heartbeat#worker"}).get("Item", {})
            return self.send(200, item)
        self.send(404, {"error": "not found"})

    def do_POST(self):
        if urlparse(self.path).path != "/api/notes":
            return self.send(404, {"error": "not found"})
        length = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(length) or b"{}")
        item = {
            "pk": f"note#{uuid.uuid4()}",
            "text": str(body.get("text", ""))[:500],
            "created_at": int(time.time()),
        }
        table.put_item(Item=item)
        self.send(201, item)

    def log_message(self, fmt, *args):
        # Skip health-check noise in CloudWatch Logs
        if "/api/health" not in (args[0] if args else ""):
            super().log_message(fmt, *args)


if __name__ == "__main__":
    print(f"api listening on :8080, table={TABLE_NAME}")
    ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
