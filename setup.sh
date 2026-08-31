#!/bin/bash
set -euo pipefail

# ==============================================================================
# AutoGuard VPN — stack setup
#
# Host requirements: Docker + Docker Compose. Nothing else.
# All cryptography runs inside a throwaway container, so the host needs no
# openssl / wg / curl binaries.
#
# This script is idempotent. Re-running it re-renders every generated file from
# templates/ and reuses the existing secrets in .env. Pass --force to rotate the
# server keypair, the registration token, and the Pi-hole password instead.
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
log_info()    { echo -e "   $1"; }

echo -e "${CYAN}${BOLD}=================================================="
echo -e "   🛡️  WIREGUARD STACK AUTOMATION UTILITY   "
echo -e "==================================================${NC}"

# ------------------------------------------------------------------------------
# Defaults
# ------------------------------------------------------------------------------
SUBNET="172.29.144.0/24"
IP_WG="172.29.144.10"
IP_UNBOUND="172.29.144.20"
IP_PIHOLE="172.29.144.30"
IP_NGINX="172.29.144.40"
IP_AUTH="172.29.144.50"
INTERNAL_SUBNET="10.13.26.0"
PORT_WG="51820"
PORT_AUTH="5000"
INTERFACE_NAME="wg0"

ENV_FILE=".env"
TEMPLATE_DIR="./templates"
KEYS_DIR="./wireguard/keys"
CERTS_DIR="./certs"

# Alpine is used as a disposable crypto workbench so the host stays Docker-only.
CRYPTO_IMAGE="alpine:3.20"

FORCE="no"
RENDER_ONLY="no"
PUBLIC_IP_OVERRIDE=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --force|-f)     FORCE="yes" ;;
        --render-only)  RENDER_ONLY="yes" ;;
        --public-ip)    PUBLIC_IP_OVERRIDE="${2:-}"; shift ;;
        --public-ip=*)  PUBLIC_IP_OVERRIDE="${1#*=}" ;;
        --help|-h)
            cat <<'USAGE'
Usage: ./setup.sh [options]

  --force              Rotate the server keypair, registration token, and
                       Pi-hole password. Invalidates every issued client config.
  --public-ip <addr>   Use this address instead of prompting. Also accepts a
                       hostname.
  --render-only        Generate keys, certs, .env and rendered configs, then
                       stop without starting the stack.
  -h, --help           Show this message.
USAGE
            exit 0
            ;;
        *) error "Unknown argument: $1 (try --help)" ;;
    esac
    shift
done

# ------------------------------------------------------------------------------
# Dependency check — Docker and Docker Compose only
# ------------------------------------------------------------------------------
echo "🔎 Checking system dependencies..."

command -v docker >/dev/null 2>&1 || error "docker is not installed.

Install it from:
https://docs.docker.com/engine/install/"

if docker compose version >/dev/null 2>&1; then
    DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    DC="docker-compose"
else
    error "Docker Compose is not installed.

Install it from:
https://docs.docker.com/compose/install/"
fi

docker info >/dev/null 2>&1 || error "Cannot talk to the Docker daemon.
Is it running, and is your user in the 'docker' group?"

log_success "Docker and Docker Compose are available."

[ -d "$TEMPLATE_DIR" ] || error "Template directory not found: $TEMPLATE_DIR
Run this script from the repository root."

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

# Render a template to its destination, substituting PLACEHOLDER/value pairs.
# Uses a temp file rather than `sed -i` so BSD and GNU sed both work.
render() {
    local src="$1" dst="$2"
    shift 2

    [ -f "$src" ] || error "Missing template: $src"

    local -a args=()
    while [ "$#" -gt 1 ]; do
        local escaped
        escaped=$(printf '%s' "$2" | sed -e 's/[\\&|]/\\&/g')
        args+=( -e "s|$1|$escaped|g" )
        shift 2
    done

    mkdir -p "$(dirname "$dst")"
    sed "${args[@]}" "$src" > "${dst}.tmp"
    mv "${dst}.tmp" "$dst"
}

# Randomness comes straight from the kernel — no openssl on the host.
random_hex() { head -c "${1:-32}" /dev/urandom | od -An -tx1 | tr -d ' \n'; }
random_b64() { head -c "${1:-12}" /dev/urandom | base64 | tr -d '\n'; }

