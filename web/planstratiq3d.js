// Planstratiq 3D engine (Three.js) – v2
// Flutter šalje tlocrt kao JSON (setPlan). Engine gradi zidove s otvorima, podove s
// teksturama, krov i namještaj; nudi orbit pregled s odabirom/povlačenjem objekata,
// šetnju u prvom licu (miš + tipkovnica ili dodir), doba dana, snimku i sličice kataloga.
//
// Koordinate: tlocrt (x, y) u metrima -> 3D (x, 0, z = y); y je visina. Sjever = -z.

import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { PointerLockControls } from 'three/addons/controls/PointerLockControls.js';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';
import { Sky } from 'three/addons/objects/Sky.js';

const EYE = 1.65;
const RADIUS = 0.22;
const WALK = 1.5;
const RUN = 3.2;
const ACCENT = 0x0e6b66;

const rgb = (c) => Number(c) & 0xffffff;
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

// ------------------------------------------------------------------ teksture
const texCache = new Map();
function canvasTex(key, size, draw, repeatMeters) {
  const k = key + ':' + repeatMeters;
  if (texCache.has(k)) return texCache.get(k);
  const cv = document.createElement('canvas');
  cv.width = cv.height = size;
  const g = cv.getContext('2d');
  draw(g, size);
  const t = new THREE.CanvasTexture(cv);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 8;
  t.repeat.set(1 / repeatMeters, 1 / repeatMeters);
  texCache.set(k, t);
  return t;
}
function rnd(seed) {
  let s = seed >>> 0;
  return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296);
}
function noise(g, n, a, alpha, r) {
  for (let i = 0; i < a; i++) {
    const v = Math.floor(r() * 60) + 160;
    g.fillStyle = `rgba(${v},${v},${v},${alpha})`;
    g.fillRect(r() * n, r() * n, 1 + r() * 2, 1 + r() * 2);
  }
}
const textures = {
  wood: () => canvasTex('wood', 512, (g, n) => {
    const r = rnd(3);
    const rows = 8;
    for (let i = 0; i < rows; i++) {
      const y = (i * n) / rows;
      let x = -r() * n;
      while (x < n) {
        const len = n * (0.45 + r() * 0.4);
        const v = Math.floor(200 + r() * 45);
        g.fillStyle = `rgb(${v},${v},${v})`;
        g.fillRect(x, y, len, n / rows);
        g.strokeStyle = 'rgba(0,0,0,0.05)';
        for (let k = 0; k < 6; k++) {
          g.beginPath();
          const yy = y + r() * (n / rows);
          g.moveTo(x, yy);
          g.bezierCurveTo(x + len * 0.3, yy + (r() - 0.5) * 6, x + len * 0.7, yy + (r() - 0.5) * 6, x + len, yy);
          g.stroke();
        }
        g.fillStyle = 'rgba(0,0,0,0.18)';
        g.fillRect(x + len - 1, y, 1.5, n / rows);
        x += len;
      }
      g.fillStyle = 'rgba(0,0,0,0.22)';
      g.fillRect(0, y, n, 1.5);
    }
  }, 1.2),
  tile: () => canvasTex('tile', 256, (g, n) => {
    const r = rnd(5);
    const k = 4;
    for (let i = 0; i < k; i++) for (let j = 0; j < k; j++) {
      const v = Math.floor(232 + r() * 18);
      g.fillStyle = `rgb(${v},${v},${v})`;
      g.fillRect((i * n) / k, (j * n) / k, n / k, n / k);
    }
    g.fillStyle = 'rgba(120,120,120,0.55)';
    for (let i = 0; i <= k; i++) { g.fillRect((i * n) / k - 1, 0, 2, n); g.fillRect(0, (i * n) / k - 1, n, 2); }
  }, 1.2),
  largeTile: () => canvasTex('largeTile', 512, (g, n) => {
    const r = rnd(9);
    const k = 2;
    for (let i = 0; i < k; i++) for (let j = 0; j < k; j++) {
      const v = Math.floor(225 + r() * 20);
      g.fillStyle = `rgb(${v},${v},${v})`;
      g.fillRect((i * n) / k, (j * n) / k, n / k, n / k);
    }
    noise(g, n, 4000, 0.15, r);
    g.fillStyle = 'rgba(90,90,90,0.5)';
    for (let i = 0; i <= k; i++) { g.fillRect((i * n) / k - 1, 0, 2, n); g.fillRect(0, (i * n) / k - 1, n, 2); }
  }, 1.2),
  stone: () => canvasTex('stone', 512, (g, n) => {
    const r = rnd(11);
    g.fillStyle = '#e0e0e0';
    g.fillRect(0, 0, n, n);
    for (let y = 0; y < n;) {
      const h = n * (0.18 + r() * 0.12);
      let x = -r() * 80;
      while (x < n) {
        const w = n * (0.25 + r() * 0.3);
        const v = Math.floor(205 + r() * 40);
        g.fillStyle = `rgb(${v},${v - 4},${v - 10})`;
        g.fillRect(x + 2, y + 2, w - 4, h - 4);
        x += w;
      }
      y += h;
    }
    noise(g, n, 6000, 0.12, r);
  }, 1.6),
  concrete: () => canvasTex('concrete', 512, (g, n) => {
    const r = rnd(13);
    g.fillStyle = '#d8d8d8';
    g.fillRect(0, 0, n, n);
    for (let i = 0; i < 90; i++) {
      const v = Math.floor(190 + r() * 50);
      g.fillStyle = `rgba(${v},${v},${v},0.25)`;
      g.beginPath();
      g.arc(r() * n, r() * n, 10 + r() * 60, 0, Math.PI * 2);
      g.fill();
    }
    noise(g, n, 9000, 0.2, r);
  }, 3),
  carpet: () => canvasTex('carpet', 256, (g, n) => {
    const r = rnd(17);
    g.fillStyle = '#d4d4d4';
    g.fillRect(0, 0, n, n);
    noise(g, n, 14000, 0.35, r);
  }, 0.8),
  plain: () => null,
  grass: () => canvasTex('grass', 512, (g, n) => {
    const r = rnd(21);
    g.fillStyle = '#7fa65a';
    g.fillRect(0, 0, n, n);
    for (let i = 0; i < 26000; i++) {
      const h = 80 + r() * 50;
      g.fillStyle = `hsla(${h},${35 + r() * 25}%,${30 + r() * 25}%,0.55)`;
      g.fillRect(r() * n, r() * n, 1, 2 + r() * 3);
    }
  }, 4),
  roof: () => canvasTex('roof', 256, (g, n) => {
    const r = rnd(23);
    const rows = 8;
    for (let i = 0; i < rows; i++) {
      const y = (i * n) / rows;
      for (let j = 0; j < 9; j++) {
        const v = Math.floor(190 + r() * 50);
        g.fillStyle = `rgb(${v},${v},${v})`;
        g.fillRect((j * n) / 8 - (i % 2) * (n / 16), y, n / 8, n / rows);
      }
      g.fillStyle = 'rgba(0,0,0,0.3)';
      g.fillRect(0, y + n / rows - 3, n, 3);
    }
  }, 2),
  plaster: () => canvasTex('plaster', 256, (g, n) => {
    const r = rnd(29);
    g.fillStyle = '#f2f2f2';
    g.fillRect(0, 0, n, n);
    noise(g, n, 5000, 0.08, r);
  }, 2),
};

// ------------------------------------------------------------------ materijali
const matCache = new Map();
function mat(color, opts = {}) {
  const key = rgb(color) + '|' + JSON.stringify(opts);
  let m = matCache.get(key);
  if (m) return m;
  if (opts.glass) {
    m = new THREE.MeshPhysicalMaterial({ color: 0xcfe6ee, transparent: true, opacity: 0.22, roughness: 0.03, metalness: 0, depthWrite: false, envMapIntensity: 1.2 });
  } else {
    const map = opts.tex ? textures[opts.tex]?.() : null;
    m = new THREE.MeshStandardMaterial({
      color: rgb(color),
      map: map || null,
      roughness: opts.roughness ?? 0.85,
      metalness: opts.metalness ?? 0,
      side: opts.double ? THREE.DoubleSide : THREE.FrontSide,
      emissive: opts.emissive ? rgb(opts.emissive) : 0x000000,
      emissiveIntensity: opts.emissiveIntensity ?? 0,
      transparent: !!opts.opacity,
      opacity: opts.opacity ?? 1,
      envMapIntensity: opts.env ?? 1,
    });
  }
  matCache.set(key, m);
  return m;
}
const lighter = (c, f = 0.25) => new THREE.Color(rgb(c)).lerp(new THREE.Color(0xffffff), f).getHex();
const darker = (c, f = 0.35) => new THREE.Color(rgb(c)).lerp(new THREE.Color(0x000000), f).getHex();

