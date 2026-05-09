<p align="center">
  <img src="assets/logo.png" alt="AutoGuard VPN" height="160">
</p>

<h3 align="center">AutoGuard VPN</h3>
<p align="center">Self-hosted WireGuard VPN with automated peer registration, ad-blocking DNS, and recursive DNSSEC.</p>

<p align="center">
  <a href="https://autoguardvpn.vercel.app">📖 Documentation</a> ·
  <a href="https://autoguardvpn.vercel.app/server-setup">Server Setup</a> ·
  <a href="https://autoguardvpn.vercel.app/client-setup">Client Setup</a> ·
  <a href="https://autoguardvpn.vercel.app/faq">FAQ</a>
</p>

---

## What It Does

AutoGuard VPN is a fully containerized VPN stack that runs on a single Docker host. Clients register themselves through a secure API — no manual peer editing required.

- Zero-touch client onboarding via a single script (Linux & Windows)
- Network-wide ad and tracker blocking through Pi-hole
- Private recursive DNS with DNSSEC via Unbound — no Cloudflare or Google in the chain
- Hot peer reload — new peers activate without restarting any container
- Timing-safe token authentication on the registration endpoint

## Stack

| Container | Image | Role |
|---|---|---|
| `wireguard` | custom | WireGuard VPN server |
| `auth-service` | custom (FastAPI) | Peer registration API |
| `nginx-proxy` | nginx:alpine | TLS reverse proxy |
| `pihole` | pihole/pihole | Ad-blocking DNS |
| `unbound` | mvance/unbound | Recursive DNS resolver |

All services run on an isolated Docker bridge network (`172.29.144.0/24`). WireGuard clients receive IPs in `10.13.26.0/24`.

## Quick Start

```bash
git clone https://github.com/ElvinSuleymanov/AutoGuard-VPN.git
cd AutoGuard-VPN
chmod +x setup.sh
./setup.sh
```

After setup completes, copy `./scripts/setupclient.sh` (Linux) or `./scripts/setupclient.ps1` (Windows) to each client and run it as root/Administrator.

For full setup instructions, requirements, architecture details, and troubleshooting, see the **[documentation](https://autoguard-vpn.vercel.app)**.

## License

[MIT](LICENSE)