detect_timezone() {
    local tz=""
    tz=$(timedatectl 2>/dev/null | awk '/Time zone/ {print $3}') || true
    if [ -z "$tz" ]; then
        tz=$(cat /etc/timezone 2>/dev/null || echo "UTC")
    fi
    printf '%s' "${tz:-UTC}"
}

fetch_public_ip() {
    if command -v curl >/dev/null 2>&1; then
        curl -s --max-time 5 https://ifconfig.me/ 2>/dev/null || true
    else
        docker run --rm "$CRYPTO_IMAGE" sh -ec \
            'apk add --no-cache curl >/dev/null 2>&1; curl -s --max-time 5 https://ifconfig.me/' \
            2>/dev/null || true
    fi
}

# X25519 keypair, generated inside a container. Prints private key then public
# key, one per line.
generate_wireguard_keys() {
    local out
    out=$(docker run --rm "$CRYPTO_IMAGE" sh -ec '
        apk add --no-cache openssl >/dev/null 2>&1
        pem=$(mktemp)
        openssl genpkey -algorithm X25519 -out "$pem" 2>/dev/null
        openssl pkey -in "$pem" -outform DER          | tail -c 32 | base64
        openssl pkey -in "$pem" -pubout -outform DER  | tail -c 32 | base64
        rm -f "$pem"
    ') || error "Failed to generate the WireGuard keypair."

    SERVER_PRIVATE_KEY=$(printf '%s\n' "$out" | sed -n '1p')
    SERVER_PUBLIC_KEY=$(printf '%s\n' "$out"  | sed -n '2p')

    [ -n "$SERVER_PRIVATE_KEY" ] && [ -n "$SERVER_PUBLIC_KEY" ] \
        || error "WireGuard key generation produced an empty key."
}

# Self-signed cert whose CN and SAN actually match what nginx serves, so clients
# can pin it instead of disabling verification wholesale.
generate_self_signed_cert() {
    local cn="$1" san

    if [[ "$cn" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
        san="IP:$cn"
    else
        san="DNS:$cn"
    fi

    mkdir -p "$CERTS_DIR"
    docker run --rm \
        -v "$(pwd)/${CERTS_DIR#./}:/certs" \
        -e CN="$cn" -e SAN="$san" \
        -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
        "$CRYPTO_IMAGE" sh -ec '
            apk add --no-cache openssl >/dev/null 2>&1
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout /certs/privkey.pem \
                -out    /certs/fullchain.pem \
                -subj   "/CN=${CN}" \
                -addext "subjectAltName=${SAN}" 2>/dev/null
            chmod 600 /certs/privkey.pem
            chmod 644 /certs/fullchain.pem
            chown "${HOST_UID}:${HOST_GID}" /certs/privkey.pem /certs/fullchain.pem
        ' || error "Failed to generate the self-signed certificate."

    log_success "TLS certificate issued for ${cn} (SAN: ${san})."
}

# ------------------------------------------------------------------------------
# Load existing configuration
# ------------------------------------------------------------------------------
IS_RERUN="no"
PREV_PUBLIC_IP=""

if [ -f "$ENV_FILE" ]; then
    IS_RERUN="yes"
    set -a
    # shellcheck source=/dev/null
    . "$ENV_FILE"
    set +a
    PREV_PUBLIC_IP="${PUBLIC_IP:-}"

    if [ "$FORCE" = "yes" ]; then
        log_warn "--force: rotating server keypair, registration token, and Pi-hole password."
        log_warn "Every previously issued client config will stop working."
    else
        log_info "Existing .env found — reusing its secrets. Use --force to rotate them."
    fi
fi

DETECTED_TZ=$(detect_timezone)
echo "Detected timezone: $DETECTED_TZ"

if [ -f /etc/os-release ]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    echo "Running on: ${ID:-unknown}"
fi

# ------------------------------------------------------------------------------
# Public IP
# ------------------------------------------------------------------------------
detect_public_ip() {
    local fetched suggested yn

    if [ -n "$PUBLIC_IP_OVERRIDE" ]; then
        PUBLIC_IP="$PUBLIC_IP_OVERRIDE"
        log_info "Using supplied server address: $PUBLIC_IP"
        return
    fi

    fetched=$(fetch_public_ip)
    suggested="${PUBLIC_IP:-$fetched}"

    # Non-interactive shells cannot answer the prompt below.
    if [ ! -t 0 ]; then
        [ -n "$suggested" ] || error "No TTY and no address available.
Pass --public-ip <addr> when running non-interactively."
        PUBLIC_IP="$suggested"
        log_info "Non-interactive: using $PUBLIC_IP"
        return
    fi

    if [ -z "$suggested" ]; then
        echo -n "Could not detect a public IP. Enter your server's public IP or hostname: "
        read -r PUBLIC_IP
        [ -n "$PUBLIC_IP" ] || error "A public IP or hostname is required."
        return
    fi

    while true; do
        echo -en "Is ${BOLD}${suggested}${NC} your WireGuard server address? (y/n): "
        read -r yn
        case "$yn" in
            [Yy]*) PUBLIC_IP="$suggested"; break ;;
            [Nn]*)
                echo -n "Enter your WireGuard server IP or hostname: "
                read -r PUBLIC_IP
                [ -n "$PUBLIC_IP" ] || error "A public IP or hostname is required."
                break ;;
            *) echo "Please answer y or n." ;;
        esac
    done
}

