// @ts-check
// kit-facades/maps.js — Maps config facade for ejected web apps.
//
// Maps are client-side (mapbox-gl in the browser). This facade just provides
// the config the client needs. One wired provider per config/kit-registry.json
// (maps kit: mapbox-gl + MAPBOX_PUBLIC_TOKEN); the keyless default is
// leaflet/OpenStreetMap — leaflet is already vendored, no env, no key.
//
// Env is passed in explicitly — never read at module scope (on Workers
// process.env does not exist). The token is publishable: it is also emitted
// into runtime/client_config.js at eject time.
//
// Env: MAPBOX_PUBLIC_TOKEN (publishable — optional; absence means leaflet/OSM)

/**
 * @param {Record<string, string | undefined>} env - process.env on node, ctx.env on Workers
 * @returns {{ provider: 'mapbox' | 'osm', token: string }}
 */
export function mapConfig(env) {
  const token = env.MAPBOX_PUBLIC_TOKEN;
  if (token) return { provider: 'mapbox', token };
  return { provider: 'osm', token: '' }; // leaflet/OpenStreetMap needs no key
}
