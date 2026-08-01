/* map_island.js — named island (ADR-0002 islands amendment).
   Data-attribute init for Leaflet maps; global `L` comes from the vendored
   leaflet/leaflet.js (absent → quiet no-op). No globals added, no server calls.
     <div data-map
          [data-map-lat="…"] [data-map-lng="…"] [data-map-zoom="…"]
          [data-map-marker="lat,lng|lat,lng"]
          [data-map-tiles="https://…/{z}/{x}/{y}.png"]
          style="height:320px"></div>
   Defaults: 0/0/2, OSM tiles. OSM attribution is always set (tile ToS).
   Marker sprites resolve offline: L.Icon.Default.imagePath is pinned to the
   vendored leaflet/images/ dir. Test hook: data-map-ready="true". */
(() => {
  const OSM_TILES = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  const OSM_ATTR =
    '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors';
  const num = (s, dflt) => {
    const n = parseFloat(s);
    return Number.isFinite(n) ? n : dflt;
  };
  const boot = (root) => {
    if (!window.L || root._mapIsland) return;
    const L = window.L;
    L.Icon.Default.imagePath = '/assets/vendor/leaflet/images/';
    const map = L.map(root).setView(
      [num(root.dataset.mapLat, 0), num(root.dataset.mapLng, 0)],
      num(root.dataset.mapZoom, 2),
    );
    L.tileLayer(root.dataset.mapTiles || OSM_TILES, {
      attribution: OSM_ATTR,
      maxZoom: 19,
    }).addTo(map);
    (root.dataset.mapMarker || '')
      .split('|')
      .map((pair) => pair.split(',').map((v) => parseFloat(v)))
      .filter(([lat, lng]) => Number.isFinite(lat) && Number.isFinite(lng))
      .forEach(([lat, lng]) => L.marker([lat, lng]).addTo(map));
    root._mapIsland = map;
    root.dataset.mapReady = 'true';
  };
  const arm = () =>
    document.querySelectorAll('[data-map]').forEach((r) => {
      if (!r.dataset.mapArmed) {
        r.dataset.mapArmed = '1';
        boot(r);
      }
    });
  document.addEventListener('DOMContentLoaded', arm);
  document.body.addEventListener('htmx:load', arm);
})();
