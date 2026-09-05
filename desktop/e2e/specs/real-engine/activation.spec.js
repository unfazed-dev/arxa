// Real-engine gate (wdio.real.conf.js, `npm run gate:real`): the app is
// pointed at a LIVE arxa studio engine (ARXA_STUDIO_URL, default
// http://arxa.studio.localhost:7891) and every plugin must activate.
// Fails on the dsh boot-failure card ("web boot: N entries did not
// activate" — e.g. the 2026-09-05 uiWorkspace self-inject deadlock).
// Excluded from `npm run gate` (that suite runs against a dead URL).
describe('real engine: plugin activation', () => {
  it('boots with no pending plugins on the clean root', async () => {
    await browser.waitUntil(async () => (await $('#root').isExisting()) && (await $('#root').getHTML(false)).length > 50, { timeout: 60_000, timeoutMsg: '#root never rendered — is the engine up at ARXA_STUDIO_URL?' })
    await browser.waitUntil(async () => (await $('[data-dsh-boot]').isExisting()) || (await $('body').getText()).length > 200, { timeout: 60_000, timeoutMsg: 'neither boot card nor UI appeared' })
    await browser.pause(4_000)
    const text = await $('body').getText()
    console.log('REAL url=', await browser.getUrl(), 'bodyLen=', text.length, 'bootCard=', await $('[data-dsh-boot]').isExisting())
    expect(text).not.toContain('did not activate')
    expect(text).not.toContain('Failed to load plugins')
    expect(text).not.toContain('authentication required')
  })
})
