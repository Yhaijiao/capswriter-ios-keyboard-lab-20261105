#!/usr/bin/env bash
set -euo pipefail
# Stage sanitized private source and models first; install_tls.sh is independent.
if [[ "$EUID" -ne 0 ]]; then echo 'Run through sudo after inspecting this script.' >&2; exit 2; fi
BASE=/srv/capswriter
if [[ ! -f "$BASE/app/cloud/runtime.py" || ! -f "$BASE/private/desktop/private-manifest.json" ]]; then
  echo 'Stage the public app and sanitized private export/models first.' >&2; exit 2
fi
if ! systemctl is-active --quiet capswriter-trial-stop.timer; then
  echo 'Install the confirmed Stop-behavior trial guard before dependency setup.' >&2; exit 2
fi
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y python3-venv python3-pip git ffmpeg espeak-ng libgomp1 libsndfile1
id capswriter >/dev/null 2>&1 || useradd --system --home "$BASE" --shell /usr/sbin/nologin capswriter
install -d -m 0700 "$BASE/private/state/tmp" "$BASE/private/hotword-backups"
export TMPDIR="$BASE/private/state/tmp"
export PIP_CACHE_DIR="$BASE/private/state/pip-cache"
python3 -m venv "$BASE/venv-asr"
python3 -m venv "$BASE/venv-bridge"
"$BASE/venv-asr/bin/pip" install -r "$BASE/app/cloud/requirements-asr.txt"
"$BASE/venv-bridge/bin/pip" install -r "$BASE/app/bridge/requirements.txt"
"$BASE/venv-asr/bin/python" -B "$BASE/app/cloud/install_native.py" --private-root "$BASE/private/desktop"
"$BASE/venv-asr/bin/python" -B "$BASE/app/cloud/preflight.py" --private-root "$BASE/private/desktop" --load-native
if [[ ! -f "$BASE/private/bridge-token.txt" ]]; then
  "$BASE/venv-bridge/bin/python" - <<'PY'
from pathlib import Path
import secrets
p=Path('/srv/capswriter/private/bridge-token.txt')
with p.open('x') as stream: stream.write(secrets.token_urlsafe(32)+'\n')
p.chmod(0o600)
PY
fi
chown -R capswriter:capswriter "$BASE/private"
chmod 0700 "$BASE/private" "$BASE/private/desktop"
# Application code remains root-owned; the gateway API whitelists hot.txt saves.
install -m 0644 "$BASE/app/cloud/capswriter-asr.service" /etc/systemd/system/
install -m 0644 "$BASE/app/cloud/capswriter-gateway.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now capswriter-asr.service
systemctl enable --now capswriter-gateway.service
"$BASE/venv-bridge/bin/python" - <<'PY'
from pathlib import Path
import json,urllib.request
token=Path('/srv/capswriter/private/bridge-token.txt').read_text().strip()
request=urllib.request.Request('http://127.0.0.1:8765/v1/status',headers={'Authorization':'Bearer '+token})
with urllib.request.urlopen(request,timeout=10) as response: status=json.load(response)
assert status.get('asr_ready') is True and status.get('voice_enabled') is True
print('Local authenticated ASR ready; public TLS and phone WAN recording still require validation.')
PY
