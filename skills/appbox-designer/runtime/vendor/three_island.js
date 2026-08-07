/* three_island.js — named island (ADR-0002 islands amendment), ES module.
   Renders the one demo scene into any <div data-three-scene="orbit-demo">.
   Controls: buttons inside the container carrying
   data-three-toggle="rotate|wireframe".
   Test hooks: data-three-ready="true"; data-three-frames = rendered frame
   counter (updated every 30 frames); data-three-rotating mirrors toggle. */
import * as THREE from './three.module.min.js';

const boot = (root) => {
  const w = root.clientWidth || 320;
  const h = root.clientHeight || 320;
  const renderer = new THREE.WebGLRenderer({ antialias: true });
  renderer.setSize(w, h);
  root.appendChild(renderer.domElement);
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x101418);
  const camera = new THREE.PerspectiveCamera(50, w / h, 0.1, 100);
  camera.position.set(0, 1.2, 4);
  const key = new THREE.DirectionalLight(0xffffff, 2.2);
  key.position.set(3, 5, 4);
  scene.add(key, new THREE.AmbientLight(0x8899aa, 0.9));
  const mats = [0x4fc3f7, 0xffb74d, 0x81c784].map(
    (c) => new THREE.MeshStandardMaterial({ color: c, flatShading: true }),
  );
  const box = new THREE.Mesh(new THREE.BoxGeometry(1, 1, 1), mats[0]);
  box.position.x = -1.4;
  const knot = new THREE.Mesh(new THREE.TorusKnotGeometry(0.5, 0.16, 96, 16), mats[1]);
  const ico = new THREE.Mesh(new THREE.IcosahedronGeometry(0.7, 0), mats[2]);
  ico.position.x = 1.4;
  scene.add(box, knot, ico);
  const meshes = [box, knot, ico];
  let rotate = root.dataset.threeAutoRotate !== 'false';
  let frames = 0;
  root.addEventListener('click', (e) => {
    const btn = e.target.closest('[data-three-toggle]');
    if (!btn) return;
    if (btn.dataset.threeToggle === 'rotate') {
      rotate = !rotate;
      root.dataset.threeRotating = String(rotate);
    }
    if (btn.dataset.threeToggle === 'wireframe') {
      meshes.forEach((m) => {
        m.material.wireframe = !m.material.wireframe;
      });
    }
  });
  renderer.setAnimationLoop(() => {
    if (rotate) {
      meshes.forEach((m, i) => {
        m.rotation.x += 0.004 * (i + 1);
        m.rotation.y += 0.006 * (i + 1);
      });
    }
    renderer.render(scene, camera);
    frames += 1;
    if (frames % 30 === 0) root.dataset.threeFrames = String(frames);
  });
  root.dataset.threeReady = 'true';
};
const arm = () =>
  document.querySelectorAll('[data-three-scene]').forEach((r) => {
    if (!r.dataset.threeArmed) {
      r.dataset.threeArmed = '1';
      boot(r);
    }
  });
arm();
document.body.addEventListener('htmx:after:process', arm);
