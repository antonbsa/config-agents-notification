#!/usr/bin/env python3
import json
import os
import subprocess
import sys

DEFAULT_MESSAGE = "Claude precisa da sua autorização"

try:
    payload = json.load(sys.stdin)
except Exception:
    sys.exit(0)

if payload.get("notification_type") != "permission_prompt":
    sys.exit(0)

cwd = payload.get("cwd") or os.getcwd()
project = os.path.basename(os.path.abspath(cwd)) or "project"
message = payload.get("message") or DEFAULT_MESSAGE

title = f"[{project}] Aguardando permissão"

subprocess.run(
    [
        "notify-send",
        title,
        str(message),
        "--app-name=Claude Code",
        "--icon=dialog-warning",
        "--urgency=critical",
        "--expire-time=0",
    ],
    check=False,
)
