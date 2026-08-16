"""Create a ServiceNow incident from a CloudWatch/SNS alarm payload.

Credentials are loaded from AWS Secrets Manager JSON:
  { "instance": "https://devXXXX.service-now.com", "user": "admin", "password": "..." }
"""

from __future__ import annotations

import base64
import json
import os
import urllib.error
import urllib.request

import boto3

def _load_creds() -> dict:
    # Prefer Secrets Manager in AWS; always re-read so password updates apply immediately
    secret_arn = os.environ.get("SNOW_SECRET_ARN")
    if secret_arn:
        client = boto3.client("secretsmanager")
        raw = client.get_secret_value(SecretId=secret_arn)["SecretString"]
        return json.loads(raw)

    return {
        "instance": os.environ["SNOW_INSTANCE"],
        "user": os.environ["SNOW_USER"],
        "password": os.environ["SNOW_PASSWORD"],
    }


def _snow_auth_header(creds: dict) -> str:
    token = base64.b64encode(
        f"{creds['user']}:{creds['password']}".encode()
    ).decode()
    return f"Basic {token}"


def create_incident(short_description: str, description: str) -> dict:
    creds = _load_creds()
    instance = creds["instance"].rstrip("/")
    url = f"{instance}/api/now/table/incident"
    body = json.dumps(
        {
            "short_description": short_description[:160],
            "description": description,
            "category": "software",
            "urgency": "2",
            "impact": "2",
        }
    ).encode()
    req = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Accept": "application/json",
            "Authorization": _snow_auth_header(creds),
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())


def handler(event, _context):
    records = event.get("Records", [])
    results = []
    for record in records:
        msg = record.get("Sns", {}).get("Message", "{}")
        try:
            alarm = json.loads(msg)
        except json.JSONDecodeError:
            alarm = {"raw": msg}
        name = alarm.get("AlarmName", "sshd-lab-alarm")
        state = alarm.get("NewStateValue", "ALARM")
        reason = alarm.get("NewStateReason", "")
        short = (
            f"sshd down - {name}"
            if state == "ALARM"
            else f"sshd recovered - {name}"
        )
        description = (
            json.dumps(alarm, indent=2) if isinstance(alarm, dict) else str(alarm)
        )
        if reason:
            description = f"{reason}\n\n{description}"
        # Include instance id when present for remediation later
        trigger = alarm.get("Trigger") or {}
        dims = trigger.get("Dimensions") if isinstance(trigger, dict) else []
        if isinstance(dims, list):
            for dim in dims:
                if not isinstance(dim, dict):
                    continue
                if dim.get("name") == "InstanceId":
                    iid = dim.get("value")
                    description = f"InstanceId={iid}\n\n{description}"
                    if state == "ALARM" and iid:
                        short = f"sshd down on {iid}"
        try:
            snow = create_incident(short, description)
            results.append(
                {"ok": True, "sys_id": snow.get("result", {}).get("sys_id"),
                 "number": snow.get("result", {}).get("number")}
            )
        except urllib.error.HTTPError as exc:
            results.append(
                {"ok": False, "error": f"HTTP {exc.code}: {exc.read().decode()}"}
            )
        except Exception as exc:  # noqa: BLE001
            results.append({"ok": False, "error": str(exc)})
    return {"results": results}
