#!/bin/bash

CYAN='\033[0;36m'
BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}=================================================="
echo -e "   🛡️  AUTOGUARD VPN CLIENT SETUP         "
echo -e "==================================================${NC}"

SERVER_IP="PLACEHOLDER-PUBLIC-IP"
INTERFACE_NAME="PLACEHOLDER-INTERFACE-NAME"
AUTH_KEY="PLACEHOLDER-AUTH_KEY"

error()       { echo -e "\n${RED}❌ ERROR: $1${NC}\n" >&2; exit 1; }
log_success() { echo -e "${GREEN}${BOLD}✅ $1${NC}"; }

[ "$(id -u)" -eq 0 ] || error "Run this script with sudo."

command -v wg      >/dev/null 2>&1 || error "wireguard-tools not installed. Run: apt install wireguard-tools"
command -v curl    >/dev/null 2>&1 || error "curl not installed."
command -v python3 >/dev/null 2>&1 || error "python3 not installed."

WG_CONF="/etc/wireguard/${INTERFACE_NAME}.conf"

if [ -f "$WG_CONF" ]; then
    echo "Config already exists. Bringing up existing tunnel..."
    wg-quick up "$INTERFACE_NAME" 2>/dev/null || true
    systemctl enable "wg-quick@${INTERFACE_NAME}" 2>/dev/null || true
    log_success "VPN is active on interface ${INTERFACE_NAME}."
    exit 0
fi

echo "🔑 Generating WireGuard keypair..."
CLIENT_PRIVATE_KEY=$(wg genkey)
CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | wg pubkey)
log_success "Keypair generated."

echo "📡 Registering with VPN server at ${SERVER_IP}..."
RESPONSE=$(curl -sk \
    -X POST \
    -H "Content-Type: application/json" \
    -H "X-Auth-Token: ${AUTH_KEY}" \
    -d "{\"public_key\": \"${CLIENT_PUBLIC_KEY}\"}" \
    "https://${SERVER_IP}/addnewpeer")

STATUS=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status',''))" 2>/dev/null)
[ "$STATUS" = "ok" ] || error "Server rejected registration. Response: $RESPONSE"

WG_CONFIG=$(echo "$RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['config'])" 2>/dev/null)
WG_CONFIG="${WG_CONFIG//<PASTE_YOUR_PRIVATE_KEY_HERE>/${CLIENT_PRIVATE_KEY}}"

mkdir -p /etc/wireguard
printf '%s\n' "$WG_CONFIG" > "$WG_CONF"
chmod 600 "$WG_CONF"
log_success "Config written to ${WG_CONF}."

echo "🚀 Starting WireGuard..."
wg-quick up "$INTERFACE_NAME" || error "wg-quick up failed."
systemctl enable "wg-quick@${INTERFACE_NAME}" 2>/dev/null || true

log_success "Connected! VPN is active on interface ${INTERFACE_NAME}."
