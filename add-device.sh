#!/bin/bash
set -euo pipefail

# ==============================================================================
# AutoGuard VPN — add a phone or tablet
#
# The device generates its own keypair in the WireGuard app, so its private key
# never leaves it. This script registers the public half and prints what to
# enter in the app, with the server's public key as a QR code to scan rather
# than 44 characters to type.
#
# The device never talks to the registration API and never holds the token:
# it is registered from here, over the SSH session that already proves this is
# your server, and the server's key reaches it through the device's camera.
#
# Run on the server, from the repository root, once setup.sh has started the
# stack:
#
#   ./add-device.sh <public key shown in the WireGuard app>
# ==============================================================================

CYAN='\033[0;36m'
BOLD='\033[1m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

error()       { echo -e "\n${RED}❌ ERROR: $1${NC}\n" >&2; exit 1; }
log_success() { echo -e "${GREEN}${BOLD}✅ $1${NC}"; }
log_warn()    { echo -e "${YELLOW}⚠️  $1${NC}"; }

ENV_FILE=".env"
SERVER_KEY_FILE="./wireguard/keys/server_public.key"
AUTH_CONTAINER="auth_service"
WG_CONTAINER="wireguard"

# The shape of a base64-encoded 32-byte WireGuard key.
KEY_RE='^[A-Za-z0-9+/]{43}=$'

usage() {
    cat <<'USAGE'
Usage: ./add-device.sh <public-key>

Adds a phone or tablet whose keypair was generated in the WireGuard app.

  1. In the WireGuard app, tap + and choose "Create from scratch".
  2. Name the tunnel, then tap "Generate keypair" (or the generate button
     next to the private key).
  3. Copy the public key it shows, get it to the server any way you like --
     it is not secret -- and run this script with it.
  4. Fill in the fields this script prints, save, and switch the tunnel on.

  -h, --help   Show this message.
USAGE
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    "")        usage >&2; exit 1 ;;
esac
[ "$#" -eq 1 ] || error "Expected exactly one argument, the device's public key (try --help)."

DEVICE_KEY="$1"
[[ $DEVICE_KEY =~ $KEY_RE ]] || error "'${DEVICE_KEY}' is not a WireGuard public key.
Copy the public key the WireGuard app shows after \"Generate keypair\" -- 44
characters ending in '='. Never the private key."

# ------------------------------------------------------------------------------
# What the device config needs, from the files setup.sh wrote
# ------------------------------------------------------------------------------
[ -f "$ENV_FILE" ] || error "No .env here. Run this from the repository root, after ./setup.sh."

# Sourced without exporting: this script needs four plain values from it, not
# the registration token or the Pi-hole password in its environment.
# shellcheck source=/dev/null
. "$ENV_FILE"

for var in PUBLIC_IP PORT_WG IP_PIHOLE INTERNAL_SUBNET; do
    [ -n "${!var:-}" ] || error "${var} is missing from .env. Re-run ./setup.sh."
done

[ -s "$SERVER_KEY_FILE" ] || error "No server public key at ${SERVER_KEY_FILE}. Run ./setup.sh first."
SERVER_KEY=$(tr -d '\n' < "$SERVER_KEY_FILE")
[[ $SERVER_KEY =~ $KEY_RE ]] || error "${SERVER_KEY_FILE} does not hold a valid key. Re-run ./setup.sh."

# ------------------------------------------------------------------------------
# Register
# ------------------------------------------------------------------------------
command -v docker >/dev/null 2>&1 || error "docker is not installed."
docker info >/dev/null 2>&1 || error "Cannot talk to the Docker daemon.
Is it running, and is your user in the 'docker' group?"

running() { [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]; }
running "$AUTH_CONTAINER" || error "${AUTH_CONTAINER} is not running. Start the stack with ./setup.sh."

# Through the same /addnewpeer API the client scripts use, so address
# allocation stays in one place. It is called from inside the auth container,
# over its own loopback, with the token already in its environment: nothing
# crosses a network, and the token never appears on this command line.
echo "📡 Registering the device..."
DEVICE_IP=$(docker exec -i "$AUTH_CONTAINER" python3 - "$DEVICE_KEY" <<'PY'
import json
import os
import sys
import urllib.error
import urllib.request

request = urllib.request.Request(
    f"http://127.0.0.1:{os.environ['PORT_AUTH']}/addnewpeer",
    data=json.dumps({"public_key": sys.argv[1]}).encode(),
    headers={
        "Content-Type": "application/json",
        "X-Auth-Token": os.environ["REGISTRATION_TOKEN"],
    },
)
try:
    with urllib.request.urlopen(request, timeout=30) as response:
        print(json.load(response)["ip"])
except urllib.error.HTTPError as e:
    body = e.read().decode(errors="replace")
    try:
        body = json.loads(body).get("detail", body)
    except ValueError:
        pass
    sys.exit(f"The server answered {e.code}: {body}")
except urllib.error.URLError as e:
    sys.exit(f"Could not reach the registration API: {e.reason}")
PY
) || error "Registration failed (see above). Nothing was added."

[ "${DEVICE_IP%.*}" = "${INTERNAL_SUBNET%.*}" ] \
    || error "The server returned an unexpected address: '${DEVICE_IP}'"

log_success "Registered. The device's address is ${DEVICE_IP}."

# ------------------------------------------------------------------------------
# What to enter in the app
#
# Mirrors generate_client_config() in auth/helpers.py. Keep all copies in step;
# helpers.py lists them.
# ------------------------------------------------------------------------------
cat <<EOF

$(echo -e "${CYAN}${BOLD}In the WireGuard app, open the tunnel you created and fill in:${NC}")

  Interface
    Addresses              ${DEVICE_IP}/32
    DNS servers            ${IP_PIHOLE}

  Peer  (tap "Add peer")
    Public key             scan the QR code below
    Endpoint               ${PUBLIC_IP}:${PORT_WG}
    Allowed IPs            0.0.0.0/0, ::/0
    Persistent keepalive   25

  Leave the other fields as they are. On Android, leave "Exclude private IPs"
  unchecked: it would send the DNS server above around the tunnel, and name
  resolution would stop working.

$(echo -e "${BOLD}Server public key${NC} -- scan with the device's camera, copy, and paste it into")
the peer's Public key field:

EOF

# qrencode ships in the WireGuard image. A missing QR is not worth failing over
# at this point -- the device is already registered, and the key is printed
# below either way.
if ! printf '%s' "$SERVER_KEY" | docker exec -i "$WG_CONTAINER" qrencode -t ansiutf8 -m 2 2>/dev/null; then
    log_warn "Could not draw the QR code; type or paste the key below instead."
fi

cat <<EOF

    ${SERVER_KEY}

Save the tunnel and switch it on. The first handshake confirms the key: if
the tunnel shows no data received, one of the fields above is off.

$(echo -e "${BOLD}Kill switch (Android):${NC} in the system VPN settings, open WireGuard and turn")
on "Always-on VPN" and "Block connections without VPN". Traffic is then blocked
whenever the tunnel is not up, instead of falling back to your normal
connection.

EOF