// ------------------------------------------------------------------ namještaj
// Gradi objekt u lokalnim koordinatama: središte na podu, stražnja strana na -z.
function buildItem(it, g, loader) {
  const W = it.w, D = it.d, H = it.h;
  const color = it.color;
  const b = (w, h, d, x, y, z, c = color, opts) => {
    const m = new THREE.Mesh(new THREE.BoxGeometry(Math.max(w, 0.002), Math.max(h, 0.002), Math.max(d, 0.002)), mat(c, opts));
    m.position.set(x, y, z);
    m.castShadow = h > 0.03;
    m.receiveShadow = true;
    g.add(m);
    return m;
  };
  const cyl = (rt, rbot, h, x, y, z, c, seg = 24, opts) => {
    const m = new THREE.Mesh(new THREE.CylinderGeometry(rt, rbot, h, seg), mat(c, opts));
    m.position.set(x, y, z);
    m.castShadow = true;
    m.receiveShadow = true;
    g.add(m);
    return m;
  };
  const sphere = (r, x, y, z, c, sy = 1, opts = { roughness: 1 }) => {
    const m = new THREE.Mesh(new THREE.SphereGeometry(r, 22, 16), mat(c, opts));
    m.position.set(x, y, z);
    m.scale.y = sy;
    m.castShadow = true;
    g.add(m);
    return m;
  };
  const legs = (w, d, h, inset = 0.05, t = 0.045, c = color) => {
    for (const sx of [-1, 1]) for (const sz of [-1, 1]) b(t, h, t, sx * (w / 2 - inset), h / 2, sz * (d / 2 - inset), c);
  };
  const metal = { metalness: 0.6, roughness: 0.35 };

  if (it.modelUrl && loader) {
    loadModel(loader, it.modelUrl, g, W, D, H, color);
    return;
  }

  switch (it.shape) {
    case 'bed':
    case 'bunk': {
      const levels = it.shape === 'bunk' ? [0, 1.1] : [0];
      for (const y0 of levels) {
        b(W, 0.3, D, 0, y0 + 0.15, 0);
        b(W - 0.06, 0.2, D - 0.12, 0, y0 + 0.4, 0.04, 0xf4f1ea, { roughness: 1 });
        b(W - 0.08, 0.06, D * 0.58, 0, y0 + 0.53, D * 0.2, lighter(color, 0.55), { roughness: 1 });
        const pw = Math.min(0.62, W * 0.42);
        for (const sx of W > 1.2 ? [-1, 1] : [0]) b(pw, 0.13, 0.38, sx * W * 0.23, y0 + 0.57, -D / 2 + 0.32, 0xffffff, { roughness: 1 });
      }
      const hb = it.shape === 'bunk' ? H : Math.min(H, 1.1);
      b(W, hb, 0.08, 0, hb / 2, -D / 2 + 0.04);
      if (it.shape === 'bunk') for (const sx of [-1, 1]) b(0.06, H, 0.06, sx * (W / 2 - 0.03), H / 2, D / 2 - 0.03);
      break;
    }
    case 'sofa': {
      const sh = 0.26;
      b(W, sh, D, 0, sh / 2, 0, darker(color, 0.12));
      const arm = Math.min(0.18, W * 0.2);
      const seatW = W - arm * 2;
      const n = Math.max(1, Math.round(seatW / 0.7));
      for (let i = 0; i < n; i++) {
        const cw = seatW / n;
        b(cw - 0.015, 0.17, D - 0.26, -seatW / 2 + cw * (i + 0.5), sh + 0.085, 0.11, lighter(color, 0.08), { roughness: 1 });
      }
      b(W, H - sh, 0.22, 0, sh + (H - sh) / 2, -D / 2 + 0.11);
      for (const sx of [-1, 1]) b(arm, 0.62, D, sx * (W / 2 - arm / 2), 0.31, 0);
      break;
    }
    case 'sofa_corner': {
      const sd = Math.min(0.95, D), cw = Math.min(0.95, W), sh = 0.26;
      b(W, sh, sd, 0, sh / 2, -D / 2 + sd / 2, darker(color, 0.12));
      b(cw, sh, D - sd, W / 2 - cw / 2, sh / 2, -D / 2 + sd + (D - sd) / 2, darker(color, 0.12));
      b(W - 0.4, 0.17, sd - 0.24, -0.1, sh + 0.085, -D / 2 + 0.22 + (sd - 0.24) / 2, lighter(color, 0.08), { roughness: 1 });
      b(cw - 0.24, 0.17, D - sd, W / 2 - 0.22 - (cw - 0.24) / 2, sh + 0.085, -D / 2 + sd + (D - sd) / 2, lighter(color, 0.08), { roughness: 1 });
      b(W, H - sh, 0.22, 0, sh + (H - sh) / 2, -D / 2 + 0.11);
      b(0.22, H - sh, D, W / 2 - 0.11, sh + (H - sh) / 2, 0);
      b(0.18, 0.62, sd, -W / 2 + 0.09, 0.31, -D / 2 + sd / 2);
      break;
    }
    case 'table':
    case 'island': {
      if (it.shape === 'island') {
        b(W, H - 0.04, D - 0.3, 0, (H - 0.04) / 2, -0.15);
        b(W, 0.04, D, 0, H - 0.02, 0, 0x3f4244, { roughness: 0.35 });
      } else {
        b(W, 0.04, D, 0, H - 0.02, 0);
        legs(W, D, H - 0.04, 0.06, 0.05);
      }
      break;
    }
    case 'table_round': {
      cyl(W / 2, W / 2, 0.04, 0, H - 0.02, 0, color, 40);
      cyl(0.05, 0.05, H - 0.04, 0, (H - 0.04) / 2, 0, darker(color, 0.3), 12);
      cyl(0.28, 0.3, 0.03, 0, 0.015, 0, darker(color, 0.3), 24);
      break;
    }
    case 'chair': {
      const seat = Math.min(0.46, H * 0.5);
      b(W, 0.05, D, 0, seat, 0);
      legs(W, D, seat - 0.025, 0.03, 0.035);
      b(W, H - seat, 0.04, 0, seat + (H - seat) / 2, -D / 2 + 0.02);
      break;
    }
    case 'stool': {
      cyl(W / 2, W / 2, 0.05, 0, H - 0.025, 0, color, 24);
      cyl(0.025, 0.025, H - 0.05, 0, (H - 0.05) / 2, 0, 0x777777, 10, metal);
      cyl(W * 0.4, W * 0.42, 0.02, 0, 0.01, 0, 0x555555, 24, metal);
      break;
    }
    case 'wardrobe': {
      b(W, H, D, 0, H / 2, 0);
      const doors = Math.max(2, Math.round(W / 0.5));
      for (let i = 1; i < doors; i++) b(0.006, H - 0.06, 0.006, -W / 2 + (i * W) / doors, H / 2, D / 2 + 0.003, darker(color, 0.4));
      for (let i = 0; i < doors; i++) {
        const x = -W / 2 + ((i + 0.5) * W) / doors + (i % 2 ? -1 : 1) * (W / doors / 2 - 0.05);
        b(0.015, 0.25, 0.025, x, H * 0.52, D / 2 + 0.013, 0x9a9a9a, metal);
      }
      break;
    }
    case 'dresser':
    case 'box': {
      b(W, H, D, 0, H / 2, 0);
      if (it.shape === 'dresser') {
        const rows = Math.max(1, Math.round(H / 0.22));
        for (let i = 1; i < rows; i++) b(W - 0.02, 0.006, 0.006, 0, (i * H) / rows, D / 2 + 0.003, darker(color, 0.35));
        for (let i = 0; i < rows; i++) b(Math.min(0.2, W * 0.3), 0.015, 0.02, 0, ((i + 0.5) * H) / rows, D / 2 + 0.01, 0x9a9a9a, metal);
      }
      break;
    }
    case 'shelf': {
      const t = 0.025;
      for (const sx of [-1, 1]) b(t, H, D, sx * (W / 2 - t / 2), H / 2, 0);
      b(W, H, 0.01, 0, H / 2, -D / 2 + 0.005);
      const n = Math.max(2, Math.round(H / 0.38));
      const r = rnd(Math.floor(W * 1000 + H * 100));
      for (let i = 0; i <= n; i++) b(W - 2 * t, t, D, 0, t / 2 + (i * (H - t)) / n, 0);
      for (let i = 0; i < n; i++) {
        const y0 = t + (i * (H - t)) / n;
        let x = -W / 2 + t + 0.02;
        while (x < W / 2 - t - 0.06) {
          const bw = 0.025 + r() * 0.03, bh = Math.min(0.18 + r() * 0.1, (H - t) / n - 0.04);
          b(bw, bh, D * 0.75, x + bw / 2, y0 + bh / 2, 0.01, [0x8a3b2f, 0x2f5a8a, 0xd9b25a, 0x4e7a4a, 0x555555, 0xe8e2d4][Math.floor(r() * 6)]);
          x += bw + 0.004;
          if (r() < 0.08) x += 0.12;
        }
      }
      break;
    }
    case 'kitchen':
    case 'vanity': {
      const base = Math.min(H, 0.9);
      b(W, base - 0.1, D - 0.03, 0, 0.1 + (base - 0.1) / 2, -0.015);
      b(W - 0.02, 0.1, D - 0.08, 0, 0.05, -0.04, 0x2a2a2a);
      b(W, 0.04, D, 0, base - 0.02, 0, it.shape === 'vanity' ? 0xf4f4f2 : 0x4a4d4f, { roughness: 0.35 });
      const n = Math.max(1, Math.round(W / 0.6));
      for (let i = 1; i < n; i++) b(0.006, base - 0.16, 0.005, -W / 2 + (i * W) / n, 0.1 + (base - 0.14) / 2, D / 2 - 0.028, darker(color, 0.25));
      for (let i = 0; i < n; i++) b(Math.min(0.3, (W / n) * 0.6), 0.015, 0.02, -W / 2 + ((i + 0.5) * W) / n, base - 0.12, D / 2 - 0.015, 0x8a8a8a, metal);
      if (it.shape === 'vanity') {
        const basin = new THREE.Mesh(new THREE.CylinderGeometry(Math.min(0.22, W * 0.3), Math.min(0.18, W * 0.25), 0.12, 32), mat(0xffffff, { roughness: 0.2 }));
        basin.scale.z = 0.75;
        basin.position.set(0, base + 0.06, 0.02);
        g.add(basin);
        cyl(0.012, 0.012, 0.2, 0, base + 0.1, -D / 2 + 0.06, 0xcccccc, 10, metal);
        b(Math.min(W, 0.8) - 0.1, 0.7, 0.02, 0, base + 0.75, -D / 2 + 0.01, 0xdde8ea, { roughness: 0.05, metalness: 0.8 });
      } else if (W >= 1.7) {
        b(0.6, 0.012, D * 0.62, -W * 0.18, base + 0.002, 0, 0xb5b7b8, metal);
        cyl(0.012, 0.012, 0.3, -W * 0.18, base + 0.15, -D / 2 + 0.08, 0xcccccc, 10, metal);
        b(0.6, 0.008, 0.52, W * 0.22, base + 0.004, 0, 0x111111, { roughness: 0.2 });
      }
      if (H > 1.5) {
        b(W, 0.72, 0.35, 0, H - 0.36, -D / 2 + 0.175);
        for (let i = 1; i < n; i++) b(0.006, 0.68, 0.005, -W / 2 + (i * W) / n, H - 0.36, -D / 2 + 0.353, darker(color, 0.25));
        b(W, 0.6, 0.01, 0, base + 0.31, -D / 2 + 0.005, 0xe6e2da, { tex: 'tile' });
        if (W >= 1.7) b(0.6, 0.12, 0.35, W * 0.22, H - 0.78, -D / 2 + 0.175, 0x9a9a9a, metal);
      }
      break;
    }
    case 'stove': {
      b(W, H - 0.02, D, 0, (H - 0.02) / 2, 0);
      b(W, 0.02, D, 0, H - 0.01, 0, 0x111111, { roughness: 0.15 });
      b(W - 0.08, H * 0.45, 0.01, 0, H * 0.4, D / 2 + 0.005, 0x1a1a1a, { roughness: 0.1 });
      break;
    }
    case 'fridge': {
      b(W, H, D, 0, H / 2, 0, color, { roughness: 0.3, metalness: 0.3 });
      b(W - 0.01, 0.006, 0.006, 0, H * 0.62, D / 2 + 0.003, 0x777777);
      b(0.02, 0.35, 0.03, W / 2 - 0.06, H * 0.78, D / 2 + 0.015, 0x888888, metal);
      b(0.02, 0.35, 0.03, W / 2 - 0.06, H * 0.45, D / 2 + 0.015, 0x888888, metal);
      break;
    }
    case 'washer': {
      b(W, H, D, 0, H / 2, 0, color, { roughness: 0.3 });
      const door = cyl(Math.min(W, H) * 0.3, Math.min(W, H) * 0.3, 0.04, 0, H * 0.45, D / 2, 0x3a4248, 32, { roughness: 0.1, metalness: 0.4 });
      door.rotation.x = Math.PI / 2;
      b(W - 0.04, 0.1, 0.01, 0, H - 0.07, D / 2 + 0.005, 0xdddddd);
      break;
    }
    case 'tv': {
      b(W, 0.5, D, 0, 0.25, 0);
      const sw = Math.min(W * 0.8, 1.45), sh = sw * 0.57;
      b(sw, sh, 0.035, 0, 0.58 + sh / 2, -D / 2 + 0.12, 0x0d0d0d, { roughness: 0.15 });
      b(0.3, 0.05, 0.2, 0, 0.525, -D / 2 + 0.12, 0x222222);
      break;
    }
    case 'lamp': {
      cyl(0.15, 0.15, 0.03, 0, 0.015, 0, 0x2a2a2a);
      cyl(0.012, 0.012, H - 0.3, 0, (H - 0.3) / 2, 0, 0x2a2a2a, 8);
      cyl(W * 0.35, W * 0.48, 0.3, 0, H - 0.15, 0, color, 24, { emissive: 0xffd9a0, emissiveIntensity: 0.7, double: true });
      break;
    }
    case 'plant': {
      cyl(W * 0.3, W * 0.24, H * 0.3, 0, H * 0.15, 0, 0xc9b8a0);
      const r = rnd(7);
      for (let i = 0; i < 6; i++) {
        sphere(W * (0.22 + r() * 0.12), (r() - 0.5) * W * 0.4, H * (0.5 + r() * 0.35), (r() - 0.5) * W * 0.4, i % 2 ? color : lighter(color, 0.15), 1.2);
      }
      break;
    }
    case 'rug':
    case 'path': {
      const h = Math.max(H, 0.01);
      b(W, h, D, 0, h / 2 + 0.034, 0, color, it.shape === 'path' ? { tex: 'stone' } : { tex: 'carpet', roughness: 1 });
      break;
    }
    case 'rug_round': {
      cyl(W / 2, W / 2, 0.012, 0, 0.04, 0, color, 48, { tex: 'carpet', roughness: 1 });
      break;
    }
    case 'fireplace': {
      b(W, H, D, 0, H / 2, 0, color, { tex: 'stone' });
      b(W * 0.55, H * 0.5, 0.05, 0, H * 0.3, D / 2 - 0.02, 0x141414);
      b(W * 0.45, 0.12, 0.03, 0, H * 0.13, D / 2 - 0.01, 0xff8a3d, { emissive: 0xff6a1a, emissiveIntensity: 1.2 });
      b(W + 0.1, 0.06, D + 0.06, 0, H + 0.03, 0, 0xd8d2c8);
      break;
    }
    case 'stairs': {
      const steps = Math.max(3, Math.round(H / 0.175));
      const run = D / steps;
      for (let i = 0; i < steps; i++) {
        const y = ((i + 1) * H) / steps;
        b(W, 0.04, run + 0.02, 0, y - 0.02, D / 2 - run * (i + 0.5), color);
        b(W, H / steps - 0.04, 0.02, 0, y - H / steps / 2 - 0.02, D / 2 - run * i, 0xf2f0ec);
      }
      const rail = b(0.04, 0.04, Math.hypot(D, H), W / 2 - 0.03, H / 2 + 0.9, 0, 0x333333);
      rail.rotation.x = Math.atan2(H, D);
      break;
    }
    case 'bath': {
      b(W, H, D, 0, H / 2, 0, 0xffffff, { roughness: 0.25 });
      b(W - 0.12, 0.02, D - 0.12, 0, H - 0.05, 0, 0x9fc9e0, { roughness: 0.05 });
      cyl(0.015, 0.015, 0.2, -W / 2 + 0.12, H + 0.08, 0, 0xcccccc, 10, metal);
      break;
    }
    case 'shower': {
      b(W, 0.05, D, 0, 0.025, 0, 0xffffff, { roughness: 0.3 });
      b(W, H, 0.01, 0, H / 2, D / 2 - 0.005, 0, { glass: true });
      b(0.01, H, D, W / 2 - 0.005, H / 2, 0, 0, { glass: true });
      b(0.02, H, 0.02, W / 2 - 0.01, H / 2, D / 2 - 0.01, 0xbbbbbb, metal);
      cyl(0.1, 0.1, 0.02, 0, H - 0.1, -D / 2 + 0.2, 0xcccccc, 20, metal);
      b(0.02, 0.02, 0.2, 0, H - 0.08, -D / 2 + 0.1, 0xcccccc, metal);
      break;
    }
    case 'toilet': {
      const bowl = cyl(W * 0.48, W * 0.36, 0.4, 0, 0.2, D * 0.1, 0xffffff, 32, { roughness: 0.2 });
      bowl.scale.z = 1.35;
      b(W, 0.38, 0.18, 0, 0.6, -D / 2 + 0.09, 0xffffff, { roughness: 0.2 });
      const seat = cyl(W * 0.49, W * 0.49, 0.03, 0, 0.415, D * 0.1, 0xf6f6f6, 32);
      seat.scale.z = 1.35;
      break;
    }
    case 'tree': {
      const trunkH = H * 0.42;
      cyl(W * 0.035, W * 0.055, trunkH, 0, trunkH / 2, 0, 0x6b4a2f, 10);
      const r = rnd(Math.floor(W * 97));
      for (let i = 0; i < 7; i++) {
        const rr = W * (0.26 + r() * 0.12);
        sphere(rr, (r() - 0.5) * W * 0.45, trunkH + (H - trunkH) * (0.3 + r() * 0.4), (r() - 0.5) * W * 0.45, i % 2 ? color : lighter(color, 0.12), 0.9);
      }
      break;
    }
    case 'cypress': {
      cyl(0.06, 0.08, 0.5, 0, 0.25, 0, 0x5a3e28, 8);
      const c = new THREE.Mesh(new THREE.SphereGeometry(W / 2, 18, 18), mat(color, { roughness: 1 }));
      c.scale.y = (H - 0.3) / W;
      c.position.y = 0.3 + (H - 0.3) / 2;
      c.castShadow = true;
      g.add(c);
      break;
    }
    case 'hedge': {
      const geo = new THREE.BoxGeometry(W, H, D, 6, 4, 2);
      const p = geo.attributes.position;
      const r = rnd(5);
      for (let i = 0; i < p.count; i++) p.setXYZ(i, p.getX(i) * (1 + (r() - 0.5) * 0.06), p.getY(i) * (1 + (r() - 0.5) * 0.05), p.getZ(i) * (1 + (r() - 0.5) * 0.15));
      geo.computeVertexNormals();
      const m = new THREE.Mesh(geo, mat(color, { roughness: 1 }));
      m.position.y = H / 2;
      m.castShadow = true;
      m.receiveShadow = true;
      g.add(m);
      break;
    }
    case 'flowerbed': {
      b(W, 0.25, D, 0, 0.125, 0, 0x8a6b4f, { tex: 'concrete' });
      b(W - 0.08, 0.02, D - 0.08, 0, 0.25, 0, 0x4a3626, { roughness: 1 });
      const r = rnd(31);
      const cols = [0xd9667a, 0xe8c04a, 0x8e6bc6, 0xf2f2f2];
      const count = Math.min(80, Math.round(W * D * 18));
      for (let i = 0; i < count; i++) {
        sphere(0.05 + r() * 0.05, (r() - 0.5) * (W - 0.15), 0.32 + r() * 0.1, (r() - 0.5) * (D - 0.15), i % 3 ? 0x4f7f4a : cols[i % 4], 1);
      }
      break;
    }
    case 'fence': {
      const n = Math.max(1, Math.round(W / 1.0));
      for (let i = 0; i <= n; i++) b(0.07, H, 0.07, -W / 2 + (i * W) / n, H / 2, 0);
      const slats = Math.round(W / 0.12);
      for (let i = 0; i < slats; i++) b(0.08, H * 0.85, 0.02, -W / 2 + (i + 0.5) * (W / slats), H * 0.45, 0.03);
      break;
    }
    case 'pool': {
      b(W, 0.06, D, 0, 0.0, 0, color, { roughness: 0.05, metalness: 0.1, opacity: 0.9 });
      const rim = 0xe9e6df;
      b(W + 0.6, 0.06, 0.3, 0, 0.03, -D / 2 - 0.15, rim, { tex: 'stone' });
      b(W + 0.6, 0.06, 0.3, 0, 0.03, D / 2 + 0.15, rim, { tex: 'stone' });
      b(0.3, 0.06, D, -W / 2 - 0.15, 0.03, 0, rim, { tex: 'stone' });
      b(0.3, 0.06, D, W / 2 + 0.15, 0.03, 0, rim, { tex: 'stone' });
      break;
    }
    case 'deck': {
      const n = Math.max(2, Math.round(D / 0.15));
      for (let i = 0; i < n; i++) b(W, H, D / n - 0.01, 0, H / 2, -D / 2 + (i + 0.5) * (D / n), i % 2 ? color : lighter(color, 0.06), { roughness: 0.8 });
      break;
    }
    case 'lounger': {
      b(W, 0.3, D, 0, 0.15, 0, 0xb9b9b4);
      b(W - 0.06, 0.06, D * 0.7, 0, 0.33, D * 0.13, color, { roughness: 1 });
      const back = b(W - 0.06, 0.06, D * 0.35, 0, 0.45, -D / 2 + 0.2, color, { roughness: 1 });
      back.rotation.x = 0.6;
      break;
    }
    case 'umbrella': {
      cyl(0.25, 0.25, 0.05, 0, 0.025, 0, 0x555555);
      cyl(0.02, 0.02, H, 0, H / 2, 0, 0x777777, 8);
      const top = new THREE.Mesh(new THREE.ConeGeometry(W / 2, 0.45, 8, 1, true), mat(color, { double: true }));
      top.position.y = H - 0.15;
      top.castShadow = true;
      g.add(top);
      break;
    }
    case 'grill': {
      b(W, 0.8, D, 0, 0.4, 0, color, { roughness: 0.5, metalness: 0.3 });
      const lid = cyl(D / 2, D / 2, W * 0.6, -W * 0.12, 0.8, 0, darker(color, 0.2), 24, { roughness: 0.4, metalness: 0.4 });
      lid.rotation.z = Math.PI / 2;
      break;
    }
    case 'trampoline': {
      const ring = new THREE.Mesh(new THREE.TorusGeometry(W / 2 - 0.05, 0.05, 8, 48), mat(0x2f6fb0));
      ring.rotation.x = Math.PI / 2;
      ring.position.y = H;
      g.add(ring);
      cyl(W / 2 - 0.1, W / 2 - 0.1, 0.01, 0, H - 0.02, 0, 0x1a1a1a, 48);
      for (let i = 0; i < 6; i++) {
        const a = (i / 6) * Math.PI * 2;
        cyl(0.025, 0.025, H, Math.cos(a) * (W / 2 - 0.08), H / 2, Math.sin(a) * (W / 2 - 0.08), 0x777777, 8, metal);
      }
      break;
    }
    case 'swing': {
      for (const sx of [-1, 1]) {
        const l1 = b(0.08, H * 1.06, 0.08, sx * (W / 2), H / 2, -D * 0.16, color);
        l1.rotation.x = 0.3;
        const l2 = b(0.08, H * 1.06, 0.08, sx * (W / 2), H / 2, D * 0.16, color);
        l2.rotation.x = -0.3;
      }
      b(W + 0.1, 0.1, 0.1, 0, H, 0, color);
      for (const sx of [-0.25, 0.25]) {
        b(0.012, H - 0.45, 0.012, sx * W - 0.18, (H + 0.45) / 2, 0, 0x777777);
        b(0.012, H - 0.45, 0.012, sx * W + 0.18, (H + 0.45) / 2, 0, 0x777777);
        b(0.45, 0.04, 0.2, sx * W, 0.45, 0, 0x2f6fb0);
      }
      break;
    }
    case 'shed': {
      const wallH = H * 0.75;
      b(W, wallH, D, 0, wallH / 2, 0, color, { roughness: 0.9 });
      const rh = H - wallH;
      const half = Math.hypot(W / 2 + 0.15, rh);
      for (const sx of [-1, 1]) {
        const p = b(half, 0.04, D + 0.3, sx * (W / 4 + 0.04), wallH + rh / 2, 0, 0x4a4a4a);
        p.rotation.z = -sx * Math.atan2(rh, W / 2 + 0.15);
      }
      b(0.8, 1.8, 0.02, 0, 0.9, D / 2 + 0.01, darker(color, 0.3));
      break;
    }
    case 'carport': {
      for (const sx of [-1, 1]) for (const sz of [-1, 1]) b(0.12, H, 0.12, sx * (W / 2 - 0.06), H / 2, sz * (D / 2 - 0.06), color);
      b(W + 0.3, 0.12, D + 0.3, 0, H + 0.06, 0, darker(color, 0.15));
      break;
    }
    case 'car': {
      b(W, H * 0.42, D, 0, 0.2 + H * 0.21, 0, color, { roughness: 0.25, metalness: 0.5 });
      b(W * 0.88, H * 0.36, D * 0.48, 0, 0.2 + H * 0.42 + H * 0.17, -D * 0.04, 0x26303a, { roughness: 0.1, metalness: 0.3 });
      for (const sx of [-1, 1]) for (const sz of [-1, 1]) {
        const wh = cyl(0.33, 0.33, 0.22, sx * (W / 2 - 0.1), 0.33, sz * (D / 2 - 0.78), 0x161616, 24);
        wh.rotation.z = Math.PI / 2;
      }
      break;
    }
    default:
      b(W, H, D, 0, H / 2, 0);
  }
}

