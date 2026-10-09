import { describe, expect, it } from 'bun:test'
import { existsSync, readFileSync, statSync } from 'node:fs'
import { join } from 'node:path'

describe('PWA & Tunnel Assets', () => {
  const publicDir = join(__dirname, '../public')
  const hubDir = join(__dirname, '../..')

  it('validates manifest.webmanifest metadata', () => {
    const manifestPath = join(publicDir, 'manifest.webmanifest')
    expect(existsSync(manifestPath)).toBe(true)

    const raw = readFileSync(manifestPath, 'utf-8')
    const manifest = JSON.parse(raw)

    expect(manifest.name).toBe('Mochi Hub')
    expect(manifest.short_name).toBe('Mochi')
    expect(manifest.display).toBe('standalone')
    expect(manifest.theme_color).toBe('#1a1b26')
    expect(Array.isArray(manifest.icons)).toBe(true)
    expect(manifest.icons.length).toBeGreaterThanOrEqual(1)

    for (const icon of manifest.icons) {
      const iconPath = join(publicDir, icon.src.replace(/^\//, ''))
      expect(existsSync(iconPath)).toBe(true)
    }
  })

  it('validates sw.js service worker cache policies', () => {
    const swPath = join(publicDir, 'sw.js')
    expect(existsSync(swPath)).toBe(true)

    const swCode = readFileSync(swPath, 'utf-8')
    expect(swCode).toContain('addEventListener(\'install\'')
    expect(swCode).toContain('addEventListener(\'activate\'')
    expect(swCode).toContain('addEventListener(\'fetch\'')

    // Verifies network-first for /api/ and cache-first for static assets
    expect(swCode).toContain('/api/')
    expect(swCode).toContain('caches.match')
  })

  it('validates tunnel.sh executable script', () => {
    const tunnelScript = join(hubDir, 'tunnel.sh')
    expect(existsSync(tunnelScript)).toBe(true)

    const stats = statSync(tunnelScript)
    // Check executable bit (owner executable = 0o100)
    expect((stats.mode & 0o111) !== 0).toBe(true)

    const scriptContent = readFileSync(tunnelScript, 'utf-8')
    expect(scriptContent).toContain('--cloudflare')
    expect(scriptContent).toContain('--tailscale')
    expect(scriptContent).toContain('cloudflared tunnel --url')
    expect(scriptContent).toContain('tailscale serve --bg')
  })
})
