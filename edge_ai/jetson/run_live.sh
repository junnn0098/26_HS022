#!/usr/bin/env bash
set -euo pipefail

app_dir="${RUVIEW_APP_DIR:-/home/junwon/hanium_ruview_fall_v2}"
checkpoint="${RUVIEW_CHECKPOINT:-$app_dir/models/production/best_model.pt}"
cough_checkpoint="${RUVIEW_COUGH_CHECKPOINT:-$app_dir/models/production/best_cough_model.pt}"
nodes="${RUVIEW_NODES:-1,2,3,4}"
board_ip="${RUVIEW_BOARD_IP:-}"
source_args=()
if [[ -n "$board_ip" ]]; then
  source_args=(--allow-source "$board_ip")
fi
model_args=()
if [[ -f "$checkpoint" ]]; then
  model_args+=(--checkpoint "$checkpoint")
else
  echo "FALL_CHECKPOINT_NOT_INSTALLED=$checkpoint; health monitoring will start first" >&2
fi
if [[ -f "$cough_checkpoint" ]]; then
  model_args+=(--cough-checkpoint "$cough_checkpoint")
else
  echo "COUGH_CHECKPOINT_NOT_INSTALLED=$cough_checkpoint; cough-like candidates only" >&2
fi

cd "$app_dir"
exec "$app_dir/jetson/python.sh" -u -m hanium_fall_v2.live_inference \
  --bind 0.0.0.0 \
  --port 5005 \
  --nodes "$nodes" \
  --runtime-config "$app_dir/config/default_config.json" \
  --status-file "$app_dir/runtime/latest_status.json" \
  --event-log "$app_dir/runtime/events.jsonl" \
  "${model_args[@]}" \
  "${source_args[@]}"
