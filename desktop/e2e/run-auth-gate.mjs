#!/usr/bin/env node
// BrowserAuth desktop gate (the 2026-09-05 lockout's follow-up): proves the
// shell reads $DSH_HOME/desktop-session.json and navigates its webview
// TOKENIZED — the only way past dsh 0.1.2-rc.1's "dsh web authentication
// required" 401. Hermetic by layering: an in-process fake engine implements
// the contract's HTTP surface (401 hint, token→303 exchange, cookie-gated
// 200) so this repo's gate needs no engine checkout; the REAL engine's half
// of the contract (actually publishing the file at boot, with a working
// token) is gated in arxa-studio's engine-boot-smoke, which logs in with the
// published file itself. The two gates meet at the documented JSON shape:
//   { "url": "<origin>/?token=<launch-token>", "token": "<launch-token>", … }
import { spawn } from 'node:child_process'
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { randomBytes } from 'node:crypto'
import http from 'node:http'

const here = dirname(fileURLToPath(import.meta.url))
const fakeHome = mkdtempSync(join(tmpdir(), 'arxa-auth-gate-'))
const token = randomBytes(24).toString('base64url')

const server = http.createServer((req, res) => {
  const u = new URL(req.url, 'http://x')
  const authed = (req.headers.cookie || '').includes('fake-auth=ok')
  console.log(`[auth-gate] ${req.method} ${req.url} cookie=${authed ? 'yes' : 'no'}`)
  if (u.pathname === '/' && u.searchParams.get('token') === token) {
    // Mirror dsh's exchange exactly: persistent authority cookie + the same
    // response headers dsh-client-connection puts on the 303.
    res.writeHead(303, {
      location: '/',
      'cache-control': 'no-store',
      'referrer-policy': 'no-referrer',
      'set-cookie': `fake-auth=ok; Max-Age=2592000; Path=/; Expires=${new Date(Date.now() + 2592000e3).toUTCString()}; HttpOnly; SameSite=Strict`,
    })
    res.end()
    return
  }
  if (authed) {
    res.writeHead(200, { 'content-type': 'text/html' })
    res.end('<!doctype html><html><head><title>studio</title></head><body><main id="studio"><h1>studio app</h1></main></body></html>')
    return
  }
  res.writeHead(401, { 'content-type': 'text/plain; charset=utf-8' })
  res.end('dsh web authentication required; reopen the URL printed by dsh web.\n')
})

const port = await new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server.address().port)))
const origin = `http://127.0.0.1:${port}`
writeFileSync(join(fakeHome, 'desktop-session.json'), JSON.stringify({
  url: `${origin}/?token=${token}`, token, pid: process.pid, at: new Date().toISOString(),
}) + '\n')
console.log(`[auth-gate] fake engine on :${port}, session file in ${fakeHome}`)

const child = spawn('npx', ['wdio', 'run', process.env.WDIO_CONF || 'wdio.auth.conf.js'], {
  cwd: here,
  env: { ...process.env, ARXA_STUDIO_URL: origin, ARXA_DSH_HOME: fakeHome },
  stdio: 'inherit',
})
child.on('exit', (code) => {
  server.close()
  try { rmSync(fakeHome, { recursive: true, force: true }) } catch {}
  process.exit(code ?? 1)
})