detect_public_ip

# ------------------------------------------------------------------------------
# Secrets — reused across runs unless --force
# ------------------------------------------------------------------------------
if [ "$FORCE" = "yes" ]; then
    WEBPASSWORD=$(random_b64 12)
    REGISTRATION_TOKEN=$(random_hex 32)
else
    WEBPASSWORD="${WEBPASSWORD:-$(random_b64 12)}"
    REGISTRATION_TOKEN="${REGISTRATION_TOKEN:-$(random_hex 32)}"
fi

# ------------------------------------------------------------------------------
# WireGuard keypair — persisted so re-runs never desync wg0.conf from the
# public key handed out to clients
# ------------------------------------------------------------------------------
mkdir -p "$KEYS_DIR"

if [ "$FORCE" != "yes" ] \
   && [ -s "$KEYS_DIR/server_private.key" ] \
   && [ -s "$KEYS_DIR/server_public.key" ]; then
    SERVER_PRIVATE_KEY=$(tr -d '\n' < "$KEYS_DIR/server_private.key")
    SERVER_PUBLIC_KEY=$(tr -d '\n'  < "$KEYS_DIR/server_public.key")
    log_info "Reusing the existing WireGuard keypair."
else
    generate_wireguard_keys
    log_success "WireGuard keypair generated."
fi

printf '%s\n' "$SERVER_PRIVATE_KEY" > "$KEYS_DIR/server_private.key"
printf '%s\n' "$SERVER_PUBLIC_KEY"  > "$KEYS_DIR/server_public.key"
chmod 600 "$KEYS_DIR/server_private.key"
chmod 644 "$KEYS_DIR/server_public.key"

# ------------------------------------------------------------------------------
# TLS certificate — reissued when missing, forced, or the address changed
# ------------------------------------------------------------------------------
if [ "$FORCE" = "yes" ] \
   || [ ! -s "$CERTS_DIR/fullchain.pem" ] \
   || [ ! -s "$CERTS_DIR/privkey.pem" ] \
   || [ "$PREV_PUBLIC_IP" != "$PUBLIC_IP" ]; then
    generate_self_signed_cert "$PUBLIC_IP"
else
    log_info "Reusing the existing TLS certificate."
fi

# ------------------------------------------------------------------------------
# Render every generated file from templates/
#
# Rendering from a pristine template on every run is what makes this script safe
# to re-run: there are no one-shot placeholders left to consume.
# ------------------------------------------------------------------------------
SERVER_WG_IP="${INTERNAL_SUBNET%.*}.1"

# ListenPort stays 51820: that is the port *inside* the container. The host-side
# port is remapped by the ${PORT_WG}:51820/udp publish in docker-compose.yml.
render "$TEMPLATE_DIR/wg0.conf.template" "./wireguard/wg_confs/wg0.conf" \
    "your-server-address" "${SERVER_WG_IP}/24" \
    "your-private-key"    "$SERVER_PRIVATE_KEY"
