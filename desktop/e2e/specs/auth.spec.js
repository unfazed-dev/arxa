// The BrowserAuth gate spec (2026-09-05 lockout): the desktop shell must
// turn $DSH_HOME/desktop-session.json into a tokenized first navigation —
// and, because WKWebView withholds the freshly minted SameSite=Strict
// cookie inside the exchange's own navigation chain, follow it with one
// clean first-party navigation (open_studio's two-step). Without that the
// window parks on the 401 hint with a valid cookie in the store — exactly
// what the installed app showed. run-auth-gate.mjs provides the fake
// engine (401 / token→303 / cookie-gated 200).
describe('arxa desktop shell — BrowserAuth gate', () => {
  it('exchanges the token and renders the engine UI on the clean root', async () => {
    // Arrival is the fake app's own marker: it only renders when the
    // cookie rides, so waiting for #studio subsumes "the two-step
    // navigation completed" — including its settle window.
    const app = await $('#studio')
    await app.waitForExist({ timeout: 60_000 })
    await expect($('#studio h1')).toHaveText('studio app')
    const url = await browser.getUrl()
    expect(url.startsWith('http://127.0.0.1:')).toBe(true)
    expect(url.includes('token=')).toBe(false)
    expect(await $('body').getText()).not.toContain('authentication required')
  })

  it('the engine refuses token-less requests (the gate is not vacuous)', async () => {
    // A GET from THIS spec process carries no cookie — if the engine under
    // test did not actually enforce auth, the first test's arrival at
    // #studio would prove nothing. The 401 hint must be the refusal shape.
    const root = await browser.getUrl()
    const res = await fetch(root, { redirect: 'manual' })
    expect(res.status).toBe(401)
    expect(await res.text()).toContain('authentication required')
  })
})
