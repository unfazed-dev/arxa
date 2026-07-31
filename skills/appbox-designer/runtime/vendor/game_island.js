/* game_island.js — named island (ADR-0002 islands amendment).
   "Dungeon Dash": an 11×11 top-down grid walker on a canvas, drawn with
   three Kenney tiny-dungeon tiles. Keyboard (arrows/WASD) and an on-screen
   d-pad (data-game-move) both move the hero; walking over a gem scores.
     <div data-game="dungeon-dash" data-game-tiles="/assets/media/kenney">
       <canvas data-game-canvas width="352" height="352"></canvas>
       <button data-game-move="up|down|left|right">…</button>
     </div>
   Test hooks: data-game-ready="true" once all tiles loaded;
   data-game-moves / data-game-score mirror state for the lens. */
(() => {
  const TILE = 32;
  const GRID = 11;
  const DIRS = {
    up: [0, -1], down: [0, 1], left: [-1, 0], right: [1, 0],
  };
  const KEYS = {
    ArrowUp: DIRS.up, ArrowDown: DIRS.down, ArrowLeft: DIRS.left,
    ArrowRight: DIRS.right, w: DIRS.up, s: DIRS.down, a: DIRS.left, d: DIRS.right,
  };
  const boot = (root) => {
    const canvas = root.querySelector('[data-game-canvas]');
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    const dir = root.dataset.gameTiles.replace(/\/$/, '');
    const floor = new Image();
    floor.src = `${dir}/tile_0000.png`;
    const heroImg = new Image();
    heroImg.src = `${dir}/tile_0084.png`;
    const gemImg = new Image();
    gemImg.src = `${dir}/tile_0085.png`;
    const hero = { x: 1, y: 1 };
    const gems = [
      { x: 5, y: 2 }, { x: 8, y: 4 }, { x: 3, y: 6 }, { x: 7, y: 8 }, { x: 9, y: 9 },
    ];
    let score = 0;
    let moves = 0;
    const inside = (x, y) => x > 0 && y > 0 && x < GRID - 1 && y < GRID - 1;
    const sync = () => {
      root.dataset.gameScore = String(score);
      root.dataset.gameMoves = String(moves);
    };
    const draw = () => {
      for (let y = 0; y < GRID; y += 1) {
        for (let x = 0; x < GRID; x += 1) {
          ctx.drawImage(floor, x * TILE, y * TILE, TILE, TILE);
        }
      }
      gems.forEach((g) => ctx.drawImage(gemImg, g.x * TILE, g.y * TILE, TILE, TILE));
      ctx.drawImage(heroImg, hero.x * TILE, hero.y * TILE, TILE, TILE);
    };
    const move = (dx, dy) => {
      const nx = hero.x + dx;
      const ny = hero.y + dy;
      if (!inside(nx, ny)) return;
      hero.x = nx;
      hero.y = ny;
      moves += 1;
      const i = gems.findIndex((g) => g.x === nx && g.y === ny);
      if (i >= 0) {
        gems.splice(i, 1);
        score += 1;
      }
      sync();
      draw();
    };
    document.addEventListener('keydown', (e) => {
      if (!KEYS[e.key] || !document.body.contains(root)) return;
      e.preventDefault();
      move(...KEYS[e.key]);
    });
    root.addEventListener('click', (e) => {
      const btn = e.target.closest('[data-game-move]');
      if (btn) move(...DIRS[btn.dataset.gameMove]);
    });
    let loaded = 0;
    [floor, heroImg, gemImg].forEach((img) =>
      img.addEventListener('load', () => {
        loaded += 1;
        if (loaded === 3) {
          root.dataset.gameReady = 'true';
          sync();
          draw();
        }
      }),
    );
  };
  const arm = () =>
    document.querySelectorAll('[data-game]').forEach((r) => {
      if (!r.dataset.gameArmed) {
        r.dataset.gameArmed = '1';
        boot(r);
      }
    });
  document.addEventListener('DOMContentLoaded', arm);
  document.body.addEventListener('htmx:load', arm);
})();