chmod 600 "./wireguard/wg_confs/wg0.conf"

# proxy_pass keeps the `auth-service` service name — Docker's embedded DNS
# resolves it on the user-defined bridge, so no IP substitution is needed.
render "$TEMPLATE_DIR/nginx.conf.template" "./nginx/nginx.conf" \
    "public_ip" "$PUBLIC_IP"

render "$TEMPLATE_DIR/setupclient.sh.template" "./scripts/setupclient.sh" \
    "PLACEHOLDER-PUBLIC-IP"     "$PUBLIC_IP" \
    "PLACEHOLDER-INTERFACE-NAME" "$INTERFACE_NAME" \
    "PLACEHOLDER-AUTH_KEY"      "$REGISTRATION_TOKEN"

render "$TEMPLATE_DIR/setupclient.ps1.template" "./scripts/setupclient.ps1" \
    "PLACEHOLDER_SERVER_PUBLIC_IP" "$PUBLIC_IP" \
    "PLACEHOLDER_INTERFACE_NAME"   "$INTERFACE_NAME" \
    "PLACEHOLDER_AUTH_KEY"         "$REGISTRATION_TOKEN"

chmod +x ./scripts/setupclient.sh
log_success "Configuration rendered from templates."

mkdir -p ./peers ./etc-pihole

# ------------------------------------------------------------------------------
# .env
# ------------------------------------------------------------------------------
write_env_file() {
    : > "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    {
        echo "SUBNET=${SUBNET}"
        echo "INTERNAL_SUBNET=${INTERNAL_SUBNET}"
        echo "DETECTED_TZ=${DETECTED_TZ}"
        echo "IP_WG=${IP_WG}"
        echo "IP_UNBOUND=${IP_UNBOUND}"
        echo "IP_PIHOLE=${IP_PIHOLE}"
        echo "IP_NGINX=${IP_NGINX}"
        echo "IP_AUTH=${IP_AUTH}"
        echo "PORT_WG=${PORT_WG}"
        echo "PORT_AUTH=${PORT_AUTH}"
        echo "PUBLIC_IP=${PUBLIC_IP}"
        echo "WEBPASSWORD=${WEBPASSWORD}"
        echo "REGISTRATION_TOKEN=${REGISTRATION_TOKEN}"
    } >> "$ENV_FILE"
}

write_env_file

if [ "$RENDER_ONLY" = "yes" ]; then
    log_success "Render complete (--render-only). Stack not started."
    exit 0
fi

# ------------------------------------------------------------------------------
# Bring the stack up
# ------------------------------------------------------------------------------
echo
echo "🚀 Starting the stack..."

if ! $DC up -d --wait; then
    echo -e "\n${RED}${BOLD}❌ docker compose failed. Inspect the logs with: ${DC} logs${NC}"
    exit 1
fi

# `up -d` will not recreate a container whose only change is the content of a
# bind-mounted config file, so re-runs need an explicit restart to pick up the
# freshly rendered wg0.conf and nginx.conf.
if [ "$IS_RERUN" = "yes" ]; then
    echo "♻️  Re-run detected — restarting services to apply the rendered configs..."
    $DC restart wireguard nginx-proxy >/dev/null
    $DC up -d --wait >/dev/null
fi

echo -e "\n${GREEN}${BOLD}✅ Stack is up and running!${NC}\n"
$DC ps

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
cat <<EOF

$(echo -e "${CYAN}${BOLD}Next steps${NC}")

  Client scripts (token already injected):
    ./scripts/setupclient.sh    — Linux, run as root
    ./scripts/setupclient.ps1   — Windows, run as Administrator

  Pi-hole admin is bound to localhost only. Reach it either over the VPN at
    http://${IP_PIHOLE}/admin
  or through an SSH tunnel:
    ssh -L 65231:127.0.0.1:65231 <user>@${PUBLIC_IP}
    then open http://127.0.0.1:65231/admin

  Pi-hole password:  ${WEBPASSWORD}

  Back up .env, wireguard/keys/, certs/, and peers/ — they are the entire
  state of this deployment.

EOF
