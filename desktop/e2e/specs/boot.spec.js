// The WKWebView boot gate spec (D3): the one proof CI could not give
// before — the REAL WKWebView rendering the shell's bundled waiting page.
// With stub sidecars the engine never comes up, which is the point: the
// SHELL is the unit under test here; the engine's own boot is arxa-studio's
// engine-boot-smoke (npm run smoke in the engine repo).
describe('arxa desktop shell — WKWebView boot gate', () => {
  it('opens the main window with its title', async () => {
    await expect(browser).toHaveTitle('Arxa Studio')
  })

  it('renders the bundled waiting page in WKWebView', async () => {
    // The waiting page is the bundled frontend (src/index.html): brand
    // logo, app name, and the #status line main.js owns. Existence, not
    // status text — with stub sidecars the copy legitimately moves between
    // "Launching…" and its retry wording while nothing serves the port.
    const status = await $('#status')
    await status.waitForExist({ timeout: 30_000 })
    const h1 = await $('main.wait h1')
    await expect(h1).toHaveText('Arxa Studio')
    const logo = await $('main.wait img.logo')
    await expect(logo).toBePresent()
  })
})
