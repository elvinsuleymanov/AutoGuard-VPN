'use client'

import { useEffect, useRef, useState } from 'react'
import { useTheme } from 'next-themes'

interface MermaidProps {
  chart: string
}

/*
 * Nextra exports a Mermaid of its own, but these diagrams carry the network
 * topology and want a framed, palette-matched presentation. The important
 * difference from a naive wrapper is that this one re-renders when the reader
 * toggles the theme -- a diagram with baked-in dark colours is unreadable on a
 * light page, and Nextra defaults to following the OS.
 */

// Kept in step with the --ag-surface-* tokens in globals.css. A diagram canvas
// that does not match the frame around it is the same seam problem in miniature.
const DARK = {
  background: '#17191d',
  primaryColor: '#1e2126',
  primaryTextColor: '#e8eaed',
  primaryBorderColor: '#2c3138',
  lineColor: '#38bdf8',
  secondaryColor: '#1e2126',
  tertiaryColor: '#1e2126',
  edgeLabelBackground: '#17191d',
  clusterBkg: '#1b1e23',
  clusterBorder: '#2c3138',
  titleColor: '#7dd3fc',
  actorBkg: '#1e2126',
  actorBorder: '#2c3138',
  actorTextColor: '#e8eaed',
  signalColor: '#7dd3fc',
  signalTextColor: '#e8eaed',
  labelBoxBkgColor: '#1e2126',
  labelBoxBorderColor: '#2c3138',
  labelTextColor: '#e8eaed',
  noteBkgColor: '#22262c',
  noteTextColor: '#e8eaed',
  noteBorderColor: '#2c3138',
}

const LIGHT = {
  background: '#ffffff',
  primaryColor: '#f0f9ff',
  primaryTextColor: '#0b1220',
  primaryBorderColor: '#7dd3fc',
  lineColor: '#0284c7',
  secondaryColor: '#f0f9ff',
  tertiaryColor: '#f8fafc',
  edgeLabelBackground: '#ffffff',
  clusterBkg: '#f8fafc',
  clusterBorder: '#cbd5e1',
  titleColor: '#0369a1',
  actorBkg: '#f0f9ff',
  actorBorder: '#7dd3fc',
  actorTextColor: '#0b1220',
  signalColor: '#0284c7',
  signalTextColor: '#0b1220',
  labelBoxBkgColor: '#f0f9ff',
  labelBoxBorderColor: '#7dd3fc',
  labelTextColor: '#0b1220',
  noteBkgColor: '#e0f2fe',
  noteTextColor: '#0b1220',
  noteBorderColor: '#7dd3fc',
}

export default function Mermaid({ chart }: MermaidProps) {
  const ref = useRef<HTMLDivElement>(null)
  const { resolvedTheme } = useTheme()
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    // resolvedTheme is undefined until next-themes has read the DOM, and
    // rendering twice in a row would flash the wrong palette.
    if (!resolvedTheme) return

    let cancelled = false
    const isDark = resolvedTheme === 'dark'

    import('mermaid').then(async (m) => {
      const mermaid = m.default

      mermaid.initialize({
        startOnLoad: false,
        securityLevel: 'strict',
        theme: 'base',
        themeVariables: {
          ...(isDark ? DARK : LIGHT),
          fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
          fontSize: '14px',
        },
      })

      const id = `mermaid-${Math.random().toString(36).slice(2)}`

      try {
        const { svg } = await mermaid.render(id, chart.trim())
        if (cancelled || !ref.current) return
        ref.current.innerHTML = svg
        setError(null)
      } catch (err) {
        if (cancelled) return
        // A failed render leaves mermaid's scratch node parented to <body>.
        document.getElementById(id)?.remove()
        document.getElementById(`d${id}`)?.remove()
        setError(err instanceof Error ? err.message : String(err))
      }
    })

    return () => {
      cancelled = true
    }
  }, [chart, resolvedTheme])

  if (error) {
    return (
      <pre
        style={{
          margin: '1.5rem 0',
          padding: '1rem',
          border: '1px solid #f43f5e',
          borderRadius: '8px',
          color: '#f43f5e',
          fontSize: '0.8rem',
          whiteSpace: 'pre-wrap',
        }}
      >
        Diagram failed to render: {error}
      </pre>
    )
  }

  return (
    <div
      ref={ref}
      style={{
        display: 'flex',
        justifyContent: 'center',
        background: 'var(--ag-surface-raised)',
        borderRadius: '12px',
        border: '1px solid var(--ag-border)',
        padding: '1.75rem',
        overflowX: 'auto',
        margin: '1.5rem 0',
      }}
    />
  )
}
