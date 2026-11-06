#!/usr/bin/env bash
set -euo pipefail
# Run this independently, before model upload, once the exact trial and CA terms
# are authorized. Only the ACME challenge is public on HTTP; ASR stays loopback.
PUBLIC_IP=${1:-}
TOS_CONFIRMATION=${2:-}
if [[ "$EUID" -ne 0 ]]; then echo 'Run through sudo.' >&2; exit 2; fi
if [[ "$TOS_CONFIRMATION" != '--acme-tos-accepted' ]]; then
  echo 'Explicit acceptance of current Lets Encrypt ACME terms is required.' >&2; exit 2
fi
python3 - "$PUBLIC_IP" <<'PY'
import ipaddress,sys
ip=ipaddress.ip_address(sys.argv[1])
assert ip.version==4 and ip.is_global, 'Approved public IPv4 required'
PY
BASE=/srv/capswriter
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y python3-venv nginx
install -d -m 0755 "$BASE/acme"
install -d -m 0700 "$BASE/private/state/tmp"
export TMPDIR="$BASE/private/state/tmp"
export PIP_CACHE_DIR="$BASE/private/state/pip-cache"
python3 -m venv "$BASE/venv-certbot"
"$BASE/venv-certbot/bin/pip" install 'certbot>=5.4,<6'
sed "s/__PUBLIC_IP__/$PUBLIC_IP/g" "$SCRIPT_DIR/nginx-http.conf.template" >/etc/nginx/conf.d/capswriter.conf
nginx -t
systemctl enable --now nginx
systemctl reload nginx
"$BASE/venv-certbot/bin/certbot" certonly --webroot --webroot-path "$BASE/acme" \
  --ip-address "$PUBLIC_IP" --preferred-profile shortlived --cert-name capswriter-ip \
  --non-interactive --agree-tos --register-unsafely-without-email \
  --deploy-hook '/usr/sbin/nginx -t && /usr/bin/systemctl reload nginx'
sed "s/__PUBLIC_IP__/$PUBLIC_IP/g" "$SCRIPT_DIR/nginx-https.conf.template" >/etc/nginx/conf.d/capswriter.conf
nginx -t
systemctl reload nginx
install -m 0644 "$SCRIPT_DIR/capswriter-cert-renew.service" /etc/systemd/system/
install -m 0644 "$SCRIPT_DIR/capswriter-cert-renew.timer" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now capswriter-cert-renew.timer
echo 'Trusted IP TLS installed; ASR readiness is a separate gate.'
