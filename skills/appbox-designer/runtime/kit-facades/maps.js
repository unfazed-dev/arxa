// kit-facades/maps.js — Maps config facade for ejected web apps.
//
// Maps are client-side (mapbox-gl or leaflet in the browser). This facade
// just provides the config the client needs. Leaflet is already vendored;
// mapbox-gl would be added as an island.
//
// Env: MAPBOX_PUBLIC_TOKEN (publishable — emitted to client config)
//      GOOGLE_MAPS_API_KEY (publishable — alternative provider)

/** @returns {{ provider: string, token: string }} */
export function mapConfig() {
  const mapbox = process.env.MAPBOX_PUBLIC_TOKEN;
  if (mapbox) return { provider: 'mapbox', token: mapbox };
  const google = process.env.GOOGLE_MAPS_API_KEY;
  if (google) return { provider: 'google', token: google };
  return { provider: 'osm', token: '' }; // leaflet/OpenStreetMap needs no key
}
