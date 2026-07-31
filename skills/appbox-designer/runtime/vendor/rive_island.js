/* rive_island.js — named island (ADR-0002 islands amendment).
   Data-attribute init for Rive .riv assets; global `rive` comes from the
   vendored canvas-single build. No globals added, no server calls.
     <div data-rive="/assets/media/off_road_car.riv" [data-rive-state-machine="Name"]>
       <canvas data-rive-canvas width="640" height="360"></canvas>
       <button data-rive-action="play|pause">…</button>
       <span data-rive-inputs></span>   <- island renders one button per
                                           discovered state-machine input
     </div>
   Test hooks: data-rive-ready="true" on load; data-rive-last-fired set to
   the last triggered input name. */
(() => {
  const boot = (root) => {
    const canvas = root.querySelector('[data-rive-canvas]');
    if (!canvas || !window.rive) return;
    const sm = root.dataset.riveStateMachine || null;
    const inst = new window.rive.Rive({
      src: root.dataset.rive,
      canvas,
      stateMachines: sm || undefined,
      autoplay: true,
      layout: new window.rive.Layout({
        fit: window.rive.Fit.Contain,
        alignment: window.rive.Alignment.Center,
      }),
      onLoad: () => {
        root.dataset.riveReady = 'true';
        const name = sm || inst.stateMachineNames[0];
        const tray = root.querySelector('[data-rive-inputs]');
        // stateMachineInputs() can return undefined when a .riv's state machine
        // isn't synchronously queryable at onLoad — guard so the input tray
        // simply stays empty instead of throwing (render + play/pause still work).
        const inputs = tray && name ? inst.stateMachineInputs(name) : null;
        if (inputs) {
          inputs.forEach((input) => {
            const b = document.createElement('button');
            b.type = 'button';
            b.className = 'chip';
            b.dataset.riveFire = input.name;
            b.textContent = input.name;
            tray.appendChild(b);
          });
        }
      },
    });
    root.addEventListener('click', (e) => {
      const btn = e.target.closest('[data-rive-action],[data-rive-fire]');
      if (!btn || !root.contains(btn)) return;
      if (btn.dataset.riveAction === 'play') inst.play();
      if (btn.dataset.riveAction === 'pause') inst.pause();
      if (btn.dataset.riveFire) {
        const name = sm || inst.stateMachineNames[0];
        const inputs = name ? inst.stateMachineInputs(name) : null;
        const input = inputs && inputs.find((i) => i.name === btn.dataset.riveFire);
        if (input && typeof input.fire === 'function') input.fire();
        else if (input && 'value' in input) input.value = !input.value;
        root.dataset.riveLastFired = btn.dataset.riveFire;
      }
    });
  };
  const arm = () =>
    document.querySelectorAll('[data-rive]').forEach((r) => {
      if (!r.dataset.riveArmed) {
        r.dataset.riveArmed = '1';
        boot(r);
      }
    });
  document.addEventListener('DOMContentLoaded', arm);
  document.body.addEventListener('htmx:load', arm);
})();
