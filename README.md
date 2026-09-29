<p align="center">
  <img src="assets/logo.png" alt="AutoGuard VPN" height="150">
</p>

<h2 align="center">AutoGuard VPN</h2>

<p align="center">
  Your own WireGuard VPN with ad-blocking DNS — set up by running one script.
</p>

<p align="center">
  <a href="https://github.com/ElvinSuleymanov/AutoGuard-VPN/actions/workflows/ci.yml">
    <img src="https://github.com/ElvinSuleymanov/AutoGuard-VPN/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License">
  <img src="https://img.shields.io/badge/WireGuard-88171A?logo=wireguard&logoColor=white" alt="WireGuard">
  <img src="https://img.shields.io/badge/Docker%20Compose-2496ED?logo=docker&logoColor=white" alt="Docker Compose">
</p>

<p align="center">
  <a href="https://autoguardvpn.vercel.app">Documentation</a> ·
  <a href="https://autoguardvpn.vercel.app/requirements">Requirements</a> ·
  <a href="https://autoguardvpn.vercel.app/server-setup">Server Setup</a> ·
  <a href="https://autoguardvpn.vercel.app/client-setup">Client Setup</a> ·
  <a href="https://autoguardvpn.vercel.app/faq">FAQ</a>
</p>

---

## Two scripts. That's the whole thing.

**1 — On your server** (any Docker host with a public IP):

```bash
git clone https://github.com/ElvinSuleymanov/AutoGuard-VPN.git
cd AutoGuard-VPN && chmod +x setup.sh && ./setup.sh
```

Generates every key, certificate and config, then starts the stack. Open
**`443/tcp`** and **`51820/udp`** in your cloud firewall.

**2 — On each device**, run the script `setup.sh` just wrote for you:

```bash
sudo ./setupclient.sh          # Linux
```
```powershell
.\setupclient.ps1              # Windows, as Administrator
```

It generates its own keypair, registers itself, and connects. No config files to
copy around, nothing to edit on the server.

Afterwards you turn the VPN on and off yourself: `sudo wg-quick up wg0` /
`sudo wg-quick down wg0` on Linux, where it does not start by itself after a
restart, and Activate / Deactivate in the WireGuard app on Windows.

> Updating later is the same one command: `git pull && ./setup.sh`

<p align="center">
  <img src="assets/usage_phase.svg" alt="How traffic flows once connected" width="620">
</p>

## What you get

- **Your keys, your server.** No VPN company in the middle to trust or audit.
- **The private key never leaves the device.** Only the public half is sent.
- **Clients verify your server.** Each client script carries your server's
  certificate fingerprint and WireGuard key, so an interceptor can neither
  steal the token nor redirect the tunnel. No domain or CA certificate needed.
- **Ad blocking for everything.** Pi-hole answers DNS for the whole tunnel, so it
  covers every app — not just browsers with an extension.
- **No third party in the DNS chain.** Unbound resolves from the root servers
  with DNSSEC. Cloudflare and Google never see your queries.
- **Kill switch.** If the tunnel drops, traffic is blocked rather than quietly
  falling back to your normal connection.
- **No IPv6 leaks.** IPv6 is blackholed instead of escaping around the tunnel.
- **Add a device anytime.** New peers activate live, without restarting anything.

## What you need

| | |
|---|---|
| **Server** | Docker + Compose v2, 2 GB RAM, a public IPv4 address |
| **Open ports** | `443/tcp` (registration) and `51820/udp` (tunnel) |
| **Linux client** | `wireguard-tools`, `curl`, `python3`, `iptables` |
| **Windows client** | Windows 10/11, Administrator — WireGuard installs itself |

Nothing else on the host: keys and certificates are generated inside a throwaway
container, so no `openssl` or `wg` binary is needed.

## The stack

| Container | Image | Role |
|---|---|---|
| `wireguard` | built locally | VPN server, hot peer reload |
| `auth-service` | built locally (FastAPI) | Peer registration API |
| `nginx-proxy` | `nginx:1.27-alpine` | TLS termination |
| `pihole` | `pihole/pihole` | Ad-blocking DNS |
| `unbound` | `mvance/unbound` | Recursive DNSSEC resolver |

Services sit on an isolated bridge (`172.29.144.0/24`); clients get addresses in
`10.13.26.0/24`, up to 253 of them.

## Documentation

Full setup walkthrough, architecture, customization and troubleshooting live at
**[autoguardvpn.vercel.app](https://autoguardvpn.vercel.app)**.

## License

[MIT](LICENSE)
