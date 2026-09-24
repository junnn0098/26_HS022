#!/usr/bin/env bash
set -euo pipefail

app_dir="${RUVIEW_APP_DIR:-/home/junwon/hanium_ruview_fall_v2}"
cd "$app_dir"
exec "$app_dir/jetson/python.sh" -u -m hanium_fall_v2.status_api \
  --bind 0.0.0.0 \
  --port "${RUVIEW_API_PORT:-8080}" \
  --status-file "$app_dir/runtime/latest_status.json" \
  --event-log "$app_dir/runtime/events.jsonl" \
  --token "${RUVIEW_API_TOKEN:-}"
