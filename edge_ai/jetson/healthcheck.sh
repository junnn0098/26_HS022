#!/usr/bin/env bash
set -euo pipefail

app_dir="${RUVIEW_APP_DIR:-/home/junwon/hanium_ruview_fall_v2}"
echo "SERVICE_STATUS"
systemctl is-active hanium-ruview-inference.service hanium-ruview-api.service
echo "UDP_5005"
ss -lunp | grep ':5005 ' || true
echo "API_HEALTH"
curl -fsS http://127.0.0.1:8080/health
echo
echo "LATEST_STATUS"
if [[ -f "$app_dir/runtime/latest_status.json" ]]; then
  python3 -m json.tool "$app_dir/runtime/latest_status.json"
else
  echo "NO_STATUS_YET"
fi

