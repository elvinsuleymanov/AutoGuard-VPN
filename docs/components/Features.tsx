import React, { ReactNode } from 'react'

interface Feature {
  icon: string
  title: string
  body: ReactNode
}

const FEATURES: Feature[] = [
  {
    icon: '⚡',
    title: 'Zero-touch onboarding',
    body: (
      <>
        A client runs one script. It generates its own keypair, registers the
        public half over HTTPS, and brings the tunnel up. No config files are
        ever emailed around.
      </>
    ),
  },
  {
    icon: '🔑',
    title: 'The private key never moves',
    body: (
      <>
        Keys are generated on the client. Only the public key is sent to the
        server, so a compromised registration request cannot yield a working
        identity.
      </>
    ),
  },
  {
    icon: '🛡️',
    title: 'Ad blocking for every peer',
    body: (
      <>
        Pi-hole answers DNS for the whole tunnel, so blocking applies to every
        app on every connected device &mdash; not just browsers with an
        extension installed.
      </>
    ),
  },
  {
    icon: '🔍',
    title: 'No third party in the DNS chain',
    body: (
      <>
        Unbound resolves recursively from the root servers with DNSSEC
        validation. Cloudflare and Google never see your queries.
      </>
    ),
  },
  {
    icon: '🔄',
    title: 'Hot peer reload',
    body: (
      <>
        <code>inotifywait</code> picks up each new peer file and applies it with{' '}
        <code>wg addconf</code>. Adding a client never restarts the tunnel or
        drops anyone.
      </>
    ),
  },
  {
    icon: '♻️',
    title: 'Re-runnable setup',
    body: (
      <>
        Every generated file is rendered fresh from <code>templates/</code> on
        each run while existing secrets are reused, so <code>setup.sh</code> is
        safe to run again at any time.
      </>
    ),
  },
]

export default function Features() {
  return (
    <div className="ag-features">
      {FEATURES.map((feature) => (
        <div className="ag-feature" key={feature.title}>
          <div className="ag-feature-icon" aria-hidden="true">
            {feature.icon}
          </div>
          <h3>{feature.title}</h3>
          <p>{feature.body}</p>
        </div>
      ))}
    </div>
  )
}
