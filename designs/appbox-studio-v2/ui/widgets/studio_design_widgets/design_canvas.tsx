// presentation: canvas island (runtime/vendor canvas.js + drag.js wire
//   panning/dragging through data-canvas hooks — no kit widget realises
//   it, F4 resolution). Inspect works on all devices.
// Role: the design canvas — the designed app as device tiles (v1
//   .device/.dv-frame vocabulary; stills carry the Portalo simulated
//   content). The tile set is the caller's business: desktop mounts all
//   three rungs, tablet mounts tablet+mobile, mobile mounts mobile only
//   (registry design_canvas note).
// Requirements: Q-v2-3, Q-v2-5 (inspect triple + annotation quad),
//   ADR-0002 (zero custom client JS — the canvas island is vendored).
// Relationships: composed by all three studio_design_view.<factor>.tsx
//   variants.
// History: created for studio v2; device classes carried from v1
//   viewer.css per the VISUAL PARITY LAW.
import type { FC } from 'hono/jsx';

export interface CanvasTile {
  id: string;
  surface: string;
  rung: 'desktop' | 'tablet' | 'mobile';
  width: number;
  src: string;
}

export interface DesignCanvasProps {
  title: string;
  tiles: CanvasTile[];
}

const tileLabel = (tile: CanvasTile): string => tile.surface + ' · ' + tile.rung + ' · ' + tile.width + 'px';

const DesignCanvas: FC<DesignCanvasProps> = ({ title, tiles }) => (
  <section
    class="design-canvas"
    aria-labelledby="design-canvas-h"
    data-canvas="design"
    data-inspect-widget="design_canvas"
    data-inspect-role="section"
    data-inspect-style="v1 device tiles on a pannable canvas region"
    data-inspect-fn="shows the designed app at every rung it exists at, inspectable on all devices"
    data-inspect-motion="reveal"
  >
    <h2
      id="design-canvas-h"
      class="design-canvas-title sr-only"
      data-inspect-role="heading"
      data-inspect-style="screen-reader heading — the tiles are the visual title"
      data-inspect-fn="names the canvas for assistive tech"
      data-inspect-motion="none"
    >
      {title}
    </h2>
    <div
      class="canvas-tiles"
      data-inspect-role="group"
      data-inspect-style="device tiles laid out by rung width"
      data-inspect-fn="holds one tile per designed-app rung"
      data-inspect-motion="reveal"
    >
      {tiles.map((tile) => (
        <figure
          key={tile.id}
          class={'device device--' + tile.rung}
          data-inspect-surface={tile.surface}
          data-inspect-role="figure"
          data-inspect-style={'device frame at ' + tile.width + 'px showing the designed ' + tile.rung}
          data-inspect-fn={'renders the designed app’s ' + tile.surface + ' at the ' + tile.rung + ' rung'}
          data-inspect-motion="reveal"
        >
          <img
            class="dv-frame"
            src={tile.src}
            alt={tileLabel(tile)}
            loading="lazy"
            data-inspect-role="image"
            data-inspect-style="the Portalo simulated content still"
            data-inspect-fn={'carries the designed ' + tile.surface + ' pixels'}
            data-inspect-motion="none"
          />
          <figcaption
            class="device-caption muted"
            data-inspect-role="label"
            data-inspect-style="surface · rung · width caption under the tile"
            data-inspect-fn="names what the tile shows"
            data-inspect-motion="none"
          >
            {tileLabel(tile)}
          </figcaption>
        </figure>
      ))}
    </div>
  </section>
);

export default DesignCanvas;
