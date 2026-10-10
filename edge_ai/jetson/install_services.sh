#!/usr/bin/env bash
set -euo pipefail

app_dir="${1:-/home/junwon/hanium_ruview_fall_v2}"
checkpoint="${2:-$app_dir/models/production/best_model.pt}"
cough_checkpoint="${3:-$app_dir/models/production/best_cough_model.pt}"
app_user="$(id -un)"

if [[ ! -f "$checkpoint" ]]; then
  echo "FALL_CHECKPOINT_NOT_FOUND=$checkpoint; installing health-only service" >&2
fi
if [[ ! -f "$app_dir/config/default_config.json" ]]; then
  echo "CONFIG_NOT_FOUND=$app_dir/config/default_config.json" >&2
  exit 3
fi

mkdir -p "$app_dir/runtime"
chmod +x "$app_dir/jetson/python.sh" "$app_dir/jetson/run_live.sh" "$app_dir/jetson/run_api.sh"

inference_tmp="$(mktemp)"
api_tmp="$(mktemp)"
trap 'rm -f "$inference_tmp" "$api_tmp"' EXIT
sed -e "s|@USER@|$app_user|g" -e "s|@APP_DIR@|$app_dir|g" \
  "$app_dir/jetson/hanium-ruview-inference.service.in" > "$inference_tmp"
sed -e "s|@USER@|$app_user|g" -e "s|@APP_DIR@|$app_dir|g" \
  "$app_dir/jetson/hanium-ruview-api.service.in" > "$api_tmp"

env_tmp="$(mktemp)"
trap 'rm -f "$inference_tmp" "$api_tmp" "$env_tmp"' EXIT
cat > "$env_tmp" <<EOF
RUVIEW_APP_DIR=$app_dir
RUVIEW_CHECKPOINT=$checkpoint
RUVIEW_COUGH_CHECKPOINT=$cough_checkpoint
RUVIEW_NODES=1,2,3,4
RUVIEW_BOARD_IP=
RUVIEW_API_PORT=8080
RUVIEW_API_TOKEN=${RUVIEW_API_TOKEN:-}
EOF

sudo install -m 0644 "$inference_tmp" /etc/systemd/system/hanium-ruview-inference.service
sudo install -m 0644 "$api_tmp" /etc/systemd/system/hanium-ruview-api.service
sudo install -m 0600 "$env_tmp" /etc/hanium-ruview-fall.env
sudo systemctl daemon-reload
sudo systemctl enable --now hanium-ruview-inference.service hanium-ruview-api.service
echo "SERVICES_INSTALLED"
sudo systemctl --no-pager --full status hanium-ruview-inference.service | head -n 20
sudo systemctl --no-pager --full status hanium-ruview-api.service | head -n 20
