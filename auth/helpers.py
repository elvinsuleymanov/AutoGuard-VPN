import os
import secrets
import base64
import re
import hashlib
from pathlib import Path
from fastapi import HTTPException, Security
from fastapi.security import APIKeyHeader

REGISTRATION_TOKEN = os.environ["REGISTRATION_TOKEN"]
INTERNAL_SUBNET    = os.environ.get("INTERNAL_SUBNET", "10.13.26.0")
PUBLIC_IP          = os.environ.get("PUBLIC_IP", "")
PORT_WG            = os.environ.get("PORT_WG", "51820")
IP_PIHOLE          = os.environ.get("IP_PIHOLE", "172.29.144.30")

_PUBKEY_FILE = Path("/wg-keys/server_public.key")

api_key_header = APIKeyHeader(name="X-Auth-Token")
PEERS_DIR = Path("/app/peers")


def verify(key: str = Security(api_key_header)) -> None:
    if not secrets.compare_digest(key, REGISTRATION_TOKEN):
        raise HTTPException(status_code=401, detail="Invalid token")


def is_valid_wg_pubkey(key: str) -> bool:
    if not re.fullmatch(r'[A-Za-z0-9+/]{43}=', key):
        return False
    try:
        decoded = base64.b64decode(key)
        return len(decoded) == 32
    except Exception:
        return False


def _get_used_ips() -> set[str]:
    used: set[str] = set()
    if not PEERS_DIR.exists():
        return used
    for f in PEERS_DIR.glob("*.conf"):
        for line in f.read_text().splitlines():
            if line.strip().startswith("AllowedIPs"):
                ip = line.split("=", 1)[1].strip().split("/")[0]
                used.add(ip)
    return used


def allocate_ip() -> str:
    base = INTERNAL_SUBNET.rsplit(".", 1)[0]
    used = _get_used_ips()
    for i in range(2, 255):
        candidate = f"{base}.{i}"
        if candidate not in used:
            return candidate
    raise RuntimeError("No available IP addresses in the WireGuard subnet")


def write_peer_conf(pubkey: str, ip: str) -> None:
    PEERS_DIR.mkdir(parents=True, exist_ok=True)
    pubkey_hash = hashlib.sha256(pubkey.encode()).hexdigest()
    peer_file = PEERS_DIR / f"{pubkey_hash[:16]}.conf"
    if peer_file.exists():
        raise FileExistsError("Peer already registered")
    conf = f"[Peer]\nPublicKey = {pubkey}\nAllowedIPs = {ip}/32\n"
    peer_file.write_text(conf)
    peer_file.chmod(0o600)


def _server_public_key() -> str:
    if _PUBKEY_FILE.exists():
        key = _PUBKEY_FILE.read_text().strip()
        if key:
            return key
    raise RuntimeError("Server public key not available yet")


def generate_client_config(client_ip: str) -> str:
    # Current client scripts ignore this and build the same config from values
    # setup.sh wrote into them, taking only the address from the response, so
    # a forged response cannot redirect their tunnel. Scripts rendered before
    # that change still use it. Keep it in step with BuildClientConfig in
    # setupclient.ps1.template, WG_CONFIG in setupclient.sh.template, and the
    # fields add-device.sh prints for phones.
    pubkey = _server_public_key()
    # ::/0 is here to *blackhole* IPv6, not to carry it. The tunnel is IPv4-only
    # -- Address is a /32 and the server has no IPv6 -- so without this line a
    # dual-stack client (most home ISPs, essentially every mobile carrier) sends
    # IPv6 straight out its normal interface and exposes its real address while
    # everything looks like it is working. Claiming the whole v6 range pulls a
    # default route into an interface that cannot route it, so those packets die
    # locally instead. Anything that does reach the server is dropped there: each
    # peer's server-side AllowedIPs stays a single IPv4 /32.
    return (
        "[Interface]\n"
        "PrivateKey = <PASTE_YOUR_PRIVATE_KEY_HERE>\n"
        f"Address = {client_ip}/32\n"
        f"DNS = {IP_PIHOLE}\n\n"
        "[Peer]\n"
        f"PublicKey = {pubkey}\n"
        f"Endpoint = {PUBLIC_IP}:{PORT_WG}\n"
        "AllowedIPs = 0.0.0.0/0, ::/0\n"
        "PersistentKeepalive = 25\n"
    )
