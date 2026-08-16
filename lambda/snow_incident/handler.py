"""Create a ServiceNow incident from a CloudWatch/SNS alarm payload."""

from __future__ import annotations

import base64
import json
import os
import urllib.error
import urllib.request


def _snow_auth_header() -> str:
    user = os.environ["SNOW_USER"]
    password = os.environ["SNOW_PASSWORD"]
    token = base64.b64encode(f"{user}:{password}".encode()).decode()
    return f"Basic {token}"


def create_incident(short_description: str, description: str) -> dict:
    instance = os.environ["SNOW_INSTANCE"].rstrip("/")
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
            "Authorization": _snow_auth_header(),
        },
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())


def handler(event, _context):
    # SNS wraps the CloudWatch alarm JSON
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
        short = f"sshd down — {name}" if state == "ALARM" else f"sshd recovered — {name}"
        description = json.dumps(alarm, indent=2) if isinstance(alarm, dict) else str(alarm)
        if reason:
            description = f"{reason}\n\n{description}"
        try:
            snow = create_incident(short, description)
            results.append({"ok": True, "sys_id": snow.get("result", {}).get("sys_id")})
        except urllib.error.HTTPError as exc:
            results.append({"ok": False, "error": f"HTTP {exc.code}: {exc.read().decode()}"})
        except Exception as exc:  # noqa: BLE001 — surface to CloudWatch logs
            results.append({"ok": False, "error": str(exc)})
    return {"results": results}
