#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" != "--confirmed-shutdown-behavior=stop" ]]; then
  echo 'First confirm EC2 instance-initiated shutdown behavior is Stop.' >&2
  exit 2
fi
if [[ "$EUID" -ne 0 ]]; then echo 'Run through sudo.' >&2; exit 2; fi
if systemctl is-active --quiet capswriter-trial-stop.timer; then
  echo 'Existing trial deadline preserved; not extended.'
  exit 0
fi
if [[ -e /etc/systemd/system/capswriter-trial-stop.timer ]]; then
  echo 'Existing trial timer needs review; not overwritten.' >&2; exit 2
fi
cat >/etc/systemd/system/capswriter-trial-stop.service <<'EOF'
[Unit]
Description=Power off approved CapsWriter trial instance
[Service]
Type=oneshot
ExecStart=/usr/bin/systemctl poweroff
EOF
STOP_AT=$(date -u -d '+22 hours' '+%Y-%m-%d %H:%M:%S UTC')
cat >/etc/systemd/system/capswriter-trial-stop.timer <<EOF
[Unit]
Description=Stop CapsWriter trial after 22 hours, reserving setup margin
[Timer]
OnCalendar=$STOP_AT
AccuracySec=1m
Persistent=true
Unit=capswriter-trial-stop.service
[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now capswriter-trial-stop.timer
systemctl list-timers capswriter-trial-stop.timer --no-pager
echo 'EBS storage continues billing after stop; this timer does not delete data.'
