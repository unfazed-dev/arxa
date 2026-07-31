/* dotlottie_island.js — named island (ADR-0002 islands amendment).
   Imports the dotLottie web component and pins its WASM to the vendored
   copy. The pin MUST land before any <dotlottie-wc> element's first Lit
   update fetches the runtime: ES module evaluation completes before the
   microtask queue (Lit updates) flushes, so importing + calling here is
   a deterministic win over elements already in the DOM. */
import { setWasmUrl } from './dotlottie-wc.js';
setWasmUrl('/assets/vendor/dotlottie-player.wasm');
