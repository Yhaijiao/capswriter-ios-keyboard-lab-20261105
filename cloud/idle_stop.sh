#!/usr/bin/env bash
# Power the instance off after CAPSWRITER_IDLE_MINUTES (default 30) without a
# recognition request. The gateway touches the activity file on every POST; it
# holds a timestamp only, never audio or text. EC2 shutdown behavior must be
# Stop so the disk and models are kept.
set -euo pipefail
ACTIVITY=${CAPSWRITER_ACTIVITY_FILE:-/srv/capswriter/private/state/last-activity}
IDLE_MINUTES=${CAPSWRITER_IDLE_MINUTES:-30}
now=$(date +%s)
boot=$(( now - $(cut -d. -f1 /proc/uptime) ))
last=$boot
if [[ -f "$ACTIVITY" ]]; then
  seen=$(stat -c %Y "$ACTIVITY")
  (( seen > last )) && last=$seen
fi
idle=$(( (now - last) / 60 ))
if (( idle >= IDLE_MINUTES )); then
  logger -t capswriter-idle "idle ${idle} min >= ${IDLE_MINUTES}; powering off"
  systemctl --no-block poweroff
fi