const gltfCache = new Map();
function loadModel(loader, url, g, W, D, H, color) {
  const ph = new THREE.Mesh(new THREE.BoxGeometry(W, H, D), mat(color));
  ph.position.y = H / 2;
  g.add(ph);
  let p = gltfCache.get(url);
  if (!p) {
    p = loader.loadAsync(url).then((gl) => gl.scene);
    gltfCache.set(url, p);
  }
  p.then((src) => {
    const obj = src.clone(true);
    const box = new THREE.Box3().setFromObject(obj);
    const size = box.getSize(new THREE.Vector3());
    const s = Math.min(W / (size.x || 1), H / (size.y || 1), D / (size.z || 1));
    obj.scale.setScalar(s);
    const b2 = new THREE.Box3().setFromObject(obj);
    const c = b2.getCenter(new THREE.Vector3());
    obj.position.set(-c.x, -b2.min.y, -c.z);
    obj.traverse((o) => { if (o.isMesh) { o.castShadow = true; o.receiveShadow = true; } });
    g.remove(ph);
    g.add(obj);
  }).catch((e) => console.warn('[Planstratiq3D] model nije učitan', url, e));
}

// ------------------------------------------------------------------ engine
class Engine {
  constructor() {
    const r = (this.renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true }));
    r.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    r.shadowMap.enabled = true;
    r.shadowMap.type = THREE.PCFSoftShadowMap;
    r.outputColorSpace = THREE.SRGBColorSpace;
    r.toneMapping = THREE.ACESFilmicToneMapping;
    r.toneMappingExposure = 0.95;
    Object.assign(r.domElement.style, { display: 'block', width: '100%', height: '100%', outline: 'none', touchAction: 'none' });

    const scene = (this.scene = new THREE.Scene());
    const pm = new THREE.PMREMGenerator(r);
    scene.environment = pm.fromScene(new RoomEnvironment(), 0.04).texture;
    scene.environmentIntensity = 0.45;
    scene.fog = new THREE.Fog(0xcfdbe3, 90, 320);

    this.sky = new Sky();
    this.sky.scale.setScalar(900);
    const u = this.sky.material.uniforms;
    u.turbidity.value = 3.5;
    u.rayleigh.value = 1.1;
    u.mieCoefficient.value = 0.004;
    u.mieDirectionalG.value = 0.8;
    scene.add(this.sky);

    this.camera = new THREE.PerspectiveCamera(60, 1, 0.1, 1200);
    this.camera.position.set(14, 7, 20);

    this.hemi = new THREE.HemisphereLight(0xdfeeff, 0x6b6250, 0.55);
    scene.add(this.hemi);
    const sun = (this.sun = new THREE.DirectionalLight(0xfff1dc, 2.6));
    sun.castShadow = true;
    sun.shadow.mapSize.set(2048, 2048);
    sun.shadow.bias = -0.0003;
    sun.shadow.normalBias = 0.025;
    Object.assign(sun.shadow.camera, { left: -30, right: 30, top: 30, bottom: -30, near: 1, far: 160 });
    scene.add(sun, sun.target);
    this.indoor = new THREE.PointLight(0xffe7c4, 0, 14, 1.6);
    scene.add(this.indoor);
    this.ambient = new THREE.AmbientLight(0xfff6ea, 0);
    scene.add(this.ambient);

    const ground = new THREE.Mesh(new THREE.CircleGeometry(400, 64).rotateX(-Math.PI / 2), mat(0xa9bb92, { tex: 'grass', roughness: 1 }));
    ground.position.y = -0.01;
    ground.receiveShadow = true;
    scene.add(ground);

    this.world = new THREE.Group();
    scene.add(this.world);

    this.orbit = new OrbitControls(this.camera, r.domElement);
    this.orbit.enableDamping = true;
    this.orbit.dampingFactor = 0.08;
    this.orbit.maxPolarAngle = Math.PI / 2.05;
    this.orbit.minDistance = 1.5;
    this.orbit.maxDistance = 220;
    this.orbit.screenSpacePanning = false;

    this.fpv = new PointerLockControls(this.camera, r.domElement);
    this.fpv.addEventListener('lock', () => this._updateHint());
    this.fpv.addEventListener('unlock', () => { this.keys.clear(); this._updateHint(); });

    this.mode = 'orbit';
    this.keys = new Set();
    this.colliders = [];
    this.ceilings = [];
    this.roofs = [];
    this.itemGroups = new Map();
    this.wallGroups = new Map();
    this.plan = null;
    this.framed = false;
    this.savedOrbit = null;
    this.selection = { kind: '', id: '' };
    this.selHelper = null;
    this.loader = new GLTFLoader();
    this.clock = new THREE.Clock();
    this.raycaster = new THREE.Raycaster();
    this.time = 15;
    this.touch = { move: null, look: null, vx: 0, vz: 0 };
    this.lastPose = 0;
    this.onEvent = null;
    this.setTime(this.time);

    window.addEventListener('keydown', (e) => {
      if (this.mode === 'walk' && this.fpv.isLocked) {
        this.keys.add(e.code);
        e.preventDefault();
        e.stopPropagation();
      }
    }, true);
    window.addEventListener('keyup', (e) => this.keys.delete(e.code), true);
    this._bindPointer();

    this.hint = this._div({
      position: 'absolute', left: '50%', bottom: '16px', transform: 'translateX(-50%)', padding: '8px 14px',
      borderRadius: '8px', background: 'rgba(28,34,38,.78)', color: '#fff', font: '500 12.5px Archivo, system-ui, sans-serif',
      pointerEvents: 'none', whiteSpace: 'nowrap', maxWidth: '92%', overflow: 'hidden', textOverflow: 'ellipsis',
    });
    this.cross = this._div({
      position: 'absolute', left: '50%', top: '50%', width: '6px', height: '6px', margin: '-3px 0 0 -3px', borderRadius: '50%',
      background: 'rgba(255,255,255,.95)', boxShadow: '0 0 0 1px rgba(0,0,0,.35)', pointerEvents: 'none', display: 'none',
    });
    this.stick = this._div({
      position: 'absolute', width: '96px', height: '96px', margin: '-48px 0 0 -48px', borderRadius: '50%',
      border: '2px solid rgba(255,255,255,.7)', background: 'rgba(28,34,38,.25)', pointerEvents: 'none', display: 'none',
    });
    this.knob = this._div({
      position: 'absolute', width: '40px', height: '40px', margin: '-20px 0 0 -20px', borderRadius: '50%',
      background: 'rgba(255,255,255,.85)', pointerEvents: 'none', display: 'none',
    });

    this._loop = this._loop.bind(this);
    this.running = false;
  }

  _div(style) {
    const d = document.createElement('div');
    Object.assign(d.style, style);
    return d;
  }

  emit(type, data) {
    try { if (this.onEvent) this.onEvent(type, JSON.stringify(data ?? null)); } catch (e) { console.warn(e); }
  }

  // ------------------------------------------------------------------ API
  mount(el) {
    this.container = el;
    el.style.position = 'relative';
    el.style.overflow = 'hidden';
    el.appendChild(this.renderer.domElement);
    for (const d of [this.hint, this.cross, this.stick, this.knob]) el.appendChild(d);
    this.ro?.disconnect();
    this.ro = new ResizeObserver(() => this._resize());
    this.ro.observe(el);
    this._resize();
    this._updateHint();
    if (!this.running) {
      this.running = true;
      requestAnimationFrame(this._loop);
    }
  }

  setPlan(json) {
    try { this.plan = typeof json === 'string' ? JSON.parse(json) : json; } catch (e) { console.error('[Planstratiq3D] JSON', e); return; }
    if (this.plan.projectId !== this.projectId) {
      this.projectId = this.plan.projectId;
      this.framed = false;
    }
    this._rebuild();
    if (!this.framed && (this.plan.walls?.length || this.plan.items?.length)) {
      this.framed = true;
      this.frame();
    }
  }

  setSelection(kind, id) {
    this.selection = { kind: kind || '', id: id || '' };
    this._updateSelectionHelper();
  }

  setOptions(json) {
    const o = typeof json === 'string' ? JSON.parse(json) : json;
    if (o.time != null) this.setTime(o.time);
  }

  setMode(mode) {
    if (mode === this.mode) return;
    if (mode === 'walk') {
      this.savedOrbit = { pos: this.camera.position.clone(), target: this.orbit.target.clone() };
      this.orbit.enabled = false;
      this.mode = 'walk';
      this._spawn();
    } else {
      if (this.fpv.isLocked) this.fpv.unlock();
      this.mode = 'orbit';
      this.orbit.enabled = true;
      if (this.savedOrbit) {
        this.camera.position.copy(this.savedOrbit.pos);
        this.orbit.target.copy(this.savedOrbit.target);
      }
      this.camera.up.set(0, 1, 0);
      this.camera.lookAt(this.orbit.target);
      this.emit('pose', null);
    }
    this.camera.fov = mode === 'walk' ? 72 : 60;
    this.camera.updateProjectionMatrix();
    this._applyVisibility();
    this._updateHint();
    this._updateSelectionHelper();
  }

  walkTo(x, y) {
    if (this.mode !== 'walk') this.setMode('walk');
    this._placeViewer(x, y);
    this._emitPose(true);
  }

  // udaljenost do najbližeg zida u smjeru (dx, dz)
  _rayDist(x, z, dx, dz, max = 15) {
    for (let d = 0.1; d < max; d += 0.1) if (this._blocked(x + dx * d, z + dz * d)) return d;
    return max;
  }

  // postavi promatrača: okreni ga prema najduljem slobodnom pogledu i odmakni unatrag
  _placeViewer(x, z) {
    let best = { d: -1, dx: 0, dz: -1 };
    for (let i = 0; i < 16; i++) {
      const a = (i / 16) * Math.PI * 2;
      const dx = Math.sin(a), dz = -Math.cos(a);
      const d = this._rayDist(x, z, dx, dz);
      if (d > best.d) best = { d, dx, dz };
    }
    const back = Math.min(1.6, Math.max(0, this._rayDist(x, z, -best.dx, -best.dz) - 0.5));
    x -= best.dx * back;
    z -= best.dz * back;
    this.camera.position.set(x, EYE, z);
    this.camera.up.set(0, 1, 0);
    this.camera.quaternion.setFromEuler(new THREE.Euler(-0.08, Math.atan2(-best.dx, -best.dz), 0, 'YXZ'));
  }

  frame() {
    const b = this._bounds();
    const size = Math.max(b.max.x - b.min.x, b.max.z - b.min.z, 6);
    const c = new THREE.Vector3((b.min.x + b.max.x) / 2, 0, (b.min.z + b.max.z) / 2);
    this.orbit.target.copy(c);
    const k = (0.62 / Math.tan(THREE.MathUtils.degToRad(this.camera.fov / 2))) * Math.pow(Math.max(1, 1.2 / Math.max(this.camera.aspect, 0.3)), 0.6);
    this.camera.position.set(c.x + size * 0.42 * k, size * 0.62 * k, c.z + size * 0.72 * k);
    this.camera.lookAt(c);
    this.center = c;
    this.extent = size;
    this.setTime(this.time);
  }

  setTime(h) {
    this.time = h;
    const t = clamp((h - 6) / 14, 0, 1);
    const elev = THREE.MathUtils.degToRad(Math.max(3, 62 * Math.sin(Math.PI * t)));
    const az = Math.PI * t;
    const dir = new THREE.Vector3(Math.cos(elev) * Math.cos(az), Math.sin(elev), Math.cos(elev) * Math.sin(az));
    this.sky.material.uniforms.sunPosition.value.copy(dir);
    const c = this.center || new THREE.Vector3();
    this.sun.position.copy(c).addScaledVector(dir, 60);
    this.sun.target.position.copy(c);
    const warm = new THREE.Color(0xffb27a), white = new THREE.Color(0xfff4e6);
    const k = clamp(Math.sin(elev) / Math.sin(THREE.MathUtils.degToRad(35)), 0, 1);
    this.sun.color.copy(warm).lerp(white, k);
    this.sun.intensity = 0.8 + 2.2 * k;
    this.hemi.intensity = 0.25 + 0.35 * k;
    const half = Math.max(20, (this.extent || 20) * 0.9);
    const sc = this.sun.shadow.camera;
    Object.assign(sc, { left: -half, right: half, top: half, bottom: -half });
    sc.updateProjectionMatrix();
    this.renderer.toneMappingExposure = 0.75 + 0.25 * k;
  }

  screenshot() {
    this.renderer.render(this.scene, this.camera);
    return this.renderer.domElement.toDataURL('image/png');
  }

  groundPoint(x, y) {
    const el = this.renderer.domElement;
    const w = el.clientWidth, h = el.clientHeight;
    if (!w || !h) return null;
    const ndc = new THREE.Vector2((x / w) * 2 - 1, -(y / h) * 2 + 1);
    this.raycaster.setFromCamera(ndc, this.camera);
    const p = new THREE.Vector3();
    if (!this.raycaster.ray.intersectPlane(new THREE.Plane(new THREE.Vector3(0, 1, 0), 0), p)) return null;
    return JSON.stringify([p.x, p.z]);
  }

  thumbnail(json) {
    const it = typeof json === 'string' ? JSON.parse(json) : json;
    if (!this.thumb) {
      const tr = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: true });
      tr.setSize(160, 160, false);
      tr.setPixelRatio(1);
      tr.outputColorSpace = THREE.SRGBColorSpace;
      tr.toneMapping = THREE.ACESFilmicToneMapping;
      tr.toneMappingExposure = 1.05;
      const sc = new THREE.Scene();
      const pm = new THREE.PMREMGenerator(tr);
      sc.environment = pm.fromScene(new RoomEnvironment(), 0.04).texture;
      sc.environmentIntensity = 0.7;
      sc.add(new THREE.HemisphereLight(0xffffff, 0x8a8a80, 0.9));
      const l = new THREE.DirectionalLight(0xffffff, 1.6);
      l.position.set(3, 6, 4);
      sc.add(l);
      const cam = new THREE.PerspectiveCamera(30, 1, 0.01, 200);
      this.thumb = { tr, sc, cam };
    }
    const { tr, sc, cam } = this.thumb;
    const g = new THREE.Group();
    buildItem({ ...it, modelUrl: null }, g, null);
    sc.add(g);
    const box = new THREE.Box3().setFromObject(g);
    const size = box.getSize(new THREE.Vector3());
    const ctr = box.getCenter(new THREE.Vector3());
    const r = Math.max(size.length() / 2, 0.1);
    const dir = new THREE.Vector3(0.75, 0.62, 1).normalize();
    const dist = (r / Math.sin(THREE.MathUtils.degToRad(15))) * 0.98;
    cam.position.copy(ctr).addScaledVector(dir, dist);
    cam.near = dist / 50;
    cam.far = dist * 4;
    cam.updateProjectionMatrix();
    cam.lookAt(ctr);
    tr.render(sc, cam);
    const url = tr.domElement.toDataURL('image/png');
    sc.remove(g);
    g.traverse((o) => o.geometry?.dispose());
    return url;
  }

  // ------------------------------------------------------------------ izgradnja scene
  _resize() {
    const el = this.container;
    if (!el) return;
    const w = el.clientWidth, h = el.clientHeight;
    if (!w || !h) return;
    this.renderer.setSize(w, h, false);
    this.camera.aspect = w / h;
    this.camera.updateProjectionMatrix();
  }

  _updateHint() {
    const touch = matchMedia('(pointer: coarse)').matches;
    let text = '';
    if (this.mode === 'orbit') {
      text = touch
        ? 'Jedan prst okreće pogled, dva prsta pomiču i zumiraju. Dodirni objekt za odabir.'
        : 'Povuci za okretanje, desni klik za pomak, kotačić za zoom. Klikni objekt za odabir, pa ga povuci.';
    } else if (touch) {
      text = this.touch.move || this.touch.look ? '' : 'Lijevi palac za hodanje, desni za gledanje okolo.';
    } else if (!this.fpv.isLocked) {
      text = 'Klikni u prikaz za šetnju. W A S D za hodanje, Shift za trčanje, Esc za izlaz.';
    }
    this.hint.textContent = text;
    this.hint.style.display = text ? 'block' : 'none';
    this.cross.style.display = this.mode === 'walk' && this.fpv.isLocked ? 'block' : 'none';
  }

  _bounds() {
    const p = this.plan || {};
    const b = new THREE.Box3();
    let any = false;
    const add = (x, z) => {
      if (!any) { b.min.set(x, 0, z); b.max.set(x, 0, z); any = true; } else b.expandByPoint(new THREE.Vector3(x, 0, z));
    };
    for (const n of Object.values(p.nodes || {})) add(n.x, n.y);
    for (const it of p.items || []) {
      const r = Math.max(it.w, it.d) / 2;
      add(it.x - r, it.y - r);
      add(it.x + r, it.y + r);
    }
    if (!any) { b.min.set(-5, 0, -5); b.max.set(5, 0, 5); }
    return b;
  }

  _clearWorld() {
    this.world.traverse((o) => { if (o.geometry) o.geometry.dispose(); });
    this.world.clear();
    this.colliders = [];
    this.ceilings = [];
    this.roofs = [];
    this.itemGroups.clear();
    this.wallGroups.clear();
    this.selHelper = null;
  }

  _rebuild() {
    this._clearWorld();
    const p = this.plan;
    if (!p) return;
    const nodes = p.nodes || {};
    const degree = {};
    for (const w of p.walls || []) {
      degree[w.a] = (degree[w.a] || 0) + 1;
      degree[w.b] = (degree[w.b] || 0) + 1;
    }
    let maxH = p.wallHeight || 2.6;
    for (const w of p.walls || []) {
      maxH = Math.max(maxH, w.height || 2.6);
      this._buildWall(w, nodes, degree, (p.openings || []).filter((o) => o.wallId === w.id));
    }
    this._buildFloors(p, nodes, maxH);
    if (p.roof) this._buildRoofs(p, maxH);
    for (const it of p.items || []) {
      const g = new THREE.Group();
      g.position.set(it.x, 0, it.y);
      g.rotation.y = -(it.rotation || 0);
      g.userData = { kind: 'item', id: it.id, data: it };
      buildItem(it, g, this.loader);
      this.world.add(g);
      this.itemGroups.set(it.id, g);
    }
    this._applyVisibility();
    this._updateSelectionHelper();
  }

  _applyVisibility() {
    for (const c of this.ceilings) c.visible = this.mode === 'walk';
  }

  _buildWall(w, nodes, degree, openings) {
    const A = nodes[w.a], B = nodes[w.b];
    if (!A || !B) return;
    const dx = B.x - A.x, dz = B.y - A.y;
    const L = Math.hypot(dx, dz);
    if (L < 0.01) return;
    const ang = Math.atan2(dz, dx);
    const T = w.thickness || 0.2, H = w.height || 2.6;
    const ea = degree[w.a] > 1 ? T / 2 : 0;
    const eb = degree[w.b] > 1 ? T / 2 : 0;
    const g = new THREE.Group();
    g.position.set(A.x, 0, A.y);
    g.rotation.y = -ang;
    g.userData = { kind: 'wall', id: w.id, L, H, T, ea, eb };

    // strana interijera: +1 (lokalni +z), -1 (lokalni -z), 0 (unutarnji zid)
    const side = w.inside || 0;
    const paint = mat(w.color, { roughness: 0.92 });
    const facade = mat(0xece7df, { tex: 'plaster', roughness: 0.95 });
    const top = mat(0xd9d6d0, { roughness: 1 });
    const faces = [paint, paint, top, paint, side === -1 ? facade : paint, side === 1 ? facade : paint];

    const box = (x0, x1, y0, y1, material = faces, depth = T, z = 0) => {
      if (x1 - x0 < 0.002 || y1 - y0 < 0.002) return null;
      const m = new THREE.Mesh(new THREE.BoxGeometry(x1 - x0, y1 - y0, depth), material);
      m.position.set((x0 + x1) / 2, (y0 + y1) / 2, z);
      m.castShadow = true;
      m.receiveShadow = true;
      g.add(m);
      return m;
    };
    const ops = openings.map((o) => ({ ...o, s: o.t * L - o.width / 2, e: o.t * L + o.width / 2 })).sort((a, b) => a.s - b.s);
    const solids = [];
    let cur = -ea;
    let solidStart = -ea;
    const frameMat = mat(0xf7f7f5, { roughness: 0.5 });
    for (const o of ops) {
      const s = Math.max(o.s, cur), e = Math.min(o.e, L + eb);
      if (e <= s) continue;
      box(cur, s, 0, H);
      const topY = Math.min(o.sill + o.height, H);
      box(s, e, topY, H);
      if (o.sill > 0) box(s, e, 0, o.sill);
      const W = e - s;
      if (o.type === 'window' || o.type === 'balcony') {
        box(s, e, o.sill, topY, mat(0, { glass: true }), 0.02);
        if (o.sill > 0) box(s, e, o.sill - 0.04, o.sill, frameMat, T + 0.05);
        box(s, s + 0.06, o.sill, topY, frameMat, 0.08);
        box(e - 0.06, e, o.sill, topY, frameMat, 0.08);
        box(s, e, topY - 0.06, topY, frameMat, 0.08);
        const mullions = o.type === 'balcony' ? 1 : Math.max(0, Math.round(W / 0.9) - 1);
        for (let i = 1; i <= mullions; i++) {
          const x = s + (i * W) / (mullions + 1);
          box(x - 0.03, x + 0.03, o.sill, topY, frameMat, 0.07);
        }
        if (o.type === 'balcony' && o.sill < 0.3) { solids.push([solidStart, s]); solidStart = e; }
      } else {
        box(s, s + 0.04, 0, topY, frameMat, T + 0.02);
        box(e - 0.04, e, 0, topY, frameMat, T + 0.02);
        box(s, e, topY - 0.04, topY, frameMat, T + 0.02);
        if (o.type === 'door') {
          let sideN = side === 0 ? 1 : side;
          if (o.swingOut) sideN = -sideN;
          const hingeAtE = !!o.flip;
          const pivot = new THREE.Group();
          const leafW = Math.max(0.2, W - 0.09);
          pivot.position.set(hingeAtE ? e - 0.045 : s + 0.045, 0, sideN * (T / 2));
          pivot.rotation.y = hingeAtE ? sideN * 1.4 : -sideN * 1.4;
          const leaf = new THREE.Mesh(new THREE.BoxGeometry(leafW, topY - 0.05, 0.04), mat(0xece6dc, { roughness: 0.55 }));
          leaf.position.set(hingeAtE ? -leafW / 2 : leafW / 2, (topY - 0.05) / 2, sideN * 0.02);
          leaf.castShadow = true;
          pivot.add(leaf);
          const handle = new THREE.Mesh(new THREE.BoxGeometry(0.12, 0.02, 0.02), mat(0x8a8a8a, { metalness: 0.7, roughness: 0.3 }));
          handle.position.set(hingeAtE ? -leafW + 0.08 : leafW - 0.08, 1.02, sideN * 0.06);
          pivot.add(handle);
          g.add(pivot);
        }
        if (o.sill < 0.3) { solids.push([solidStart, s]); solidStart = e; }
      }
      cur = Math.max(cur, e);
    }
    box(cur, L + eb, 0, H);
    solids.push([solidStart, L + eb]);
    this.world.add(g);
    this.wallGroups.set(w.id, g);
    const ux = dx / L, uz = dz / L;
    for (const [s0, s1] of solids) {
      if (s1 - s0 < 0.01) continue;
      this.colliders.push({ ax: A.x + ux * s0, az: A.y + uz * s0, bx: A.x + ux * s1, bz: A.y + uz * s1, r: T / 2 });
    }
  }

  _shapeFrom(points) {
    const shape = new THREE.Shape();
    points.forEach((pt, i) => (i ? shape.lineTo(pt.x, -pt.y) : shape.moveTo(pt.x, -pt.y)));
    shape.closePath();
    return shape;
  }

  _buildFloors(p, nodes, maxH) {
    if (!this.slabMat) {
      this.slabMat = mat(0xbab5ad, { tex: 'concrete', double: true }).clone();
      this.slabMat.polygonOffset = true;
      this.slabMat.polygonOffsetFactor = 2;
      this.slabMat.polygonOffsetUnits = 2;
    }
    const slabMat = this.slabMat;
    const mk = (pts, material, y, opts = {}) => {
      const geo = new THREE.ShapeGeometry(this._shapeFrom(pts)).rotateX(-Math.PI / 2);
      const m = new THREE.Mesh(geo, material);
      m.position.y = y;
      m.receiveShadow = true;
      if (opts.ceiling) this.ceilings.push(m);
      if (opts.userData) m.userData = opts.userData;
      this.world.add(m);
      return m;
    };
    for (const o of p.outlines || []) {
      if (o.length >= 3) mk(o.map(([x, y]) => ({ x, y })), slabMat, 0.004);
    }
    for (const r of p.rooms || []) {
      const pts = (r.nodeIds || []).map((id) => nodes[id]).filter(Boolean);
      if (pts.length < 3) continue;
      mk(pts, mat(r.floorColor, { tex: r.floorTexture, roughness: r.floorTexture === 'wood' ? 0.82 : 0.86, env: 0.3, double: true }), 0.03,
        { userData: { kind: 'room', id: r.id } });
      mk(pts, mat(0xfbfaf8, { double: true, roughness: 1 }), maxH, { ceiling: true });
    }
  }

  _buildRoofs(p, maxH) {
    for (const o of p.outlines || []) {
      if (o.length < 3) continue;
      let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
      for (const [x, y] of o) { minX = Math.min(minX, x); maxX = Math.max(maxX, x); minZ = Math.min(minZ, y); maxZ = Math.max(maxZ, y); }
      const wallT = 0.15;
      minX -= wallT; maxX += wallT; minZ -= wallT; maxZ += wallT;
      const ov = 0.5;
      const w = maxX - minX, d = maxZ - minZ;
      const alongX = w >= d;
      const span = (alongX ? d : w) + 2 * ov;
      const len = (alongX ? w : d) + 2 * ov;
      const half = span / 2;
      const rise = half * Math.tan(THREE.MathUtils.degToRad(28));
      const slope = Math.hypot(half, rise);
      const g = new THREE.Group();
      g.position.set((minX + maxX) / 2, maxH, (minZ + maxZ) / 2);
      if (!alongX) g.rotation.y = Math.PI / 2;
      const roofMat = mat(0xa5533a, { tex: 'roof', roughness: 0.85, double: true });
      for (const sgn of [-1, 1]) {
        const geo = new THREE.BoxGeometry(len, 0.08, slope);
        const uv = geo.attributes.uv;
        for (let i = 0; i < uv.count; i++) uv.setXY(i, uv.getX(i) * len, uv.getY(i) * slope);
        const plane = new THREE.Mesh(geo, roofMat);
        plane.position.set(0, rise / 2, (sgn * half) / 2);
        plane.rotation.x = sgn * Math.atan2(rise, half);
        plane.castShadow = true;
        plane.receiveShadow = true;
        g.add(plane);
      }
      const inner = half - ov;
      const innerRise = rise * (inner / half);
      const tri = new THREE.Shape();
      tri.moveTo(-inner, 0);
      tri.lineTo(inner, 0);
      tri.lineTo(0, innerRise);
      tri.closePath();
      const gable = new THREE.ExtrudeGeometry(tri, { depth: 0.2, bevelEnabled: false });
      for (const sgn of [-1, 1]) {
        const m = new THREE.Mesh(gable, mat(0xece7df, { tex: 'plaster' }));
        m.rotation.y = Math.PI / 2;
        m.position.set(sgn * (len / 2 - ov) - (sgn > 0 ? 0.2 : 0), 0, 0);
        m.castShadow = true;
        g.add(m);
      }
      this.world.add(g);
      this.roofs.push(g);
    }
  }

  _updateSelectionHelper() {
    if (this.selHelper) {
      this.selHelper.parent?.remove(this.selHelper);
      this.selHelper.geometry.dispose();
      this.selHelper = null;
    }
    if (this.mode === 'walk') return;
    const { kind, id } = this.selection;
    let parent = null, geo = null, y = 0, x = 0;
    if (kind === 'item' && this.itemGroups.has(id)) {
      parent = this.itemGroups.get(id);
      const it = parent.userData.data;
      geo = new THREE.BoxGeometry(it.w + 0.04, Math.max(it.h, 0.02) + 0.04, it.d + 0.04);
      y = Math.max(it.h, 0.02) / 2;
    } else if (kind === 'wall' && this.wallGroups.has(id)) {
      parent = this.wallGroups.get(id);
      const u = parent.userData;
      geo = new THREE.BoxGeometry(u.L + u.ea + u.eb + 0.03, u.H + 0.03, u.T + 0.03);
      x = (u.L + u.eb - u.ea) / 2;
      y = u.H / 2;
    }
    if (!parent) return;
    const h = new THREE.LineSegments(new THREE.EdgesGeometry(geo), new THREE.LineBasicMaterial({ color: ACCENT, depthTest: false, transparent: true, opacity: 0.95 }));
    h.renderOrder = 999;
    h.position.set(x, y, 0);
    geo.dispose();
    parent.add(h);
    this.selHelper = h;
  }

  // ------------------------------------------------------------------ odabir i povlačenje
  _ndc(e) {
    const r = this.renderer.domElement.getBoundingClientRect();
    return new THREE.Vector2(((e.clientX - r.left) / r.width) * 2 - 1, -((e.clientY - r.top) / r.height) * 2 + 1);
  }

  _pick(e) {
    this.raycaster.setFromCamera(this._ndc(e), this.camera);
    const hits = this.raycaster.intersectObjects(this.world.children, true);
    for (const h of hits) {
      if (!h.object.visible) continue;
      let o = h.object;
      while (o && !o.userData?.kind) o = o.parent;
      if (o && o.userData.kind) return { kind: o.userData.kind, id: o.userData.id, obj: o, point: h.point };
    }
    return null;
  }

  _groundAt(e) {
    this.raycaster.setFromCamera(this._ndc(e), this.camera);
    const p = new THREE.Vector3();
    return this.raycaster.ray.intersectPlane(new THREE.Plane(new THREE.Vector3(0, 1, 0), 0), p) ? p : null;
  }

  _bindPointer() {
    const el = this.renderer.domElement;
    el.addEventListener('pointerdown', (e) => {
      if (this.mode === 'walk') {
        if (e.pointerType === 'touch') { this._touchStart(e); return; }
        if (!this.fpv.isLocked) this.fpv.lock();
        return;
      }
      if (e.button !== 0) return;
      this.down = { x: e.clientX, y: e.clientY };
      const hit = this._pick(e);
      this.down.hit = hit;
      if (hit && hit.kind === 'item' && this.selection.kind === 'item' && this.selection.id === hit.id) {
        const g0 = this._groundAt(e);
        if (g0) {
          this.orbit.enabled = false;
          this.dragItem = { g: hit.obj, start: hit.obj.position.clone(), g0, id: hit.id, pid: e.pointerId };
          el.setPointerCapture(e.pointerId);
        }
      }
    }, { capture: true });
    el.addEventListener('pointermove', (e) => {
      if (this.mode === 'walk') { if (e.pointerType === 'touch') this._touchMove(e); return; }
      const d = this.dragItem;
      if (!d) return;
      const p = this._groundAt(e);
      if (!p) return;
      const nx = Math.round((d.start.x + p.x - d.g0.x) * 100) / 100;
      const nz = Math.round((d.start.z + p.z - d.g0.z) * 100) / 100;
      d.g.position.set(nx, 0, nz);
      d.moved = true;
    });
    const up = (e) => {
      if (this.mode === 'walk') { if (e.pointerType === 'touch') this._touchEnd(e); return; }
      const d = this.dragItem;
      if (d) {
        this.dragItem = null;
        this.orbit.enabled = true;
        try { el.releasePointerCapture(d.pid); } catch (_) { /* ignore */ }
        if (d.moved) {
          this.down = null;
          this.emit('move', { id: d.id, x: d.g.position.x, y: d.g.position.z });
          return;
        }
      }
      const dn = this.down;
      this.down = null;
      if (!dn) return;
      if (Math.hypot(e.clientX - dn.x, e.clientY - dn.y) > 5) return;
      const hit = dn.hit;
      if (hit && (hit.kind === 'item' || hit.kind === 'wall' || hit.kind === 'room')) this.emit('select', { kind: hit.kind, id: hit.id });
      else this.emit('select', { kind: '', id: '' });
    };
    el.addEventListener('pointerup', up);
    el.addEventListener('pointercancel', up);
    el.addEventListener('contextmenu', (e) => e.preventDefault());
  }

  _touchStart(e) {
    const r = this.renderer.domElement.getBoundingClientRect();
    const x = e.clientX - r.left, y = e.clientY - r.top;
    if (x < r.width / 2 && !this.touch.move) {
      this.touch.move = { id: e.pointerId, x, y };
      Object.assign(this.stick.style, { left: x + 'px', top: y + 'px', display: 'block' });
      Object.assign(this.knob.style, { left: x + 'px', top: y + 'px', display: 'block' });
    } else if (!this.touch.look) {
      this.touch.look = { id: e.pointerId, x, y };
    }
    try { this.renderer.domElement.setPointerCapture(e.pointerId); } catch (_) { /* ignore */ }
    this._updateHint();
  }

  _touchMove(e) {
    const r = this.renderer.domElement.getBoundingClientRect();
    const x = e.clientX - r.left, y = e.clientY - r.top;
    const t = this.touch;
    if (t.move && t.move.id === e.pointerId) {
      let dx = x - t.move.x, dy = y - t.move.y;
      const len = Math.hypot(dx, dy);
      if (len > 44) { dx = (dx / len) * 44; dy = (dy / len) * 44; }
      t.vx = dx / 44;
      t.vz = dy / 44;
      Object.assign(this.knob.style, { left: t.move.x + dx + 'px', top: t.move.y + dy + 'px' });
    } else if (t.look && t.look.id === e.pointerId) {
      const dx = x - t.look.x, dy = y - t.look.y;
      t.look.x = x;
      t.look.y = y;
      const eu = new THREE.Euler(0, 0, 0, 'YXZ').setFromQuaternion(this.camera.quaternion);
      eu.y -= dx * 0.005;
      eu.x = clamp(eu.x - dy * 0.005, -1.3, 1.3);
      this.camera.quaternion.setFromEuler(eu);
    }
  }

  _touchEnd(e) {
    const t = this.touch;
    if (t.move && t.move.id === e.pointerId) {
      t.move = null;
      t.vx = t.vz = 0;
      this.stick.style.display = this.knob.style.display = 'none';
    }
    if (t.look && t.look.id === e.pointerId) t.look = null;
    this._updateHint();
  }

  // ------------------------------------------------------------------ šetnja
  _spawn() {
    const p = this.plan || {};
    const rooms = (p.rooms || []).slice().sort((a, b) => (b.area || 0) - (a.area || 0));
    let x, z;
    if (rooms.length) {
      x = rooms[0].cx;
      z = rooms[0].cy;
    } else {
      const b = this._bounds();
      x = (b.min.x + b.max.x) / 2;
      z = (b.min.z + b.max.z) / 2;
    }
    this._placeViewer(x, z);
    this._emitPose(true);
  }

  _blocked(x, z) {
    for (const c of this.colliders) {
      const abx = c.bx - c.ax, abz = c.bz - c.az;
      const l2 = abx * abx + abz * abz;
      let t = l2 ? ((x - c.ax) * abx + (z - c.az) * abz) / l2 : 0;
      t = clamp(t, 0, 1);
      const px = c.ax + abx * t - x, pz = c.az + abz * t - z;
      if (px * px + pz * pz < (c.r + RADIUS) ** 2) return true;
    }
    return false;
  }

  _walk(dt) {
    const k = this.keys;
    let f = 0, s = 0;
    if (k.has('KeyW') || k.has('ArrowUp')) f += 1;
    if (k.has('KeyS') || k.has('ArrowDown')) f -= 1;
    if (k.has('KeyD') || k.has('ArrowRight')) s += 1;
    if (k.has('KeyA') || k.has('ArrowLeft')) s -= 1;
    f -= this.touch.vz;
    s += this.touch.vx;
    if (Math.abs(f) < 0.05 && Math.abs(s) < 0.05) return false;
    const len = Math.max(1, Math.hypot(f, s));
    f /= len;
    s /= len;
    const speed = k.has('ShiftLeft') || k.has('ShiftRight') ? RUN : WALK;
    const dir = new THREE.Vector3();
    this.camera.getWorldDirection(dir);
    dir.y = 0;
    dir.normalize();
    const rx = -dir.z, rz = dir.x;
    const mx = (dir.x * f + rx * s) * speed * dt;
    const mz = (dir.z * f + rz * s) * speed * dt;
    const p = this.camera.position;
    const stuck = this._blocked(p.x, p.z);
    if (stuck || !this._blocked(p.x + mx, p.z)) p.x += mx;
    if (stuck || !this._blocked(p.x, p.z + mz)) p.z += mz;
    p.y = EYE;
    return true;
  }

  _emitPose(force) {
    const now = performance.now();
    if (!force && now - this.lastPose < 90) return;
    this.lastPose = now;
    const dir = new THREE.Vector3();
    this.camera.getWorldDirection(dir);
    this.emit('pose', { x: this.camera.position.x, y: this.camera.position.z, yaw: Math.atan2(dir.x, -dir.z) });
    this.indoor.position.set(this.camera.position.x, 2.2, this.camera.position.z);
  }

  _loop() {
    requestAnimationFrame(this._loop);
    const dt = Math.min(this.clock.getDelta(), 0.05);
    if (this.mode === 'walk') {
      const active = this.fpv.isLocked || this.touch.move || this.touch.look;
      if (this.fpv.isLocked || this.touch.move) this._walk(dt);
      if (active) this._emitPose(false);
      this.indoor.intensity = 2.2;
      this.ambient.intensity = 0.55;
    } else {
      this.orbit.update();
      this.indoor.intensity = 0;
      this.ambient.intensity = 0;
    }
    if (this.container && this.container.isConnected) this.renderer.render(this.scene, this.camera);
  }
}

const engine = new Engine();
const prev = window.Planstratiq3D || {};
const api = {
  ready: true,
  mount: (el) => engine.mount(el),
  setPlan: (json) => engine.setPlan(json),
  setMode: (mode) => engine.setMode(mode),
  setSelection: (kind, id) => engine.setSelection(kind, id),
  setOptions: (json) => engine.setOptions(json),
  frame: () => engine.frame(),
  walkTo: (x, y) => engine.walkTo(x, y),
  screenshot: () => engine.screenshot(),
  thumbnail: (json) => engine.thumbnail(json),
  groundPoint: (x, y) => engine.groundPoint(x, y),
};
Object.defineProperty(api, 'onEvent', {
  get: () => engine.onEvent,
  set: (f) => { engine.onEvent = f; },
});
if (prev.onEvent) engine.onEvent = prev.onEvent;
window.Planstratiq3D = api;
for (const [fn, args] of prev._q || []) if (api[fn]) api[fn](...args);
