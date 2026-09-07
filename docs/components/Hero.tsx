import React from 'react'
import Link from 'next/link'

const BADGES = [
  'WireGuard',
  'Pi-hole',
  'Unbound DNSSEC',
  'FastAPI',
  'Docker Compose',
  'MIT licensed',
]

export default function Hero() {
  return (
    <section className="ag-hero">
      <span className="ag-hero-eyebrow">
        <span className="ag-hero-eyebrow-dot" />
        Self-hosted · No third-party VPN provider
      </span>

      <h1>AutoGuard VPN</h1>

      <p className="ag-hero-tagline">
        A containerized WireGuard stack with automated peer registration,
        network-wide ad blocking, and fully recursive DNSSEC resolution. Two
        scripts &mdash; one on the server, one on each client.
      </p>

      <div className="ag-hero-actions">
        <Link className="ag-btn ag-btn-primary" href="/server-setup">
          Deploy your server →
        </Link>
        <Link className="ag-btn ag-btn-secondary" href="/architecture">
          How it works
        </Link>
      </div>

      <div className="ag-hero-command">
        <span>$</span>
        git clone https://github.com/ElvinSuleymanov/AutoGuard-VPN.git &amp;&amp; ./setup.sh
      </div>

      <div className="ag-hero-badges">
        {BADGES.map((badge) => (
          <span className="ag-badge" key={badge}>
            {badge}
          </span>
        ))}
      </div>
    </section>
  )
}
