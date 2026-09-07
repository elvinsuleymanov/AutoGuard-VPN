import React from 'react'
import { DocsThemeConfig, useConfig } from 'nextra-theme-docs'
import { useRouter } from 'next/router'
import Image from 'next/image'

const SITE = 'AutoGuard VPN'
const REPO = 'https://github.com/ElvinSuleymanov/AutoGuard-VPN'
const DESCRIPTION =
  'Self-hosted WireGuard VPN with automated peer registration, Pi-hole ad blocking, and recursive DNSSEC resolution — deployed with a single script.'

const config: DocsThemeConfig = {
  logo: (
    <span style={{ display: 'flex', alignItems: 'center', gap: '0.6rem' }}>
      <Image
        src="/logo.png"
        alt=""
        width={80}
        height={80}
        style={{
          borderRadius: '6px',
          height: 'clamp(30px, 4vw, 36px)',
          width: 'auto',
          display: 'block',
        }}
      />
      <span style={{ fontWeight: 700, letterSpacing: '-0.02em' }}>
        AutoGuard&nbsp;VPN
      </span>
    </span>
  ),

  project: { link: REPO },
  docsRepositoryBase: `${REPO}/tree/main/docs`,

  // Nextra renders this into <head> on every page. Pulling the frontmatter via
  // useConfig is what gives each page its own title and description rather than
  // repeating the site-wide one everywhere.
  head: function Head() {
    const { frontMatter, title } = useConfig()
    const { asPath } = useRouter()

    const pageTitle = asPath === '/' ? `${SITE} — Self-hosted WireGuard` : `${title} – ${SITE}`
    const description = frontMatter.description || DESCRIPTION

    return (
      <>
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <title>{pageTitle}</title>
        <meta name="description" content={description} />

        <meta property="og:type" content="website" />
        <meta property="og:site_name" content={SITE} />
        <meta property="og:title" content={pageTitle} />
        <meta property="og:description" content={description} />
        <meta property="og:image" content="/logo.png" />

        <meta name="twitter:card" content="summary" />
        <meta name="twitter:title" content={pageTitle} />
        <meta name="twitter:description" content={description} />

        <meta name="theme-color" content="#060b14" />
        <link rel="icon" href="/logo.png" />
      </>
    )
  },

  nextThemes: { defaultTheme: 'dark' },

  sidebar: {
    defaultMenuCollapseLevel: 1,
    toggleButton: true,
  },

  toc: {
    backToTop: true,
    title: 'On this page',
  },

  editLink: { content: 'Edit this page on GitHub' },

  feedback: {
    content: 'Found a mistake? Open an issue',
    labels: 'documentation',
  },

  navigation: { prev: true, next: true },

  search: { placeholder: 'Search the docs…' },

  footer: {
    content: (
      <div
        style={{
          display: 'flex',
          flexWrap: 'wrap',
          gap: '0.5rem 1.5rem',
          alignItems: 'center',
          justifyContent: 'space-between',
          width: '100%',
          fontSize: '0.85rem',
        }}
      >
        <span>
          {SITE} — MIT licensed. Self-hosted infrastructure you own end to end.
        </span>
        <a href={REPO} target="_blank" rel="noreferrer">
          GitHub ↗
        </a>
      </div>
    ),
  },
}

export default config
