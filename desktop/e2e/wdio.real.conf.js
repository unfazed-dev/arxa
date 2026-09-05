// WebdriverIO config — REAL engine gate. Same embedded-WebDriver app launch
// as wdio.conf.js, but the app targets a live engine (ARXA_STUDIO_URL must
// point at a running `bin/arxa-studio.mjs`; default :7891) and the only
// specs are the real-engine ones. Run: `npm run gate:real`.
import { config as base } from './wdio.conf.js'

if (!process.env.ARXA_STUDIO_URL) {
  console.error('gate:real: ARXA_STUDIO_URL is required (e.g. http://arxa.studio.localhost:7891 with the engine running)')
  process.exit(2)
}

export const config = {
  ...base,
  specs: ['./specs/real-engine/**/*.js'],
  exclude: [],
}
