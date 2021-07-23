#!/usr/bin/env python
import json
import os
import urllib.request
from pprint import pprint

job_status = os.environ["JOB_STATUS"]
github = json.loads(os.environ["GITHUB_ENVIRONMENT"])
actor = github["actor"]
workflow = github["workflow"]
repository = github["repository"]
run_id = github["run_id"]

html_url = github["event"]["repository"]["html_url"]
run_description = {"success": "ran", "cancelled": "cancelled", "failure": "failed"}[
    job_status
]
run_emoji = {"success": "🎉", "cancelled": "💥", "failure": "💥"}[job_status]

fallback = f"{repository} - {actor} {run_description} <{html_url}/actions/runs/{run_id}|{workflow}> {run_emoji}"
color = {
    "success": "good",
    "cancelled": "warning",
    "failure": "danger",
}[job_status]
field = {
    "title": repository,
    "value": f"{actor} {run_description} <{html_url}/actions/runs/{run_id}|{workflow}> {run_emoji}",
    "short": False,
}
fields = [field]
if os.environ["CUSTOM_MESSAGE"]:
    fields.append({"value": os.environ["CUSTOM_MESSAGE"]})

body = {
    "attachments": [{"fallback": fallback, "color": color, "fields": fields}],
}

request = urllib.request.Request(
    os.environ["SLACK_WEBHOOK"], 
    json.dumps(body).encode("utf-8"),
    { "Content-Type": "application/json" }
)

with urllib.request.urlopen(request) as response:
    print("Status:")
    pprint(response.status)
    print("Response body:")
    pprint(response.read())
