#!/usr/bin/env python3
import json
import os
import subprocess
import sys

AI_NOTIFY = os.path.expanduser("~/.local/bin/ai-notify")

try:
    payload = json.load(sys.stdin)
except Exception:
    sys.exit(0)

cwd = payload.get("cwd") or os.getcwd()
event = payload.get("hook_event_name")
notification_type = payload.get("notification_type")

if event == "Stop":
    subprocess.run(
        [
            AI_NOTIFY,
            "Claude",
            "finished",
            "normal",
            "utilities-terminal",
            cwd,
            str(payload.get("last_assistant_message") or ""),
        ],
        check=False,
    )
elif event in (None, "Notification") and notification_type == "permission_prompt":
    subprocess.run(
        [
            AI_NOTIFY,
            "Claude",
            "waiting for approval",
            "critical",
            "dialog-warning",
            cwd,
            "",
        ],
        check=False,
    )
