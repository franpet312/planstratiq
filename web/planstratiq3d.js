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
const FLOOR = 0.03; // visina gotovog poda iznad ploče
let lampBudget = 12; // najviše toliko stvarnih svjetala u lampama (zbog brzine)

const rgb = (c) => Number(c) & 0xffffff;
const norm2 = (x, y) => { const l = Math.hypot(x, y) || 1; return { x: x / l, y: y / l }; };
// Sutherland–Hodgman: zadrži dio poligona gdje je f(u, v) ≤ 0
function clipPoly(pts, f) {
  const out = [];
  for (let i = 0; i < pts.length; i++) {
    const a = pts[i], b = pts[(i + 1) % pts.length];
    const fa = f(a[0], a[1]), fb = f(b[0], b[1]);
    if (fa <= 0) out.push(a);
    if ((fa < 0 && fb > 0) || (fa > 0 && fb < 0)) {
      const k = fa / (fa - fb);
      out.push([a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k]);
    }
  }
  return out;
}
const STAIRS = new Set(['stairs', 'stairs_l', 'stairs_spiral']);
// L-stubište: širina kraka (lokalno: prvi krak uz desni rub od naprijed prema natrag, podest straga desno, drugi krak ulijevo)
function stairL(W, D) {
  const fw = clamp(Math.min(W, D) * 0.45, 0.7, Math.max(0.7, Math.min(W, D) - 0.3));
  const L1 = Math.max(0.3, D - fw), L2 = Math.max(0.3, W - fw);
  return { fw, L1, L2, r1: L1 / (L1 + L2) };
}
const SPIRAL_SWEEP = Math.PI * 1.5;
// napredak uz stubište 0 (dno) … 1 (vrh) za lokalnu točku, ili null ako točka nije na stubama
function stairProgress(it, lx, lz, upper) {
  const W = it.w, D = it.d;
  if (Math.abs(lx) > W / 2 || Math.abs(lz) > D / 2) return null;
  if (it.shape === 'stairs_l') {
    const g = stairL(W, D);
    if (lx >= W / 2 - g.fw) {
      if (lz > -D / 2 + g.fw) return (g.r1 * (D / 2 - lz)) / g.L1;
      return g.r1; // podest
    }
    if (lz <= -D / 2 + g.fw) return g.r1 + ((1 - g.r1) * (W / 2 - g.fw - lx)) / g.L2;
    return null;
  }
  if (it.shape === 'stairs_spiral') {
    const R = Math.min(W, D) / 2;
    if (Math.hypot(lx, lz) > R) return null;
    let a = Math.atan2(lx, lz);
    if (a < 0) a += Math.PI * 2;
    if (a > SPIRAL_SWEEP) return upper ? 1 : 0;
    return a / SPIRAL_SWEEP;
  }
  return (D / 2 - lz) / D;
}
// rasvjeta: stropna (visi sa stropa), zidna, stolna (stoji na stolu/komodi)
const CEILING = new Set(['chandelier', 'chandelier_ring', 'pendant', 'pendant_row', 'ceiling_light', 'light_point']);
const ELECTRIC = new Set(['socket', 'socket_double', 'socket_high', 'switch', 'tv_socket', 'lan_socket']);
const SURFACES = new Set(['table', 'table_round', 'dresser', 'tv_stand', 'kitchen', 'island', 'vanity', 'shelf', 'bench']);
const BALCONY = new Set(['balcony', 'balcony_rail', 'balcony_wall']);
function inPolygon(x, y, poly) {
  let c = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const a = poly[i], b = poly[j];
    if ((a.y > y) !== (b.y > y) && x < ((b.x - a.x) * (y - a.y)) / (b.y - a.y) + a.x) c = !c;
  }
  return c;
}
// točka (x, y) tlocrta u lokalnim koordinatama objekta (x širina, z dubina)
function toLocal(it, x, y) {
  const r = it.rotation || 0, dx = x - it.x, dz = y - it.y;
  return { x: dx * Math.cos(r) + dz * Math.sin(r), z: -dx * Math.sin(r) + dz * Math.cos(r) };
}
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
// UV kvadra u metrima (teksture zidova se ne rastežu; x0/y0 poravnavaju fuge među komadima zida)
function scaleBoxUV(geo, w, h, d, x0 = 0, y0 = 0) {
  const uv = geo.attributes.uv;
  const dims = [[d, h, 0, y0], [d, h, 0, y0], [w, d, x0, 0], [w, d, x0, 0], [w, h, x0, y0], [w, h, -x0 - w, y0]];
  for (let f = 0; f < 6; f++) {
    const [su, sv, ou, ov] = dims[f];
    for (let i = f * 4; i < f * 4 + 4; i++) uv.setXY(i, uv.getX(i) * su + ou, uv.getY(i) * sv + ov);
  }
  uv.needsUpdate = true;
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
  // zidne obloge (UV na zidovima je u metrima)
  wallTile: () => canvasTex('wallTile', 256, (g, n) => {
    const r = rnd(41), k = 4;
    for (let i = 0; i < k; i++) for (let j = 0; j < k; j++) {
      const v = Math.floor(236 + r() * 16);
      g.fillStyle = `rgb(${v},${v},${v})`;
      g.fillRect((i * n) / k, (j * n) / k, n / k, n / k);
    }
    g.fillStyle = 'rgba(150,150,150,0.7)';
    for (let i = 0; i <= k; i++) { g.fillRect((i * n) / k - 1.5, 0, 3, n); g.fillRect(0, (i * n) / k - 1.5, n, 3); }
  }, 0.8),
  wallTileL: () => canvasTex('wallTileL', 256, (g, n) => {
    const r = rnd(43);
    for (let j = 0; j < 4; j++) for (let i = 0; i < 2; i++) {
      const v = Math.floor(225 + r() * 22);
      g.fillStyle = `rgb(${v},${v},${v})`;
      const off = j % 2 ? n / 4 : 0;
      g.fillRect(((i * n) / 2 + off) % n, (j * n) / 4, n / 2, n / 4);
      if (off) g.fillRect(-n / 4, (j * n) / 4, n / 2, n / 4);
    }
    noise(g, n, 1500, 0.08, r);
    g.fillStyle = 'rgba(120,120,120,0.6)';
    for (let j = 0; j <= 4; j++) g.fillRect(0, (j * n) / 4 - 1, n, 2);
    for (let j = 0; j < 4; j++) for (let i = 0; i <= 2; i++) g.fillRect(((i * n) / 2 + (j % 2 ? n / 4 : 0)) % (n + 1) - 1, (j * n) / 4, 2, n / 4);
  }, 1.2),
  metroTile: () => canvasTex('metroTile', 256, (g, n) => {
    const r = rnd(47), rows = 8, cols = 4;
    for (let j = 0; j < rows; j++) for (let i = -1; i < cols; i++) {
      const x = (i * n) / cols + (j % 2 ? n / cols / 2 : 0), y = (j * n) / rows;
      const v = Math.floor(238 + r() * 14);
      g.fillStyle = 'rgb(150,150,150)';
      g.fillRect(x, y, n / cols, n / rows);
      const grd = g.createLinearGradient(0, y, 0, y + n / rows);
      grd.addColorStop(0, `rgb(${v + 3},${v + 3},${v + 3})`);
      grd.addColorStop(1, `rgb(${v - 14},${v - 14},${v - 14})`);
      g.fillStyle = grd;
      g.fillRect(x + 1.5, y + 1.5, n / cols - 3, n / rows - 3);
    }
  }, 0.6),
  woodPanel: () => canvasTex('woodPanel', 256, (g, n) => {
    const r = rnd(53), k = 8;
    for (let i = 0; i < k; i++) {
      const v = Math.floor(200 + r() * 45);
      g.fillStyle = `rgb(${v},${v},${v})`;
      g.fillRect((i * n) / k, 0, n / k, n);
      g.strokeStyle = 'rgba(0,0,0,0.06)';
      for (let q = 0; q < 5; q++) {
        g.beginPath();
        const x = (i * n) / k + r() * (n / k);
        g.moveTo(x, 0);
        g.bezierCurveTo(x + (r() - 0.5) * 6, n * 0.3, x + (r() - 0.5) * 6, n * 0.7, x, n);
        g.stroke();
      }
      g.fillStyle = 'rgba(0,0,0,0.28)';
      g.fillRect((i * n) / k, 0, 1.5, n);
    }
  }, 0.8),
  brick: () => canvasTex('brick', 256, (g, n) => {
    const r = rnd(59), rows = 14, cols = 4;
    g.fillStyle = '#cfc8bd';
    g.fillRect(0, 0, n, n);
    for (let j = 0; j < rows; j++) for (let i = -1; i < cols; i++) {
      const x = (i * n) / cols + (j % 2 ? n / cols / 2 : 0), y = (j * n) / rows;
      const h = 14 + r() * 10, sat = 0.45 + r() * 0.15, l = 0.38 + r() * 0.12;
      g.fillStyle = `hsl(${h},${sat * 100}%,${l * 100}%)`;
      g.fillRect(x + 1.5, y + 1.5, n / cols - 3, n / rows - 3);
    }
    noise(g, n, 3000, 0.12, r);
  }, 1.0),
  wallpaper: () => canvasTex('wallpaper', 256, (g, n) => {
    g.fillStyle = '#f4f1ea';
    g.fillRect(0, 0, n, n);
    g.strokeStyle = 'rgba(160,140,110,0.35)';
    g.lineWidth = 2;
    for (let x = 0; x < n; x += n / 4) {
      g.beginPath();
      for (let y = 0; y <= n; y += 4) g.lineTo(x + n / 8 + Math.sin((y / n) * Math.PI * 4) * 10, y);
      g.stroke();
    }
    g.fillStyle = 'rgba(160,140,110,0.3)';
    for (let x = 0; x < n; x += n / 4) for (let y = 0; y < n; y += n / 4) {
      g.beginPath();
      g.arc(x, y + n / 8, 4, 0, Math.PI * 2);
      g.fill();
    }
  }, 0.53),
  asphalt: () => canvasTex('asphalt', 256, (g, n) => {
    const r = rnd(61);
    g.fillStyle = '#8c8c8c';
    g.fillRect(0, 0, n, n);
    noise(g, n, 16000, 0.35, r);
  }, 2),
  paving: () => canvasTex('paving', 256, (g, n) => {
    const r = rnd(67), k = 8;
    g.fillStyle = '#9a9a9a';
    g.fillRect(0, 0, n, n);
    for (let j = 0; j < k; j++) for (let i = 0; i < k / 2; i++) {
      const v = Math.floor(200 + r() * 40);
      g.fillStyle = `rgb(${v},${v - 3},${v - 8})`;
      const off = j % 2 ? n / k : 0;
      g.fillRect(((i * 2 * n) / k + off) % n + 1, (j * n) / k + 1, (2 * n) / k - 2, n / k - 2);
      if (off && i === k / 2 - 1) g.fillRect(1, (j * n) / k + 1, n / k - 2, n / k - 2);
    }
  }, 1.6),
  lawn: () => canvasTex('lawn', 256, (g, n) => {
    const r = rnd(71);
    for (let i = 0; i < 4; i++) {
      g.fillStyle = i % 2 ? '#d9d9d9' : '#eeeeee';
      g.fillRect(0, (i * n) / 4, n, n / 4);
    }
    noise(g, n, 9000, 0.25, r);
  }, 6),
  field: () => canvasTex('field', 256, (g, n) => {
    const r = rnd(73);
    g.fillStyle = '#e6e6e6';
    g.fillRect(0, 0, n, n);
    for (let x = 0; x < n; x += 8) {
      g.fillStyle = 'rgba(0,0,0,0.12)';
      g.fillRect(x, 0, 3, n);
    }
    noise(g, n, 6000, 0.2, r);
  }, 6),
  facadeWin: () => canvasTex('facadeWin', 256, (g, n) => {
    g.fillStyle = '#f0f0f0';
    g.fillRect(0, 0, n, n);
    g.fillStyle = '#3d4a55';
    for (let j = 0; j < 2; j++) for (let i = 0; i < 2; i++) g.fillRect(i * 128 + 30, j * 128 + 24, 68, 78);
  }, 6),
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
      side: opts.double ? THREE.DoubleSide : opts.side === 'back' ? THREE.BackSide : THREE.FrontSide,
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

// ------------------------------------------------------------------ rezanje kosim krovom (potkrovlje)
// Zidovi potkrovlja idu visoko i režu se u shaderu po stvarnoj plohi krova: najviša od krovnih ploha
// svih krila (L, T, U kuće), tako da svaki dio zida završi točno ispod krila nad sobom.
const ROOF_MAX = 16;
const roofU = {
  uRA: { value: Array.from({ length: ROOF_MAX }, () => new THREE.Vector4()) },
  uRB: { value: Array.from({ length: ROOF_MAX }, () => new THREE.Vector4()) },
  uRP: { value: Array.from({ length: ROOF_MAX * 4 }, () => new THREE.Vector4()) },
  uRN: { value: 0 },
};
const ROOF_GLSL = `
uniform vec4 uRA[${ROOF_MAX}];
uniform vec4 uRB[${ROOF_MAX}];
uniform vec4 uRP[${ROOF_MAX * 4}];
uniform int uRN;
uniform float uRoofOff;
uniform float uRoofMode;
varying vec3 vPsqW;
float psqRoofH(vec2 p) {
  float best = -1e5;
  for (int i = 0; i < ${ROOF_MAX}; i++) {
    if (i >= uRN) break;
    vec4 a = uRA[i];
    vec4 b = uRB[i];
    float u = b.x * p.x + b.y * p.y;
    float v = -b.y * p.x + b.x * p.y;
    if (u < a.x - 0.001 || u > a.y + 0.001 || v < a.z - 0.001 || v > a.w + 0.001) continue;
    float h = 1e5;
    for (int k = 0; k < 4; k++) {
      if (float(k) >= b.w) break;
      vec4 q = uRP[i * 4 + k];
      h = min(h, q.x * u + q.y * v + q.z);
    }
    best = max(best, b.z + h);
  }
  return best;
}
`;
// mode 0: odreži sve iznad krova (zidovi); mode 1: odreži sve ispod najviše krovne plohe
// (dijelovi krila koji su ušli u susjedno krilo L/T kuće ne smiju se vidjeti iznutra)
function roofCut(m, off, mode = 0) {
  m.onBeforeCompile = (sh) => {
    Object.assign(sh.uniforms, roofU);
    sh.uniforms.uRoofOff = { value: off };
    sh.uniforms.uRoofMode = { value: mode };
    sh.vertexShader = 'varying vec3 vPsqW;\n' + sh.vertexShader.replace('#include <begin_vertex>', '#include <begin_vertex>\n  vPsqW = (modelMatrix * vec4(transformed, 1.0)).xyz;');
    sh.fragmentShader = ROOF_GLSL + sh.fragmentShader.replace('void main() {', 'void main() {\n  { float rh = psqRoofH(vPsqW.xz); if (rh > -1e4 && (uRoofMode < 0.5 ? vPsqW.y > rh + uRoofOff : vPsqW.y < rh + uRoofOff - 0.002)) discard; }');
  };
  m.customProgramCacheKey = () => 'psqroof';
  m.userData = { ...m.userData, roofOff: off };
  return m;
}
const roofDepthMats = new Map();
function roofDepth(off) {
  if (!roofDepthMats.has(off)) roofDepthMats.set(off, roofCut(new THREE.MeshDepthMaterial({ depthPacking: THREE.RGBADepthPacking, side: THREE.DoubleSide }), off));
  return roofDepthMats.get(off);
}

// ------------------------------------------------------------------ namještaj
// mali pomak po objektu (0–6 mm) da se tepisi koji se preklapaju ne „bore” (z-fighting)
function jitter(id) {
  let h = 0;
  for (const ch of String(id || '')) h = (h * 31 + ch.charCodeAt(0)) >>> 0;
  return (h % 7) * 0.001;
}
// Gradi objekt u lokalnim koordinatama: središte na podu, stražnja strana na -z.
function buildItem(it, g, loader) {
  const W = it.w, D = it.d, H = it.h;
  const color = it.color;
  let tgt = g;
  const b = (w, h, d, x, y, z, c = color, opts) => {
    const m = new THREE.Mesh(new THREE.BoxGeometry(Math.max(w, 0.002), Math.max(h, 0.002), Math.max(d, 0.002)), mat(c, opts));
    m.position.set(x, y, z);
    m.castShadow = h > 0.03;
    m.receiveShadow = true;
    tgt.add(m);
    return m;
  };
  const cyl = (rt, rbot, h, x, y, z, c, seg = 24, opts) => {
    const m = new THREE.Mesh(new THREE.CylinderGeometry(rt, rbot, h, seg), mat(c, opts));
    m.position.set(x, y, z);
    m.castShadow = true;
    m.receiveShadow = true;
    tgt.add(m);
    return m;
  };
  const sphere = (r, x, y, z, c, sy = 1, opts = { roughness: 1 }) => {
    const m = new THREE.Mesh(new THREE.SphereGeometry(r, 22, 16), mat(c, opts));
    m.position.set(x, y, z);
    m.scale.y = sy;
    m.castShadow = true;
    tgt.add(m);
    return m;
  };
  const metal = { metalness: 0.6, roughness: 0.35 };

  // pomični dijelovi (vrata ormara, ladice, svjetla) – engine ih otvara/pali na klik ili E
  const ud = g.userData || (g.userData = {});
  const parts = [];
  const interactive = (noun, def = 0, light = false) => { ud.parts = parts; ud.inter = { noun, def, light }; };
  const part = (o, prop, delta) => parts.push({ o, prop, delta });
  const inside = lighter(color, 0.18);
  const inGroup = (grp, f) => { const prev = tgt; tgt = grp; f(); tgt = prev; };
  // krilo s šarkom na x=hx (lokalno), otvara se prema +z; dir=+1 krilo ide u +x od šarke
  const hinged = (w, h, x, y, z, dir, c = color, opts, handleY = null, open = 1.75) => {
    const pv = new THREE.Group();
    pv.position.set(x, y, z);
    tgt.add(pv);
    inGroup(pv, () => {
      b(w, h, 0.02, (dir * w) / 2, h / 2, 0.01, c, opts);
      if (handleY !== null) b(0.015, 0.22, 0.025, dir * (w - 0.05), handleY, 0.032, 0x9a9a9a, metal);
    });
    part(pv, 'ry', -dir * open);
    return pv;
  };
  // šuplji korpus (stranice, strop, dno, leđa) – da se pri otvaranju vidi unutrašnjost
  const carcass = (w, h, d, c = color, inC = inside) => {
    const t = 0.02;
    for (const sx of [-1, 1]) b(t, h, d, sx * (w / 2 - t / 2), h / 2, 0, c);
    b(w, t, d, 0, h - t / 2, 0, c);
    b(w, 0.06, d, 0, 0.03, 0, c);
    b(w - 2 * t, h - 0.08, 0.01, 0, h / 2, -d / 2 + 0.005, inC);
  };
  // ormar s vratima u mreži cols × rows (splits: visine prijeloma redova)
  const cabinet = (w, h, d, cols, splits = [], opts) => {
    const dd = d - 0.02;
    const grp = new THREE.Group();
    grp.position.z = -0.01;
    tgt.add(grp);
    inGroup(grp, () => {
      carcass(w, h, dd);
      for (const y of splits) b(w - 0.04, 0.02, dd - 0.02, 0, y, 0.01, inside);
      if (h > 1.2) b(w - 0.04, 0.02, dd - 0.04, 0, h * 0.78, 0.01, inside);
    });
    const ys = [0, ...splits, h];
    const dw = w / cols;
    for (let r = 0; r + 1 < ys.length; r++) {
      const y0 = ys[r] + 0.003, hh = ys[r + 1] - ys[r] - 0.006;
      for (let i = 0; i < cols; i++) {
        const left = cols === 1 || i % 2 === 0;
        const hx = left ? -w / 2 + i * dw + 0.002 : -w / 2 + (i + 1) * dw - 0.002;
        const hy = r === 0 && ys.length > 2 ? hh - 0.2 : Math.min(hh / 2, 1.05 - y0);
        hinged(dw - 0.004, hh, hx, y0, d / 2 - 0.02, left ? 1 : -1, color, opts, Math.max(0.15, hy));
      }
    }
  };

  // noge prema izvedbi i stilu
  const legType = it.legs || 'wood';
  const legColor = legType === 'metal' ? 0x2a2a2a
    : legType === 'chrome' ? 0xcfd2d4
    : ({ klasicni: 0x5a3e2b, rustikalni: 0x7a5236, retro: 0x8a5a3a, industrijski: 0x6b4a33 })[it.style] || 0xc9a77c;
  const legOpts = legType === 'metal' || legType === 'chrome' ? { metalness: 0.7, roughness: 0.3 } : { roughness: 0.6 };
  const legs = (w, d, h, inset = 0.05, t = 0.045, c = null) => {
    for (const sx of [-1, 1]) for (const sz of [-1, 1]) {
      const x = sx * (w / 2 - inset), z = sz * (d / 2 - inset);
      if (c !== null) { b(t, h, t, x, h / 2, z, c); continue; }
      if (legType === 'metal' || legType === 'chrome') b(Math.min(t, 0.03), h, Math.min(t, 0.03), x, h / 2, z, legColor, legOpts);
      else cyl(t * 0.6, t * 0.38, h, x, h / 2, z, legColor, 10, legOpts);
    }
  };
  // podigni tijelo objekta na noge (ili na uvučeno postolje)
  const lift = (h, w, d) => {
    if (legType === 'plinth') {
      const ph = h > 0.25 ? h : Math.min(h, 0.06);
      b(w - 0.08, ph, d - 0.08, 0, ph / 2, 0, h > 0.25 ? color : 0x2a2a2a);
      const sub = new THREE.Group(); sub.position.y = ph; g.add(sub); tgt = sub;
      return ph;
    }
    legs(w, d, h, 0.07, 0.045);
    const sub = new THREE.Group(); sub.position.y = h; g.add(sub); tgt = sub;
    return h;
  };

  if (it.modelUrl && loader) {
    loadModel(loader, it.modelUrl, g, W, D, H, color);
    return;
  }

  switch (it.shape) {
    case 'bed':
    case 'bunk': {
      if (it.shape === 'bed' && it.legs) lift(0.12, W - 0.1, D - 0.1);
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
      const lh = lift(it.legs ? 0.1 : 0.0001, W - 0.1, D - 0.15);
      const Hs = H - lh;
      const sh = 0.2;
      b(W, sh, D, 0, sh / 2, 0, darker(color, 0.12));
      const arm = Math.min(0.18, W * 0.2);
      const seatW = W - arm * 2;
      const n = Math.max(1, Math.round(seatW / 0.7));
      for (let i = 0; i < n; i++) {
        const cw = seatW / n;
        b(cw - 0.015, 0.17, D - 0.26, -seatW / 2 + cw * (i + 0.5), sh + 0.085, 0.11, lighter(color, 0.08), { roughness: 1 });
      }
      b(W, Hs - sh, 0.22, 0, sh + (Hs - sh) / 2, -D / 2 + 0.11);
      for (const sx of [-1, 1]) b(arm, Math.min(0.62, Hs - 0.18), D, sx * (W / 2 - arm / 2), Math.min(0.62, Hs - 0.18) / 2, 0);
      break;
    }
    case 'sofa_corner': {
      const lh = lift(it.legs ? 0.1 : 0.0001, W - 0.1, D - 0.1);
      const sd = Math.min(0.95, D), cw = Math.min(0.95, W), sh = 0.22;
      b(W, sh, sd, 0, sh / 2, -D / 2 + sd / 2, darker(color, 0.12));
      b(cw, sh, D - sd, W / 2 - cw / 2, sh / 2, -D / 2 + sd + (D - sd) / 2, darker(color, 0.12));
      b(W - 0.4, 0.17, sd - 0.24, -0.1, sh + 0.085, -D / 2 + 0.22 + (sd - 0.24) / 2, lighter(color, 0.08), { roughness: 1 });
      b(cw - 0.24, 0.17, D - sd, W / 2 - 0.22 - (cw - 0.24) / 2, sh + 0.085, -D / 2 + sd + (D - sd) / 2, lighter(color, 0.08), { roughness: 1 });
      b(W, H - lh - sh, 0.22, 0, sh + (H - lh - sh) / 2, -D / 2 + 0.11);
      b(0.22, H - lh - sh, D, W / 2 - 0.11, sh + (H - lh - sh) / 2, 0);
      b(0.18, 0.5, sd, -W / 2 + 0.09, 0.25, -D / 2 + sd / 2);
      break;
    }
    case 'table':
    case 'island': {
      if (it.shape === 'island') {
        b(W, H - 0.04, D - 0.3, 0, (H - 0.04) / 2, -0.15);
        b(W, 0.04, D, 0, H - 0.02, 0, 0x3f4244, { roughness: 0.35 });
      } else if (legType === 'plinth') {
        b(W, 0.04, D, 0, H - 0.02, 0);
        b(Math.max(0.12, W * 0.18), H - 0.04, Math.max(0.12, D * 0.5), 0, (H - 0.04) / 2, 0, legColor === 0xc9a77c ? darker(color, 0.15) : legColor);
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
      if (legType === 'plinth') b(0.05, seat - 0.025, 0.05, 0, (seat - 0.025) / 2, 0, 0x555555, metal);
      else legs(W, D, seat - 0.025, 0.03, 0.035);
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
      cabinet(W, H, D, Math.max(2, Math.round(W / 0.5)));
      // šipka i nešto odjeće
      const rod = cyl(0.012, 0.012, W - 0.06, 0, H * 0.74, -0.02, 0x9a9a9a, 8, metal);
      rod.rotation.z = Math.PI / 2;
      const r = rnd(Math.round(W * 100));
      const cl = [0x40505e, 0xb9a88f, 0x7d3b3b, 0xd8d4cc, 0x2f2f33, 0x6f7f68];
      for (let x = -W / 2 + 0.12; x < W / 2 - 0.1; x += 0.09 + r() * 0.05) b(0.03, 0.75 + r() * 0.25, Math.min(0.42, D - 0.16), x, H * 0.74 - 0.45 - r() * 0.1, -0.02, cl[Math.floor(r() * cl.length)], { roughness: 1 });
      interactive('ormar');
      break;
    }
    case 'dresser':
    case 'tv_stand':
    case 'box': {
      const lh = it.legs && H > 0.3 ? lift(Math.min(0.14, H * 0.2), W, D) : 0;
      const Hb = H - lh;
      if (it.shape === 'dresser') {
        b(W, Hb, D - 0.02, 0, Hb / 2, -0.01);
        const rows = Math.max(1, Math.round(Hb / 0.22));
        const rh = Hb / rows;
        for (let i = 0; i < rows; i++) {
          const dr = new THREE.Group();
          tgt.add(dr);
          const yc = (i + 0.5) * rh;
          inGroup(dr, () => {
            b(W - 0.012, rh - 0.008, 0.02, 0, yc, D / 2 - 0.01);
            b(Math.min(0.2, W * 0.3), 0.015, 0.02, 0, yc, D / 2 + 0.01, 0x9a9a9a, metal);
            b(W - 0.06, Math.max(0.04, rh - 0.06), D * 0.62, 0, yc, D / 2 - 0.02 - D * 0.31, inside);
          });
          part(dr, 'pz', D * (0.5 - 0.08 * (rows - 1 - i) / Math.max(1, rows - 1)));
        }
        interactive('ladice');
      } else {
        b(W, Hb, D, 0, Hb / 2, 0);
      }
      if (it.shape === 'tv_stand') {
        const n = Math.max(2, Math.round(W / 0.5));
        for (let i = 1; i < n; i++) b(0.006, Hb - 0.04, 0.006, -W / 2 + (i * W) / n, Hb / 2, D / 2 + 0.003, darker(color, 0.35));
        b(W * 0.3, Hb * 0.5, 0.01, 0, Hb / 2, D / 2 + 0.004, 0x222222, { roughness: 0.4 });
      }
      break;
    }
    case 'pouf': {
      if (Math.abs(W - D) < 0.05) cyl(W / 2, W / 2, H, 0, H / 2, 0, color, 28, { roughness: 1 });
      else b(W, H, D, 0, H / 2, 0, color, { roughness: 1 });
      break;
    }
    case 'bench': {
      const lh = lift(H - 0.08, W - 0.04, D - 0.04);
      b(W, 0.06, D, 0, 0.03, 0);
      if (it.style) b(W - 0.04, 0.05, D - 0.04, 0, 0.085, 0, lighter(color, 0.08), { roughness: 1 });
      break;
    }
    case 'vitrine': {
      b(W, H, 0.02, 0, H / 2, -D / 2 + 0.01);
      for (const sx of [-1, 1]) b(0.03, H, D, sx * (W / 2 - 0.015), H / 2, 0);
      b(W, 0.04, D, 0, 0.02, 0);
      b(W, 0.04, D, 0, H - 0.02, 0);
      const n = Math.max(2, Math.round(H / 0.4));
      for (let i = 1; i < n; i++) b(W - 0.06, 0.012, D - 0.04, 0, (i * H) / n, 0, 0, { glass: true });
      for (const dir of [1, -1]) {
        const pv = new THREE.Group();
        pv.position.set(-dir * (W / 2 - 0.03), 0.04, D / 2 - 0.01);
        tgt.add(pv);
        inGroup(pv, () => {
          b((W - 0.06) / 2 - 0.002, H - 0.08, 0.01, (dir * ((W - 0.06) / 2)) / 2, (H - 0.08) / 2, 0, 0, { glass: true });
          b(0.008, 0.18, 0.015, dir * ((W - 0.06) / 2 - 0.03), (H - 0.08) / 2, 0.012, darker(color, 0.3));
        });
        part(pv, 'ry', -dir * 1.6);
      }
      interactive('vitrinu');
      break;
    }
    case 'crib': {
      b(W, 0.04, D, 0, 0.35, 0);
      b(W - 0.04, 0.1, D - 0.04, 0, 0.42, 0, 0xf4f1ea, { roughness: 1 });
      for (const sx of [-1, 1]) for (const sz of [-1, 1]) b(0.04, H, 0.04, sx * (W / 2 - 0.02), H / 2, sz * (D / 2 - 0.02));
      for (const sx of [-1, 1]) b(0.03, 0.03, D, sx * (W / 2 - 0.02), H - 0.015, 0);
      for (const sz of [-1, 1]) b(W, 0.03, 0.03, 0, H - 0.015, sz * (D / 2 - 0.02));
      const bars = Math.round(D / 0.08);
      for (let i = 1; i < bars; i++) for (const sx of [-1, 1]) b(0.015, H - 0.4, 0.015, sx * (W / 2 - 0.02), 0.4 + (H - 0.4) / 2, -D / 2 + (i * D) / bars);
      break;
    }
    case 'dishwasher': {
      b(W, H, D - 0.03, 0, H / 2, -0.015, 0xd9d9d6, { roughness: 0.4 });
      b(W - 0.06, 0.12, D - 0.12, 0, H * 0.3, -0.02, 0x9a9a9a, metal);
      b(W - 0.06, 0.12, D - 0.12, 0, H * 0.65, -0.02, 0x9a9a9a, metal);
      const pv = new THREE.Group();
      pv.position.set(0, 0.06, D / 2 - 0.03);
      tgt.add(pv);
      inGroup(pv, () => {
        b(W - 0.006, H - 0.07, 0.03, 0, (H - 0.07) / 2, 0.015, color, { roughness: 0.3 });
        b(W - 0.02, 0.1, 0.01, 0, H - 0.07 - 0.06, 0.032, darker(color, 0.25));
        b(W * 0.5, 0.02, 0.025, 0, H - 0.07 - 0.15, 0.04, 0x888888, metal);
      });
      part(pv, 'rx', 1.45);
      interactive('perilicu posuđa');
      break;
    }
    case 'tall': {
      cabinet(W, H, D, 1, [H * 0.45]);
      interactive('ormarić');
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
      } else if (W >= 1.7 && it.legs !== 'plain') {
        b(0.6, 0.012, D * 0.62, -W * 0.18, base + 0.002, 0, 0xb5b7b8, metal);
        cyl(0.012, 0.012, 0.3, -W * 0.18, base + 0.15, -D / 2 + 0.08, 0xcccccc, 10, metal);
        b(0.6, 0.008, 0.52, W * 0.22, base + 0.004, 0, 0x111111, { roughness: 0.2 });
      }
      if (H > 1.5) {
        b(W, 0.72, 0.35, 0, H - 0.36, -D / 2 + 0.175);
        for (let i = 1; i < n; i++) b(0.006, 0.68, 0.005, -W / 2 + (i * W) / n, H - 0.36, -D / 2 + 0.353, darker(color, 0.25));
        b(W, 0.6, 0.01, 0, base + 0.31, -D / 2 + 0.005, 0xe6e2da, { tex: 'tile' });
        if (W >= 1.7 && it.legs !== 'plain') b(0.6, 0.12, 0.35, W * 0.22, H - 0.78, -D / 2 + 0.175, 0x9a9a9a, metal);
      }
      break;
    }
    case 'stove': {
      b(W, H - 0.02, D, 0, (H - 0.02) / 2, 0);
      b(W, 0.02, D, 0, H - 0.01, 0, 0x111111, { roughness: 0.15 });
      const pv = new THREE.Group();
      pv.position.set(0, H * 0.175, D / 2);
      tgt.add(pv);
      inGroup(pv, () => {
        b(W - 0.08, H * 0.45, 0.02, 0, H * 0.225, 0.01, 0x1a1a1a, { roughness: 0.1 });
        b(W * 0.6, 0.02, 0.03, 0, H * 0.42, 0.035, 0xaaaaaa, metal);
      });
      part(pv, 'rx', 1.4);
      b(W - 0.12, 0.01, D - 0.1, 0, H * 0.35, 0, 0x555555, metal);
      interactive('pećnicu');
      break;
    }
    case 'fridge': {
      cabinet(W, H, D, 1, [H * 0.62], { roughness: 0.3, metalness: 0.3 });
      for (let k = 0; k < 3; k++) b(W - 0.06, 0.01, D - 0.1, 0, H * (0.68 + k * 0.1), -0.02, 0xdfe7ea, { glass: true });
      interactive('hladnjak');
      break;
    }
    case 'washer': {
      b(W, H, D, 0, H / 2, 0, color, { roughness: 0.3 });
      const rr = Math.min(W, H) * 0.3;
      const pv = new THREE.Group();
      pv.position.set(-rr, H * 0.45, D / 2);
      tgt.add(pv);
      inGroup(pv, () => {
        const door = cyl(rr, rr, 0.04, rr, 0, 0.02, 0x3a4248, 32, { roughness: 0.1, metalness: 0.4 });
        door.rotation.x = Math.PI / 2;
      });
      part(pv, 'ry', -1.5);
      interactive('perilicu');
      b(W - 0.04, 0.1, 0.01, 0, H - 0.07, D / 2 + 0.005, 0xdddddd);
      break;
    }
    case 'tv': {
      b(W, 0.5, D, 0, 0.25, 0);
      const sw = Math.min(W * 0.8, 1.45), sh = sw * 0.57;
      const scr = b(sw, sh, 0.035, 0, 0.58 + sh / 2, -D / 2 + 0.12, 0x0d0d0d, { roughness: 0.15 });
      scr.material = scr.material.clone();
      scr.material.emissive = new THREE.Color(0x8fb6ff);
      parts.push({ mat: scr.material, emi: 0.55 });
      interactive('TV', 0, true);
      b(0.3, 0.05, 0.2, 0, 0.525, -D / 2 + 0.12, 0x222222);
      break;
    }
    case 'radiator': {
      // pločasti radijator 15 cm od poda, s rebrima i ventilom
      const y0 = 0.15, z = -D / 2 + 0.05;
      b(W, H, 0.05, 0, y0 + H / 2, z, color, { roughness: 0.45 });
      const n = Math.max(4, Math.floor(W / 0.05));
      for (let i = 0; i < n; i++) b(0.012, H - 0.04, 0.012, -W / 2 + (i + 0.5) * (W / n), y0 + H / 2, z + 0.029, lighter(color, 0.05), { roughness: 0.45 });
      b(W - 0.02, 0.025, 0.06, 0, y0 + H - 0.012, z, color, { roughness: 0.45 });
      cyl(0.015, 0.015, 0.08, W / 2 - 0.04, y0 - 0.04, z, 0xd0d2d4, 10, metal);
      cyl(0.022, 0.022, 0.05, W / 2 - 0.04, y0 - 0.1, z, 0xf0f0f0, 12);
      break;
    }
    case 'towel_radiator': {
      const y0 = 0.25, z = -D / 2 + 0.05;
      for (const sx of [-1, 1]) cyl(0.017, 0.017, H, sx * (W / 2 - 0.02), y0 + H / 2, z, color, 10, { roughness: 0.4 });
      const n = Math.max(6, Math.round(H / 0.07));
      for (let i = 0; i < n; i++) {
        if (i % 6 === 5) continue;
        const bar = cyl(0.011, 0.011, W - 0.04, 0, y0 + 0.04 + (i * (H - 0.08)) / (n - 1), z, color, 8, { roughness: 0.4 });
        bar.rotation.z = Math.PI / 2;
      }
      break;
    }
    case 'ac_indoor': {
      // unutarnja jedinica klime visoko na zidu (gornji rub 2,35 m)
      const yt = Math.min(2.35, (it.ceil ?? 2.57) - 0.15), z = -D / 2 + D / 2;
      const body = b(W, H, D, 0, yt - H / 2, z, color, { roughness: 0.35 });
      body.castShadow = true;
      b(W * 0.92, 0.02, 0.02, 0, yt - H + 0.04, z + D / 2 - 0.02, darker(color, 0.4));
      b(0.05, 0.012, 0.004, W / 2 - 0.08, yt - 0.08, z + D / 2 + 0.002, 0x7fd6ff, { emissive: 0x7fd6ff, emissiveIntensity: 0.6 });
      break;
    }
    case 'ac_outdoor':
    case 'heat_pump': {
      b(W, H - 0.06, D, 0, 0.06 + (H - 0.06) / 2, 0, color, { roughness: 0.6 });
      for (const sx of [-1, 1]) b(0.06, 0.06, D + 0.04, sx * (W / 2 - 0.08), 0.03, 0, 0x555555);
      const fans = it.shape === 'heat_pump' && H > 1.1 ? 2 : 1;
      for (let i = 0; i < fans; i++) {
        const fy = 0.06 + (H - 0.06) * (fans === 1 ? 0.5 : 0.28 + i * 0.44);
        const r = Math.min(W * 0.3, (H - 0.06) / (fans * 2.3));
        const g2 = cyl(r, r, 0.02, -W * 0.12, fy, D / 2 + 0.005, 0x2e3236, 28);
        g2.rotation.x = Math.PI / 2;
        for (let k = 0; k < 4; k++) {
          const bar = b(r * 2, 0.01, 0.01, -W * 0.12, fy, D / 2 + 0.02, 0x6a6e72);
          bar.rotation.z = (k * Math.PI) / 4;
        }
      }
      break;
    }
    case 'boiler': {
      const yc = 1.55, r = Math.min(W, D) / 2;
      cyl(r, r, H, 0, yc, -D / 2 + r, color, 28, { roughness: 0.35 });
      sphere(r, 0, yc - H / 2, -D / 2 + r, color, 0.35, { roughness: 0.35 });
      for (const dx of [-0.05, 0.05]) cyl(0.012, 0.012, 0.3, dx, yc - H / 2 - 0.2, -D / 2 + r, 0xb9b9b9, 8, metal);
      b(0.08, 0.05, 0.01, 0, yc - H * 0.25, -D / 2 + 2 * r + 0.004, 0x333333);
      break;
    }
    case 'drain_stack': {
      // instalacijski kanal (obloženi gips) od poda do stropa s revizijskim otvorom
      const C = it.ceil ?? 2.57;
      b(W, C, D, 0, C / 2, 0, color, { roughness: 0.9 });
      b(0.16, 0.16, 0.006, 0, 0.55, D / 2 + 0.003, 0xe2e2df, { roughness: 0.6 });
      b(0.03, 0.01, 0.008, 0, 0.6, D / 2 + 0.007, 0x9a9a9a, metal);
      break;
    }
    case 'floor_drain': {
      b(W, 0.006, D, 0, 0.003, 0, color, metal);
      const n = Math.max(2, Math.round(Math.max(W, D) / 0.025));
      for (let i = 1; i < n; i++) {
        const f = -0.5 + i / n;
        if (W >= D) b(0.006, 0.002, D * 0.7, f * W, 0.007, 0, 0x1a1a1a);
        else b(W * 0.7, 0.002, 0.006, 0, 0.007, f * D, 0x1a1a1a);
      }
      break;
    }
    case 'water_manifold': {
      const y0 = 0.35;
      b(W, H, D, 0, y0 + H / 2, 0, color, { roughness: 0.5 });
      b(W - 0.04, H - 0.04, 0.004, 0, y0 + H / 2, D / 2 + 0.002, darker(color, 0.04), { roughness: 0.5 });
      b(0.05, 0.015, 0.012, W / 2 - 0.06, y0 + H / 2, D / 2 + 0.008, 0x888888, metal);
      for (const dx of [-W * 0.3, -W * 0.1, W * 0.1, W * 0.3]) cyl(0.012, 0.012, y0, dx, y0 / 2, 0, 0xc9c9c9, 8, metal);
      break;
    }
    case 'manhole': {
      b(W, 0.05, D, 0, 0.025, 0, color, { roughness: 0.95 });
      cyl(Math.min(W, D) * 0.36, Math.min(W, D) * 0.36, 0.012, 0, 0.056, 0, 0x3a3a3a, 32, metal);
      break;
    }
    case 'wood_stove': {
      b(W, H * 0.12, D, 0, H * 0.06, 0, darker(color, 0.2));
      b(W, H * 0.78, D, 0, H * 0.12 + H * 0.39, 0, color, { roughness: 0.6 });
      const fire = b(W * 0.6, H * 0.35, 0.01, 0, H * 0.45, D / 2 + 0.006, 0xff8a3d, { emissive: 0xff6a1a, emissiveIntensity: 1.2 });
      fire.material = fire.material.clone();
      b(W * 0.66, H * 0.4, 0.012, 0, H * 0.45, D / 2 + 0.002, 0x111111);
      parts.push({ mat: fire.material, emi: 1.2 });
      const C = it.ceil ?? 2.57;
      cyl(0.075, 0.075, C - H * 0.9, 0, H * 0.9 + (C - H * 0.9) / 2, -D * 0.15, 0x2a2a2a, 16, metal);
      interactive('vatru', 1, true);
      break;
    }
    case 'socket':
    case 'socket_double':
    case 'socket_high':
    case 'switch':
    case 'tv_socket':
    case 'lan_socket': {
      // pločica na zidu (stražnja strana objekta je uz zid)
      const y = { socket_high: 1.1, switch: 1.1 }[it.shape] ?? 0.3;
      const n = it.shape === 'socket_double' || it.shape === 'socket_high' ? 2 : 1;
      const z = -D / 2 + 0.006;
      for (let i = 0; i < n; i++) {
        const x = n === 1 ? 0 : (i - 0.5) * 0.075;
        b(0.07, 0.07, 0.012, x, y, z, color, { roughness: 0.4 });
        if (it.shape === 'switch') b(0.05, 0.05, 0.006, x, y, z + 0.009, lighter(color, 0.08), { roughness: 0.3 });
        else if (it.shape === 'tv_socket' || it.shape === 'lan_socket') b(0.016, 0.014, 0.004, x, y, z + 0.008, 0x222222);
        else {
          cyl(0.02, 0.02, 0.004, x, y, z + 0.008, darker(color, 0.12), 20).rotation.x = Math.PI / 2;
          for (const dx of [-0.009, 0.009]) cyl(0.0025, 0.0025, 0.004, x + dx, y, z + 0.01, 0x111111, 6).rotation.x = Math.PI / 2;
        }
      }
      break;
    }
    case 'light_point': {
      const C = it.ceil ?? 2.57;
      cyl(0.05, 0.05, 0.02, 0, C - 0.01, 0, color, 20);
      cyl(0.004, 0.004, 0.2, 0, C - 0.11, 0, 0x222222, 6);
      const bulb = mat(0xfff4e0, { emissive: 0xffd9a0, emissiveIntensity: 1 }).clone();
      const s = sphere(0.04, 0, C - 0.24, 0, 0xffffff);
      s.material = bulb;
      s.castShadow = false;
      parts.push({ mat: bulb, emi: 1 });
      interactive('svjetlo', 0, true);
      break;
    }
    case 'chandelier':
    case 'chandelier_ring':
    case 'pendant':
    case 'pendant_row':
    case 'ceiling_light':
    case 'wall_lamp':
    case 'table_lamp':
    case 'lamp_arc': {
      const C = it.ceil ?? 2.57; // strop iznad poda objekta
      const bulb = mat(0xfff4e0, { emissive: 0xffd9a0, emissiveIntensity: 1.2 }).clone();
      const glow = { mat: bulb, emi: 1.2 };
      const addLight = (x, y, z, li, dist = 7) => {
        if (lampBudget > 0 && g.userData?.kind) {
          lampBudget--;
          const L = new THREE.PointLight(0xffd6a0, 0, dist, 1.5);
          L.position.set(x, y, z);
          tgt.add(L);
          if (!glow.light) { glow.light = L; glow.li = li; }
          else parts.push({ light: L, li });
        }
      };
      const lit = (m) => { m.material = bulb; m.castShadow = false; return m; };
      const cable = (x, z, y0, y1) => cyl(0.004, 0.004, y0 - y1, x, (y0 + y1) / 2, z, 0x222222, 6);
      const canopy = (x, z, r = 0.06) => cyl(r, r, 0.04, x, C - 0.02, z, color, 20, metal);
      if (it.shape === 'chandelier') {
        const drop = Math.min(H, C - 1.95);
        canopy(0, 0, 0.08);
        cyl(0.012, 0.012, drop * 0.45, 0, C - (drop * 0.45) / 2, 0, color, 8, metal);
        sphere(0.07, 0, C - drop * 0.5, 0, color, 1.3, metal);
        const ringY = C - drop * 0.75, R = W * 0.4;
        const ring = new THREE.Mesh(new THREE.TorusGeometry(R, 0.012, 8, 40), mat(color, metal));
        ring.rotation.x = Math.PI / 2;
        ring.position.y = ringY;
        tgt.add(ring);
        const n = 6;
        for (let i = 0; i < n; i++) {
          const a = (i / n) * Math.PI * 2, x = Math.sin(a) * R, z = Math.cos(a) * R;
          const arm = b(R, 0.012, 0.012, x / 2, ringY + 0.02, z / 2, color, metal);
          arm.rotation.y = a - Math.PI / 2;
          cyl(0.025, 0.02, 0.04, x, ringY + 0.03, z, color, 12, metal); // čašica
          cyl(0.01, 0.01, 0.1, x, ringY + 0.1, z, 0xf4efe6, 8);         // svijeća
          lit(sphere(0.022, x, ringY + 0.17, z, 0xffffff, 1.4));
          // kristali
          for (let k = 0; k < 2; k++) {
            const ca = a + Math.PI / n + k * 0.25;
            sphere(0.012, Math.sin(ca) * (R * 0.85), ringY - 0.08 - k * 0.05, Math.cos(ca) * (R * 0.85), 0xffffff, 1.6, { glass: true });
          }
        }
        addLight(0, ringY + 0.1, 0, 9, 9);
      } else if (it.shape === 'chandelier_ring') {
        const drop = Math.min(H, C - 1.95);
        canopy(0, 0, 0.1);
        const ringY = C - drop;
        for (let i = 0; i < 3; i++) {
          const a = (i / 3) * Math.PI * 2;
          cable(Math.sin(a) * W * 0.45, Math.cos(a) * W * 0.45, C, ringY);
        }
        const r1 = new THREE.Mesh(new THREE.TorusGeometry(W / 2, 0.025, 10, 64), mat(color, metal));
        r1.rotation.x = Math.PI / 2;
        r1.position.y = ringY;
        tgt.add(r1);
        const strip = new THREE.Mesh(new THREE.TorusGeometry(W / 2, 0.012, 8, 64), bulb);
        strip.rotation.x = Math.PI / 2;
        strip.position.y = ringY - 0.022;
        tgt.add(strip);
        if (W >= 0.8) {
          const r2 = new THREE.Mesh(new THREE.TorusGeometry(W * 0.3, 0.02, 10, 48), mat(color, metal));
          r2.rotation.x = Math.PI / 2;
          r2.position.y = ringY + 0.12;
          tgt.add(r2);
          cable(0, W * 0.3, C, ringY + 0.12);
        }
        addLight(0, ringY - 0.05, 0, 8, 9);
      } else if (it.shape === 'pendant' || it.shape === 'pendant_row') {
        const n = it.shape === 'pendant_row' ? 3 : 1;
        const r = it.shape === 'pendant_row' ? Math.min(D / 2, W / 7) : W / 2;
        if (n > 1) b(W * 0.9, 0.03, 0.08, 0, C - 0.015, 0, color, metal);
        const drop = Math.min(H, C - 1.5);
        for (let i = 0; i < n; i++) {
          const x = n === 1 ? 0 : -W * 0.35 + (i * W * 0.7) / (n - 1);
          if (n === 1) canopy(x, 0);
          const yb = C - drop;
          cable(x, 0, C, yb + r * 0.9);
          const shade = new THREE.Mesh(new THREE.CylinderGeometry(0.03, r, r * 0.9, 28, 1, true), mat(color, { roughness: 0.6, double: true }));
          shade.position.set(x, yb + r * 0.45, 0);
          shade.castShadow = true;
          tgt.add(shade);
          lit(sphere(r * 0.25, x, yb + r * 0.25, 0, 0xffffff));
          addLight(x, yb, 0, n > 1 ? 3 : 5, 6);
        }
      } else if (it.shape === 'ceiling_light') {
        const pl = cyl(W / 2, W / 2 - 0.02, Math.max(0.04, H * 0.4), 0, C - Math.max(0.04, H * 0.4) / 2, 0, color, 32, metal);
        pl.castShadow = false;
        const dome = sphere(W / 2 - 0.02, 0, C - H * 0.4, 0, 0xffffff, (H * 0.6) / (W / 2));
        lit(dome);
        dome.geometry = new THREE.SphereGeometry(W / 2 - 0.02, 28, 12, 0, Math.PI * 2, Math.PI / 2, Math.PI / 2);
        addLight(0, C - H - 0.1, 0, 6, 8);
      } else if (it.shape === 'wall_lamp') {
        const y = 1.75;
        b(0.1, 0.16, 0.02, 0, y, -D / 2 + 0.01, color, metal);
        const arm = b(0.015, 0.015, D * 0.7, 0, y, -D / 2 + D * 0.35, color, metal);
        arm.castShadow = false;
        const shade = new THREE.Mesh(new THREE.CylinderGeometry(W * 0.3, W * 0.45, H * 0.5, 24, 1, true), mat(0xf2ede2, { roughness: 0.9, double: true, emissive: 0xffd9a0, emissiveIntensity: 0.4 }));
        shade.position.set(0, y + 0.05, D / 2 - W * 0.45);
        tgt.add(shade);
        lit(sphere(0.03, 0, y + 0.02, D / 2 - W * 0.45, 0xffffff));
        addLight(0, y, D / 2 - W * 0.45, 2.5, 5);
      } else if (it.shape === 'table_lamp') {
        const e = it.elev || 0; // stoji na stolu/komodi
        cyl(W * 0.22, W * 0.26, 0.03, 0, e + 0.015, 0, darker(color, 0.4), 24);
        const base = sphere(W * 0.2, 0, e + H * 0.22, 0, color, 1.2, { roughness: 0.4 });
        base.castShadow = true;
        cyl(0.01, 0.01, H * 0.35, 0, e + H * 0.5, 0, 0xb8b8b8, 8, metal);
        const shade = new THREE.Mesh(new THREE.CylinderGeometry(W * 0.32, W * 0.5, H * 0.38, 28, 1, true), mat(0xf2ede2, { roughness: 0.95, double: true, emissive: 0xffd9a0, emissiveIntensity: 0.5 }));
        shade.position.y = e + H * 0.8;
        shade.castShadow = true;
        tgt.add(shade);
        lit(sphere(0.035, 0, e + H * 0.72, 0, 0xffffff));
        addLight(0, e + H * 0.72, 0, 2.5, 5);
      } else {
        // lučna podna lampa: teška baza straga, luk prema naprijed, kupola nad sjedalom
        cyl(0.17, 0.19, 0.06, 0, 0.03, -D / 2 + 0.18, 0xe8e4dc, 32, { roughness: 0.4 }); // mramorna baza
        const zb = -D / 2 + 0.18, L = D - 0.4;
        const curve = new THREE.CubicBezierCurve3(
          new THREE.Vector3(0, 0.06, zb),
          new THREE.Vector3(0, H * 0.95, zb - 0.05),
          new THREE.Vector3(0, H + 0.2, zb + L * 0.75),
          new THREE.Vector3(0, H - 0.05, zb + L),
        );
        const pts = curve.getPoints(32);
        const tube = new THREE.Mesh(new THREE.TubeGeometry(curve, 48, 0.013, 8), mat(color, metal));
        tube.castShadow = true;
        tgt.add(tube);
        const end = pts[pts.length - 1];
        const dome = new THREE.Mesh(new THREE.SphereGeometry(0.2, 28, 12, 0, Math.PI * 2, 0, Math.PI / 2), mat(color, { ...metal, double: true }));
        dome.position.set(0, end.y - 0.12, end.z);
        dome.castShadow = true;
        tgt.add(dome);
        lit(sphere(0.04, 0, end.y - 0.12, end.z, 0xffffff));
        addLight(0, end.y - 0.2, end.z, 4, 6);
      }
      parts.push(glow);
      interactive('svjetlo', 1, true);
      break;
    }
    case 'lamp': {
      cyl(0.15, 0.15, 0.03, 0, 0.015, 0, 0x2a2a2a);
      cyl(0.012, 0.012, H - 0.3, 0, (H - 0.3) / 2, 0, 0x2a2a2a, 8);
      const shade = cyl(W * 0.35, W * 0.48, 0.3, 0, H - 0.15, 0, color, 24, { emissive: 0xffd9a0, emissiveIntensity: 0.7, double: true });
      shade.material = shade.material.clone();
      const pt = { mat: shade.material, emi: 0.7 };
      if (lampBudget > 0 && g.userData?.kind) {
        lampBudget--;
        const L = new THREE.PointLight(0xffd6a0, 0, 6, 1.5);
        L.position.set(0, H - 0.25, 0);
        tgt.add(L);
        pt.light = L;
        pt.li = 3.5;
      }
      parts.push(pt);
      interactive('svjetlo', 1, true);
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
      b(W, h, D, 0, h / 2 + 0.004 + jitter(it.id), 0, color, it.shape === 'path' ? { tex: 'stone' } : { tex: 'carpet', roughness: 1 });
      break;
    }
    case 'rug_round': {
      cyl(W / 2, W / 2, 0.012, 0, 0.01 + jitter(it.id), 0, color, 48, { tex: 'carpet', roughness: 1 });
      break;
    }
    case 'balcony':
    case 'balcony_rail':
    case 'balcony_wall': {
      // ploča (gornja ploha = gotovi pod), ograda na tri strane; stražnja strana (-z) je uz zid
      const st = 0.18;
      b(W, 0.02, D, 0, -0.01, 0, color, { tex: 'tile', roughness: 0.7 });
      b(W, st - 0.02, D, 0, -0.02 - (st - 0.02) / 2, 0, 0xe4ded4, { tex: 'plaster', roughness: 0.95 });
      const Hr = Math.max(0.6, H);
      const wallT = it.shape === 'balcony_wall' ? 0.12 : 0.06;
      // dijelovi ograde: prednja (os x) i bočne (os z); bočne završavaju prije prednje (bez preklapanja)
      const segs = [
        { ax: 'x', a0: -W / 2, a1: W / 2, f: D / 2 - wallT / 2 },
        { ax: 'z', a0: -D / 2, a1: D / 2 - wallT, f: -W / 2 + wallT / 2 },
        { ax: 'z', a0: -D / 2, a1: D / 2 - wallT, f: W / 2 - wallT / 2 },
      ];
      const seg = (sg, y, h, th, c, opts, a0 = sg.a0, a1 = sg.a1) => sg.ax === 'x'
        ? b(a1 - a0, h, th, (a0 + a1) / 2, y, sg.f, c, opts)
        : b(th, h, a1 - a0, sg.f, y, (a0 + a1) / 2, c, opts);
      for (const sg of segs) {
        if (it.shape === 'balcony_wall') {
          seg(sg, Hr / 2, Hr, wallT, 0xece7df, { tex: 'plaster', roughness: 0.95 });
          seg(sg, Hr + 0.02, 0.04, wallT + 0.04, 0xd8d2c8, { tex: 'stone' }, sg.a0, sg.ax === 'z' ? sg.a1 - 0.021 : sg.a1);
        } else if (it.shape === 'balcony_rail') {
          const rc = 0x2e3236;
          seg(sg, Hr - 0.02, 0.04, 0.05, rc, metal);
          seg(sg, 0.1, 0.03, 0.03, rc, metal);
          const len = sg.a1 - sg.a0, n = Math.max(2, Math.round(len / 0.12));
          for (let k = 0; k <= n; k++) {
            const a = sg.a0 + (k * len) / n;
            seg(sg, 0.06 + (Hr - 0.12) / 2, Hr - 0.12, 0.018, rc, metal, a - 0.009, a + 0.009);
          }
        } else {
          seg(sg, 0.04, 0.08, 0.06, 0x9a9a9a, metal);
          seg(sg, 0.06 + (Hr - 0.1) / 2, Hr - 0.1, 0.015, 0, { glass: true }, sg.a0 + 0.005, sg.a1 - 0.005);
          seg(sg, Hr - 0.02, 0.04, 0.06, 0xbfc3c6, metal);
        }
      }
      break;
    }
    case 'fireplace': {
      b(W, H, D, 0, H / 2, 0, color, { tex: 'stone' });
      b(W * 0.55, H * 0.5, 0.05, 0, H * 0.3, D / 2 - 0.02, 0x141414);
      const fire = b(W * 0.45, 0.12, 0.03, 0, H * 0.13, D / 2 - 0.01, 0xff8a3d, { emissive: 0xff6a1a, emissiveIntensity: 1.2 });
      fire.material = fire.material.clone();
      parts.push({ mat: fire.material, emi: 1.2 });
      interactive('vatru', 1, true);
      b(W + 0.1, 0.06, D + 0.06, 0, H + 0.03, 0, 0xd8d2c8);
      break;
    }
    case 'stairs_l': {
      const g = stairL(W, D);
      const n = Math.max(4, Math.round(H / 0.175));
      const n1 = clamp(Math.round(n * g.r1), 2, n - 2);
      const rise = H / n;
      const run1 = g.L1 / n1, run2 = g.L2 / (n - n1);
      const xs = W / 2 - g.fw / 2; // os prvog kraka
      const zs = -D / 2 + g.fw / 2; // os drugog kraka
      for (let j = 1; j < n1; j++) {
        const y = j * rise;
        b(g.fw, 0.04, run1 + 0.02, xs, y - 0.02, D / 2 - run1 * (j - 0.5), color);
        b(g.fw, rise - 0.04, 0.02, xs, y - rise / 2 - 0.02, D / 2 - run1 * (j - 1), 0xf2f0ec);
      }
      // podest
      b(g.fw, 0.06, g.fw, xs, n1 * rise - 0.03, zs, color);
      b(g.fw, rise - 0.04, 0.02, xs, n1 * rise - rise / 2 - 0.02, -D / 2 + g.fw, 0xf2f0ec);
      b(g.fw, n1 * rise - 0.06, 0.08, xs, (n1 * rise - 0.06) / 2, -D / 2 + 0.04, 0xe9e5de); // nosivi zidić ispod podesta
      for (let j = 1; j <= n - n1; j++) {
        const y = (n1 + j) * rise;
        b(run2 + 0.02, 0.04, g.fw, W / 2 - g.fw - run2 * (j - 0.5), y - 0.02, zs, color);
        b(0.02, rise - 0.04, g.fw, W / 2 - g.fw - run2 * (j - 1), y - rise / 2 - 0.02, zs, 0xf2f0ec);
      }
      // rukohvati na unutarnjoj strani krakova
      const r1 = b(0.04, 0.04, Math.hypot(g.L1, n1 * rise), W / 2 - g.fw + 0.03, (n1 * rise) / 2 + 0.9, D / 2 - g.L1 / 2, 0x333333);
      r1.rotation.x = Math.atan2(n1 * rise, g.L1);
      const r2 = b(Math.hypot(g.L2, (n - n1) * rise), 0.04, 0.04, W / 2 - g.fw - g.L2 / 2, n1 * rise + ((n - n1) * rise) / 2 + 0.9, -D / 2 + g.fw - 0.03, 0x333333);
      r2.rotation.z = -Math.atan2((n - n1) * rise, g.L2);
      break;
    }
    case 'stairs_spiral': {
      const R = Math.min(W, D) / 2;
      const n = Math.max(8, Math.round(H / 0.19));
      const rise = H / n, dA = SPIRAL_SWEEP / n;
      cyl(0.06, 0.06, H + 0.95, 0, (H + 0.95) / 2, 0, 0x3a3a3a, 16, metal);
      let prev = null;
      for (let j = 1; j <= n; j++) {
        const a0 = (j - 1) * dA;
        const geo = new THREE.CylinderGeometry(R, R, 0.04, 8, 1, false, a0, dA * 1.08);
        const m = new THREE.Mesh(geo, mat(color));
        m.position.y = j * rise - 0.02;
        m.castShadow = true;
        m.receiveShadow = true;
        tgt.add(m);
        // rukohvat: stupić na vanjskom rubu i spoj s prethodnim
        const am = a0 + dA / 2;
        const px = (R - 0.04) * Math.sin(am), pz = (R - 0.04) * Math.cos(am);
        cyl(0.012, 0.012, 0.9, px, j * rise + 0.45, pz, 0x3a3a3a, 6, metal);
        const top = new THREE.Vector3(px, j * rise + 0.9, pz);
        if (prev) {
          const len = prev.distanceTo(top);
          const rail = cyl(0.02, 0.02, len, (prev.x + top.x) / 2, (prev.y + top.y) / 2, (prev.z + top.z) / 2, 0x3a3a3a, 6, metal);
          rail.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), top.clone().sub(prev).normalize());
        }
        prev = top;
      }
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
    r.localClippingEnabled = true; // zidovi potkrovlja odrezani kosim krovom
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
    this.ground = ground;

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

    this.avatar = this._makeAvatar();
    this.avatar.root.visible = false;
    scene.add(this.avatar.root);
    this.tp = { x: 0, z: 0, heading: 0, yaw: 0, pitch: 0.78, dist: 5.2, speed: 0, phase: 0 };
    this.kbd = false;
    this.wallMeshes = [];

    this.mode = 'orbit';
    this.keys = new Set();
    this.colliders = [];
    this.ceilings = [];
    this.roofs = [];
    this.itemGroups = new Map();
    this.wallGroups = new Map();
    this.plan = null;
    this.fy = 0; // visina poda aktivne etaže
    this.showAll = false; // u pogledu izvana prikaži i etaže iznad aktivne
    this.levelGroups = [];
    this.inters = []; // vrata, prozori, ormari, svjetla…
    this.openState = new Map(); // id -> 0/1 (pamti se kroz ponovnu izgradnju scene)
    this.aim = null;
    this.aimAt = 0;
    this._tgt = null;
    this._passive = false;
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

    const moveKeys = new Set(['KeyW', 'KeyA', 'KeyS', 'KeyD', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'ShiftLeft', 'ShiftRight']);
    const keyCodes = { w: 'KeyW', a: 'KeyA', s: 'KeyS', d: 'KeyD', ArrowUp: 'ArrowUp', ArrowDown: 'ArrowDown', ArrowLeft: 'ArrowLeft', ArrowRight: 'ArrowRight', Shift: 'ShiftLeft' };
    const codeOf = (e) => e.code || keyCodes[e.key] || keyCodes[(e.key || '').toLowerCase()] || '';
    window.addEventListener('keydown', (e) => {
      const code = codeOf(e);
      const fp = this.mode === 'walk' && this.fpv.isLocked;
      const tp = this.mode === 'third' && this.kbd && moveKeys.has(code) && !e.ctrlKey && !e.metaKey;
      if ((fp || (this.mode === 'third' && this.kbd)) && (code === 'KeyE' || e.key === 'e' || e.key === 'E') && !e.ctrlKey && !e.metaKey) {
        if (!e.repeat) this._interact();
        e.preventDefault();
        e.stopPropagation();
        e.stopImmediatePropagation();
        return;
      }
      if (fp || tp) {
        this.keys.add(code);
        e.preventDefault();
        e.stopPropagation();
        e.stopImmediatePropagation();
      }
    }, true);
    window.addEventListener('blur', () => this.keys.clear());
    document.addEventListener('pointerdown', (e) => {
      if (e.target !== this.renderer.domElement) { this.kbd = false; this.keys.clear(); }
    }, true);
    window.addEventListener('keyup', (e) => {
      const code = codeOf(e);
      if (this.keys.has(code)) {
        this.keys.delete(code);
        if (this.mode === 'third' && this.kbd) { e.preventDefault(); e.stopPropagation(); }
      }
    }, true);
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
    const fy = this.plan.elevation || 0;
    if (Math.abs(fy - this.fy) > 0.001) {
      const d = fy - this.fy;
      this.fy = fy;
      if (this._stairOff != null) this._stairOff -= d; // isti položaj u prostoru, nova etaža
      if (this.tp && this.tp.off != null) this.tp.off -= d;
      // prebaci promatrača na novu etažu
      this.camera.position.y += d;
      if (this.mode === 'orbit') this.orbit.target.y += d;
    }
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
    if (o.showAll != null) { this.showAll = !!o.showAll; this._applyVisibility(); }
    if (o.measure != null) this._setMeasure(!!o.measure);
  }

  // ------------------------------------------------------------------ mjerenje u 3D-u
  _setMeasure(on) {
    const m = (this.meas ||= { on: false, pts: [] });
    m.on = on;
    this._clearMeasure();
    if (!m.label) {
      m.label = document.createElement('div');
      Object.assign(m.label.style, {
        position: 'absolute', transform: 'translate(-50%, -130%)', padding: '4px 9px', borderRadius: '7px',
        background: '#b0562b', color: '#fff', font: '700 13px Archivo, system-ui, sans-serif', pointerEvents: 'none',
        whiteSpace: 'nowrap', display: 'none', boxShadow: '0 2px 8px rgba(0,0,0,.25)',
      });
      this.renderer.domElement.parentElement?.appendChild(m.label);
    }
    this._updateHint();
  }

  _clearMeasure() {
    const m = this.meas;
    if (!m) return;
    m.pts = [];
    if (m.group) { this.scene.remove(m.group); m.group = null; }
    if (m.label) m.label.style.display = 'none';
  }

  // točka na površini ispod zrake (zidovi, pod, namještaj; staklo i nevidljivo se preskače)
  _surfacePoint(ray) {
    const hits = ray.intersectObjects(this.world.children, true);
    for (const h of hits) {
      const o = h.object;
      if (!o.visible || o.isPoints || o.isLine || this._cutAway(h)) continue;
      let vis = true;
      for (let q = o.parent; q; q = q.parent) if (!q.visible) { vis = false; break; }
      if (!vis) continue;
      if (o.material?.transparent && (o.material.opacity ?? 1) < 0.5) continue;
      return h.point.clone();
    }
    const p = new THREE.Vector3();
    return ray.ray.intersectPlane(new THREE.Plane(new THREE.Vector3(0, 1, 0), -this.fy), p) ? p : null;
  }

  _measureAt(ndc) {
    const m = this.meas;
    if (!m?.on) return false;
    this.raycaster.setFromCamera(ndc, this.camera);
    const p = this._surfacePoint(this.raycaster);
    if (!p) return true;
    if (m.pts.length >= 2) this._clearMeasure();
    m.pts.push(p);
    if (!m.group) { m.group = new THREE.Group(); this.scene.add(m.group); }
    const dot = new THREE.Mesh(new THREE.SphereGeometry(0.035, 16, 10), new THREE.MeshBasicMaterial({ color: 0xb0562b, depthTest: false }));
    dot.position.copy(p);
    dot.renderOrder = 999;
    m.group.add(dot);
    if (m.pts.length === 2) {
      const [a, b] = m.pts;
      const mk = (pts, color, dashed) => {
        const g = new THREE.BufferGeometry().setFromPoints(pts);
        const mt = dashed ? new THREE.LineDashedMaterial({ color, dashSize: 0.08, gapSize: 0.06, depthTest: false }) : new THREE.LineBasicMaterial({ color, depthTest: false });
        const l = new THREE.Line(g, mt);
        if (dashed) l.computeLineDistances();
        l.renderOrder = 998;
        m.group.add(l);
      };
      mk([a, b], 0xb0562b, false);
      const dy = b.y - a.y;
      if (Math.abs(dy) > 0.05) {
        const c = new THREE.Vector3(b.x, a.y, b.z);
        mk([a, c, b], 0x5f6b73, true);
      }
    }
    this._updateHint();
    return true;
  }

  _updateMeasureLabel() {
    const m = this.meas;
    if (!m?.label) return;
    if (!m.on || m.pts.length < 2) { m.label.style.display = 'none'; return; }
    const [a, b] = m.pts;
    const mid = a.clone().add(b).multiplyScalar(0.5).project(this.camera);
    if (mid.z > 1) { m.label.style.display = 'none'; return; }
    const el = this.renderer.domElement;
    const f = (v) => v.toFixed(2).replace('.', ',');
    const d = a.distanceTo(b), dy = Math.abs(b.y - a.y), dh = Math.hypot(b.x - a.x, b.z - a.z);
    m.label.textContent = dy > 0.05 && dh > 0.05 ? `${f(d)} m  ·  vodoravno ${f(dh)}  ·  visina ${f(dy)}` : `${f(d)} m`;
    m.label.style.left = ((mid.x + 1) / 2) * el.clientWidth + 'px';
    m.label.style.top = ((1 - mid.y) / 2) * el.clientHeight + 'px';
    m.label.style.display = 'block';
  }

  setMode(mode) {
    if (mode === this.mode) return;
    queueMicrotask(() => this._applyNight());
    if (this.mode === 'orbit') this.savedOrbit = { pos: this.camera.position.clone(), target: this.orbit.target.clone() };
    if (this.fpv.isLocked) this.fpv.unlock();
    this.keys.clear();
    if (mode === 'walk' || mode === 'third') {
      this.orbit.enabled = false;
      const from = this.mode;
      this.mode = mode;
      if (mode === 'third' && from === 'walk') {
        const d = new THREE.Vector3();
        this.camera.getWorldDirection(d);
        this._placeAvatar(this.camera.position.x, this.camera.position.z, Math.atan2(d.x, d.z));
      } else if (mode === 'walk' && from === 'third') {
        this.camera.position.set(this.tp.x, EYE + this.fy, this.tp.z);
        this.camera.quaternion.setFromEuler(new THREE.Euler(-0.05, this.tp.heading + Math.PI, 0, 'YXZ'));
        this._emitPose(true);
      } else {
        this._spawn();
      }
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
    this.avatar.root.visible = mode === 'third';
    this.camera.fov = mode === 'walk' ? 72 : mode === 'third' ? 62 : 60;
    this.camera.updateProjectionMatrix();
    this._applyVisibility();
    this._updateHint();
    this._updateSelectionHelper();
  }

  walkTo(x, y) {
    if (this.mode === 'orbit') this.setMode('walk');
    if (this.mode === 'third') {
      const v = this._bestView(x, y);
      this._placeAvatar(v.x, v.z, Math.atan2(v.dx, v.dz));
    } else {
      this._placeViewer(x, y);
    }
    this._emitPose(true);
  }

  // najbolje mjesto i smjer pogleda oko točke (najduži slobodan pogled)
  _bestView(x, z) {
    let best = { d: -1, dx: 0, dz: -1 };
    for (let i = 0; i < 16; i++) {
      const a = (i / 16) * Math.PI * 2;
      const dx = Math.sin(a), dz = -Math.cos(a);
      const d = this._rayDist(x, z, dx, dz);
      if (d > best.d) best = { d, dx, dz };
    }
    const back = Math.min(1.6, Math.max(0, this._rayDist(x, z, -best.dx, -best.dz) - 0.5));
    return { x: x - best.dx * back, z: z - best.dz * back, dx: best.dx, dz: best.dz };
  }

  _placeAvatar(x, z, heading) {
    Object.assign(this.tp, { x, z, heading, yaw: heading + Math.PI, speed: 0 });
    this.avatar.root.position.set(x, this.fy, z);
    this.avatar.root.rotation.y = heading;
    this._thirdCamera(1, true);
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
    this.camera.position.set(x, EYE + this.fy, z);
    this.camera.up.set(0, 1, 0);
    this.camera.quaternion.setFromEuler(new THREE.Euler(-0.08, Math.atan2(-best.dx, -best.dz), 0, 'YXZ'));
  }

  frame() {
    // kadriraj zgradu (zidove); ako zidova nema, sve objekte
    const b = this._bounds(true);
    const w = b.max.x - b.min.x, d = b.max.z - b.min.z;
    const size = Math.max(w, d, 6);
    const c = new THREE.Vector3((b.min.x + b.max.x) / 2, this.fy, (b.min.z + b.max.z) / 2);
    this.orbit.target.copy(c);
    const r = 0.5 * Math.hypot(w, d) + 2;
    const vfov = THREE.MathUtils.degToRad(this.camera.fov);
    const hfov = 2 * Math.atan(Math.tan(vfov / 2) * this.camera.aspect);
    const dist = (r / Math.sin(Math.min(vfov, hfov) / 2)) * 0.9;
    const dir = new THREE.Vector3(0.42, 0.62, 0.72).normalize();
    this.camera.position.copy(c).addScaledVector(dir, dist);
    this.camera.lookAt(c);
    this.center = c;
    this.extent = Math.max(size, this._bounds(false).max.distanceTo(this._bounds(false).min) / 1.4);
    this.setTime(this.time);
  }

  setTime(h) {
    this.time = h;
    // sunce: izlazi u 6, zalazi u 20; izvan toga je ispod obzora (noć)
    const t = (h - 6) / 14;
    const elevDeg = 62 * Math.sin(Math.PI * t);
    const elev = THREE.MathUtils.degToRad(Math.max(3, elevDeg));
    const az = Math.PI * clamp(t, 0, 1);
    const dir = new THREE.Vector3(Math.cos(elev) * Math.cos(az), Math.sin(elev), Math.cos(elev) * Math.sin(az));
    // noć: 0 danju, 1 kad je sunce ~8° ispod obzora
    const night = clamp((2 - elevDeg) / 10, 0, 1);
    this.night = night;
    const skyDir = new THREE.Vector3(Math.cos(az), Math.sin(THREE.MathUtils.degToRad(elevDeg)), Math.sin(az)).normalize();
    this.sky.material.uniforms.sunPosition.value.copy(night > 0 ? skyDir : dir);
    const c = this.center || new THREE.Vector3();
    const warm = new THREE.Color(0xffb27a), white = new THREE.Color(0xfff4e6), moon = new THREE.Color(0x9fb4ff);
    const k = clamp(Math.sin(elev) / Math.sin(THREE.MathUtils.degToRad(35)), 0, 1);
    if (night > 0) {
      // mjesečina s istoka-jugoistoka
      const md = new THREE.Vector3(-0.4, 0.75, 0.5).normalize();
      this.sun.position.copy(c).addScaledVector(night > 0.5 ? md : dir, 60);
    } else {
      this.sun.position.copy(c).addScaledVector(dir, 60);
    }
    this.sun.target.position.copy(c);
    this.sun.color.copy(warm).lerp(white, k).lerp(moon, night);
    this.sun.intensity = (0.8 + 2.2 * k) * (1 - night) + 0.22 * night;
    this.hemi.intensity = (0.25 + 0.35 * k) * (1 - night) + 0.05 * night;
    this.hemi.color.set(0xdfeeff).lerp(new THREE.Color(0x3a4a70), night);
    this.scene.environmentIntensity = 0.45 * (1 - night) + 0.04 * night;
    this.scene.fog.color.set(0xcfdbe3).lerp(new THREE.Color(0x0d1524), night);
    const half = Math.max(20, (this.extent || 20) * 0.9);
    const sc = this.sun.shadow.camera;
    Object.assign(sc, { left: -half, right: half, top: half, bottom: -half });
    sc.updateProjectionMatrix();
    this.renderer.toneMappingExposure = (0.75 + 0.25 * k) * (1 - night) + 1.05 * night;
    // zvijezde
    if (!this.stars) {
      const pts = [];
      const rr = rnd(99);
      for (let i = 0; i < 1500; i++) {
        const u = rr() * Math.PI * 2, v = Math.acos(rr() * 0.95);
        pts.push(Math.sin(v) * Math.cos(u) * 800, Math.cos(v) * 800, Math.sin(v) * Math.sin(u) * 800);
      }
      const g = new THREE.BufferGeometry();
      g.setAttribute('position', new THREE.Float32BufferAttribute(pts, 3));
      this.stars = new THREE.Points(g, new THREE.PointsMaterial({ color: 0xffffff, size: 1.6, sizeAttenuation: false, transparent: true, opacity: 0, fog: false, depthWrite: false }));
      this.scene.add(this.stars);
    }
    this.stars.material.opacity = clamp((night - 0.4) / 0.6, 0, 1) * 0.9;
    this.stars.visible = night > 0.4;
    this._applyNight();
  }

  // noću svijetle prozori, ulična rasvjeta i prozori susjeda
  _applyNight() {
    const n = this.night || 0;
    const glass = mat(0, { glass: true });
    glass.emissive = glass.emissive || new THREE.Color();
    glass.emissive.set(0xffcf8f);
    glass.emissiveIntensity = this.mode === 'orbit' ? 0.55 * n : 0;
    for (const { m, e, op } of this.nightMats || []) {
      m.emissiveIntensity = e * n;
      if (op !== undefined) {
        m.opacity = op * n;
        m.visible = n > 0.05;
      }
    }
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
    if (!this.raycaster.ray.intersectPlane(new THREE.Plane(new THREE.Vector3(0, 1, 0), -this.fy), p)) return null;
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
    } else if (this.mode === 'third') {
      text = touch
        ? (this.touch.move || this.touch.look ? '' : 'Lijevi palac za hodanje, desni za okretanje kamere.')
        : 'Klikni u prikaz, pa W A S D za hodanje (Shift trčanje). Povuci mišem za okretanje kamere, kotačić za udaljenost.';
    } else if (touch) {
      text = this.touch.move || this.touch.look ? '' : 'Lijevi palac za hodanje, desni za gledanje okolo.';
    } else if (!this.fpv.isLocked) {
      text = 'Klikni u prikaz za šetnju. W A S D za hodanje, Shift za trčanje, Esc za izlaz.';
    }
    if (this.meas?.on) {
      const n = this.meas.pts.length;
      const how = touch ? 'Dodirni' : this.mode === 'walk' ? 'Klikni (križić)' : 'Klikni';
      text = n === 1 ? `Mjerenje: ${how.toLowerCase()} drugu točku.` : `Mjerenje: ${how.toLowerCase()} prvu točku (zid, pod, namještaj).`;
    } else if (this.aim && this.mode !== 'orbit') {
      text = touch ? `Dodirni – ${this.aim}` : this.mode === 'walk' ? `E ili klik – ${this.aim}` : `E – ${this.aim}`;
    } else if (this.mode === 'orbit' && !touch && text) {
      text += ' Dvoklik otvara vrata, prozore i ormare.';
    }
    this.hint.textContent = text;
    this.hint.style.display = text ? 'block' : 'none';
    this.cross.style.display = this.mode === 'walk' && this.fpv.isLocked ? 'block' : 'none';
  }

  _bounds(structureOnly = false) {
    const p = this.plan || {};
    const b = new THREE.Box3();
    let any = false;
    const add = (x, z) => {
      if (!any) { b.min.set(x, 0, z); b.max.set(x, 0, z); any = true; } else b.expandByPoint(new THREE.Vector3(x, 0, z));
    };
    for (const n of Object.values(p.nodes || {})) add(n.x, n.y);
    if (!(structureOnly && any)) for (const it of p.items || []) {
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
    this.wallMeshes = [];
    this.itemGroups.clear();
    this.wallGroups.clear();
    this.levelGroups = [];
    this.inters = [];
    this.selHelper = null;
  }

  _rebuild() {
    this._clearWorld();
    lampBudget = 12;
    const p = this.plan;
    if (!p) return;
    this.roofClip = [];
    this._tgt = this.world;
    if (p.roof && p.roofLevel) this._buildRoofs({ outlines: p.roofLevel.outlines }, p.roofLevel.y, { ...(p.roofStyle || {}), attic: p.roofLevel.attic });
    this._roofUniforms();
    // ostale etaže (samo za prikaz, bez odabira i sudara)
    for (const L of p.others || []) {
      const g = new THREE.Group();
      g.position.y = L.elevation || 0;
      this.world.add(g);
      this._tgt = g;
      this._passive = true;
      this._buildLevel(L);
      this.levelGroups.push({ g, above: (L.elevation || 0) > this.fy + 0.01 });
    }
    // aktivna etaža
    const lv = new THREE.Group();
    lv.position.y = this.fy;
    this.world.add(lv);
    this._tgt = lv;
    this._passive = false;
    this._buildLevel(p);
    this._tgt = this.world;
    this._passive = false;
    this._buildSite(p.site, p.projectId);
    this._applyVisibility();
    this._updateSelectionHelper();
  }

  _buildLevel(p) {
    const nodes = p.nodes || {};
    this._attic = p.attic ? { knee: p.kneeWall || 1.2, y: p.elevation || 0 } : null;
    // smjerovi zidova iz svakog čvora
    const dirs = {};
    for (const w of p.walls || []) {
      const A = nodes[w.a], B = nodes[w.b];
      if (!A || !B) continue;
      const ang = Math.atan2(B.y - A.y, B.x - A.x);
      (dirs[w.a] ||= []).push({ w, ang, T: w.thickness || 0.2 });
      (dirs[w.b] ||= []).push({ w, ang: ang + Math.PI, T: w.thickness || 0.2 });
    }
    // produžetak kraja zida u čvor: samo na kutu/T-spoju, i to do lica poprečnog zida (−2 mm)
    const ext = (w, nodeId, ang) => {
      const others = (dirs[nodeId] || []).filter((d) => d.w !== w);
      let collinear = null, cross = 0;
      for (const d of others) {
        const sn = Math.abs(Math.sin(d.ang - ang));
        if (sn < 0.2 && Math.cos(d.ang - ang) < 0) collinear = d.w;
        else if (sn >= 0.2) cross = Math.max(cross, d.T / 2 / sn);
      }
      // ravni nastavak: jedan od dvaju zidova uđe 1,5 mm u drugi (bez pukotine na spoju)
      if (collinear) return String(w.id) < String(collinear.id) ? 0.0015 : 0;
      if (!cross) return 0;
      return Math.max(0, cross - 0.002);
    };
    let maxH = p.wallHeight || 2.6;
    for (const w of p.walls || []) {
      maxH = Math.max(maxH, w.height || 2.6);
      const A = nodes[w.a], B = nodes[w.b];
      const ang = A && B ? Math.atan2(B.y - A.y, B.x - A.x) : 0;
      this._buildWall(w, nodes, { ea: ext(w, w.a, ang), eb: ext(w, w.b, ang + Math.PI) }, (p.openings || []).filter((o) => o.wallId === w.id));
    }
    this._buildFloors(p, nodes, maxH);
    // tlocrtni obrisi i balkoni – namještaj unutra stoji na gotovom podu (+3 cm)
    const outs = (p.outlines || []).filter((o) => o.length >= 3).map((o) => o.map(([x, y]) => ({ x, y })));
    const balconies = (p.items || []).filter((q) => BALCONY.has(q.shape));
    const onFloor = (it) => {
      if (BALCONY.has(it.shape)) return true;
      if (outs.some((o) => inPolygon(it.x, it.y, o))) return true;
      return balconies.some((q) => { const l = toLocal(q, it.x, it.y); return Math.abs(l.x) <= q.w / 2 && Math.abs(l.z) <= q.d / 2; });
    };
    const surfaces = (p.items || []).filter((q) => SURFACES.has(q.shape));
    for (let it of p.items || []) {
      if (it.shape === 'roof_window') { this._roofWindow(it, p); continue; }
      if (CEILING.has(it.shape) || it.shape === 'ac_indoor' || it.shape === 'wood_stove' || it.shape === 'drain_stack') it = { ...it, ceil: maxH - FLOOR };
      if (it.shape === 'table_lamp') {
        // stolna lampa stoji na stolu/komodi ispod sebe
        let elev = 0;
        for (const q of surfaces) {
          const l = toLocal(q, it.x, it.y);
          if (Math.abs(l.x) <= q.w / 2 && Math.abs(l.z) <= q.d / 2) elev = Math.max(elev, q.shape === 'kitchen' || q.shape === 'island' ? 0.9 : q.h);
        }
        it = { ...it, elev };
      }
      const g = new THREE.Group();
      g.position.set(it.x, onFloor(it) ? FLOOR : 0, it.y);
      g.rotation.y = -(it.rotation || 0);
      if (!this._passive) {
        g.userData = { kind: 'item', id: it.id, data: it };
        this.itemGroups.set(it.id, g);
      }
      buildItem(it, g, this.loader);
      this._tgt.add(g);
      if (g.userData.inter) this._register(it.id, [g], g.userData.inter, g.userData.parts || []);
      if (!this._passive) this._itemColliders(it);
    }
  }

  // krovni prozor: okvir i staklo u ravnini krova iznad mjesta prozora (prati nagib plohe)
  _roofWindow(it, p) {
    const R = this._roofPlaneAt(it.x, it.y);
    const base = p.elevation || 0;
    const g = new THREE.Group();
    if (!this._passive) {
      g.userData = { kind: 'item', id: it.id, data: it };
      this.itemGroups.set(it.id, g);
    }
    const w = it.w || 0.78, d = it.d || 1.18;
    if (!R || Math.hypot(R.A, R.B) < 1e-3) {
      // nema kosog krova iznad: samo oznaka na stropu
      const m = new THREE.Mesh(new THREE.BoxGeometry(w, 0.02, d), mat(0xdfe9ef, { emissive: 0xdfe9ef, emissiveIntensity: 0.3 }));
      g.position.set(it.x, (p.wallHeight || 2.6) - 0.01, it.y);
      g.rotation.y = -(it.rotation || 0);
      g.add(m);
      this._tgt.add(g);
      return;
    }
    const n = new THREE.Vector3(-R.A, 1, -R.B).normalize();
    const xAx = new THREE.Vector3(-R.B, 0, R.A).normalize(); // vodoravno, okomito na pad
    const zAx = new THREE.Vector3().crossVectors(xAx, n).normalize(); // uz pad
    g.matrixAutoUpdate = true;
    g.quaternion.setFromRotationMatrix(new THREE.Matrix4().makeBasis(xAx, n, zAx));
    g.position.set(it.x, R.y - base, it.y);
    const frameMat = mat(it.color ?? 0xff5a5f63, { roughness: 0.5, metalness: 0.3 });
    const glass = new THREE.MeshPhysicalMaterial({ color: 0x6f8fa6, roughness: 0.05, metalness: 0.2, transparent: true, opacity: 0.55, envMapIntensity: 1.5 });
    const fr = 0.07;
    const bar = (bw, bd, x, z, y = 0.05, h = 0.1) => {
      const m = new THREE.Mesh(new THREE.BoxGeometry(bw, h, bd), frameMat);
      m.position.set(x, y, z);
      m.castShadow = true;
      g.add(m);
    };
    // vanjski okvir (malo iznad pokrova) i opšav
    bar(w, fr, 0, -d / 2 + fr / 2);
    bar(w, fr, 0, d / 2 - fr / 2);
    bar(fr, d - 2 * fr, -w / 2 + fr / 2, 0);
    bar(fr, d - 2 * fr, w / 2 - fr / 2, 0);
    const gl = new THREE.Mesh(new THREE.BoxGeometry(w - 2 * fr, 0.012, d - 2 * fr), glass);
    gl.position.y = 0.07;
    g.add(gl);
    // unutra: svijetla špaleta kroz debljinu krova i „nebo” na kosom stropu
    if (this._attic) {
      const lining = mat(0xf7f5f0, { roughness: 0.9, double: true });
      const depth = 0.2;
      for (const [bw, bd, x, z] of [[w, 0.02, 0, -d / 2], [w, 0.02, 0, d / 2], [0.02, d, -w / 2, 0], [0.02, d, w / 2, 0]]) {
        const m = new THREE.Mesh(new THREE.BoxGeometry(bw, depth, bd), lining);
        m.position.set(x, -depth / 2 - 0.005, z);
        g.add(m);
      }
      const sky = new THREE.Mesh(new THREE.PlaneGeometry(w - 0.04, d - 0.04), mat(0xcfe3f2, { emissive: 0xcfe3f2, emissiveIntensity: this.night ? 0.05 : 0.9, double: true }));
      sky.rotation.x = -Math.PI / 2;
      sky.position.y = -depth - 0.006;
      g.add(sky);
      // ručka na donjem rubu
      const hd = new THREE.Mesh(new THREE.BoxGeometry(w * 0.4, 0.03, 0.03), frameMat);
      hd.position.set(0, -depth - 0.03, d / 2 - 0.06);
      g.add(hd);
    }
    this._tgt.add(g);
  }

  // sudari u šetnji: namještaj (orijentirani pravokutnik) i ograde balkona
  _itemColliders(it) {
    const sh = it.shape;
    if (['rug', 'rug_round', 'path', 'deck', 'carport', 'wall_lamp', 'table_lamp'].includes(sh) || STAIRS.has(sh) || CEILING.has(sh) || ELECTRIC.has(sh) || sh === 'ac_indoor' || sh === 'boiler') return;
    if (sh === 'lamp_arc') {
      // samo baza blokira prolaz (luk je iznad glave)
      const r = it.rotation || 0;
      const bz = -it.d / 2 + 0.18;
      this.colliders.push({ obb: true, cx: it.x - Math.sin(r) * bz, cz: it.y + Math.cos(r) * bz, hw: 0.19, hd: 0.19, ux: { x: Math.cos(r), z: Math.sin(r) }, uz: { x: -Math.sin(r), z: Math.cos(r) } });
      return;
    }
    const r = it.rotation || 0;
    const ux = { x: Math.cos(r), z: Math.sin(r) }, uz = { x: -Math.sin(r), z: Math.cos(r) };
    const W = (x, z) => ({ x: it.x + ux.x * x + uz.x * z, z: it.y + ux.z * x + uz.z * z });
    if (BALCONY.has(sh)) {
      const t = sh === 'balcony_wall' ? 0.06 : 0.03;
      const pts = [W(-it.w / 2 + t, -it.d / 2), W(-it.w / 2 + t, it.d / 2 - t), W(it.w / 2 - t, it.d / 2 - t), W(it.w / 2 - t, -it.d / 2)];
      for (let i = 0; i < 3; i++) this.colliders.push({ ax: pts[i].x, az: pts[i].z, bx: pts[i + 1].x, bz: pts[i + 1].z, r: t });
      return;
    }
    if ((it.h || 0) < 0.12) return;
    const trunk = sh === 'tree' || sh === 'umbrella' || sh === 'cypress';
    this.colliders.push({ obb: true, cx: it.x, cz: it.y, hw: trunk ? 0.12 : it.w / 2, hd: trunk ? 0.12 : it.d / 2, ux, uz });
  }

  _applyVisibility() {
    const showAbove = this.mode === 'orbit' && this.showAll;
    let hiddenAbove = false;
    for (const L of this.levelGroups) {
      L.g.visible = !L.above || showAbove;
      if (L.above && !showAbove) hiddenAbove = true;
    }
    for (const c of this.ceilings) c.visible = this.mode === 'walk' && !hiddenAbove ? true : this.mode === 'walk';
    for (const r of this.roofs) r.visible = this.mode !== 'third' && !hiddenAbove;
    // podrum se izvana ne vidi ispod trave
    if (this.ground) this.ground.visible = !(this.mode === 'orbit' && this.fy < -0.1);
    if (this.siteGroup) this.siteGroup.visible = this.ground.visible;
  }

  _buildWall(w, nodes, ends, openings) {
    const A = nodes[w.a], B = nodes[w.b];
    if (!A || !B) return;
    const dx = B.x - A.x, dz = B.y - A.y;
    const L = Math.hypot(dx, dz);
    if (L < 0.01) return;
    const ang = Math.atan2(dz, dx);
    const T = w.thickness || 0.2;
    let H = w.height || 2.6;
    // potkrovlje: svi zidovi idu do krova i režu se njegovom plohom – unutarnji do kosog stropa
    // (20 cm ispod pokrova), vanjski do pokrova (zabat je tako pravi zid, s prozorima do vrha)
    let roofOff = null;
    if (this._attic && (this.roofClip || []).some((R) => R.type !== 'flat')) {
      roofOff = (w.inside || 0) !== 0 ? -0.01 : -0.2;
      H = Math.max(H, this._roofTopOver(A, B) - this._attic.y + 0.05);
    } else if (this._attic && (w.inside || 0) !== 0) H = this._attic.knee;
    const clipCache = new Map();
    const cl = (m) => {
      if (roofOff == null || !m) return m;
      if (!clipCache.has(m)) clipCache.set(m, roofCut(m.clone(), roofOff));
      return clipCache.get(m);
    };
    const ea = ends.ea, eb = ends.eb;
    const g = new THREE.Group();
    g.position.set(A.x, 0, A.y);
    g.rotation.y = -ang;
    g.userData = this._passive ? { L, H, T, ea, eb } : { kind: 'wall', id: w.id, L, H, T, ea, eb };

    // strana interijera: +1 (lokalni +z), -1 (lokalni -z), 0 (unutarnji zid)
    const side = w.inside || 0;
    const paint = mat(w.color, { roughness: 0.92 });
    const facade = mat(0xece7df, { tex: 'plaster', roughness: 0.95 });
    const top = mat(0xd9d6d0, { roughness: 1 });
    // strane zida: obloga prostorije (pločice, drvo…) do visine h, iznad boja prostorije
    const sides = w.sides || {};
    const sideMats = (si, fallback) => {
      if (!si) return { lo: fallback, hi: fallback, h: 0 };
      const hi = mat(si.paint ?? w.color, { roughness: 0.92 });
      if (!si.tex && si.color == null) return { lo: hi, hi, h: 0 };
      const tiled = si.tex && /Tile/.test(si.tex);
      const lo = mat(si.color ?? 0xffffffff, { tex: si.tex, roughness: tiled ? 0.35 : 0.8 });
      return si.h > 0 && si.h < H - 0.01 ? { lo, hi, h: si.h } : { lo, hi: lo, h: 0 };
    };
    const P = sideMats(sides.p, side === -1 ? facade : paint);
    const N = sideMats(sides.n, side === 1 ? facade : paint);
    const faces = [paint, paint, top, paint, P.hi, N.hi];
    const bands = [...new Set([P.h, N.h].filter((h) => h > 0))].sort((a, b) => a - b);
    const facesAt = (yMid) => [paint, paint, top, paint, P.h && yMid < P.h ? P.lo : P.hi, N.h && yMid < N.h ? N.lo : N.hi];

    const box = (x0, x1, y0, y1, material = faces, depth = T, z = 0, parent = g) => {
      if (x1 - x0 < 0.002 || y1 - y0 < 0.002) return null;
      if (material === faces) {
        // komad zida podijeli na visinama obloga (bez preklapanja => bez treperenja)
        const cuts = [y0, ...bands.filter((h) => h > y0 + 0.005 && h < y1 - 0.005), y1];
        let last = null;
        for (let i = 0; i + 1 < cuts.length; i++) {
          const a = cuts[i], b = cuts[i + 1];
          const geo = new THREE.BoxGeometry(x1 - x0, b - a, depth);
          scaleBoxUV(geo, x1 - x0, b - a, depth, x0, a);
          const m = new THREE.Mesh(geo, facesAt((a + b) / 2).map(cl));
          m.position.set((x0 + x1) / 2, (a + b) / 2, z);
          m.castShadow = true;
          m.receiveShadow = true;
          parent.add(m);
          if (!this._passive) this.wallMeshes.push(m);
          last = m;
        }
        return last;
      }
      const m = new THREE.Mesh(new THREE.BoxGeometry(x1 - x0, y1 - y0, depth), Array.isArray(material) ? material.map(cl) : cl(material));
      m.position.set((x0 + x1) / 2, (y0 + y1) / 2, z);
      m.castShadow = true;
      m.receiveShadow = true;
      parent.add(m);
      if (!this._passive && !Array.isArray(material)) this.wallMeshes.push(m);
      return m;
    };
    const ops = openings.map((o) => ({ ...o, s: o.t * L - o.width / 2, e: o.t * L + o.width / 2 })).sort((a, b) => a.s - b.s);
    const solids = [];
    const gaps = [];
    let cur = -ea;
    let solidStart = -ea;
    const frameMat = mat(0xf7f7f5, { roughness: 0.5 });
    const glassMat = mat(0, { glass: true });
    const sideN0 = side === 0 ? 1 : side;
    for (const o of ops) {
      const s = Math.max(o.s, cur), e = Math.min(o.e, L + eb);
      if (e <= s) continue;
      box(cur, s, 0, H);
      const topY = Math.min(o.sill + o.height, H);
      box(s, e, topY, H);
      const W = e - s;
      const low = o.sill < 0.3;
      let I = null;
      if (o.type === 'window' || o.type === 'balcony') {
        if (o.sill > 0) {
          box(s, e, 0, o.sill - 0.04);
          box(s, e, o.sill - 0.04, o.sill, frameMat, T + 0.05); // klupčica
        }
        // fiksni okvir
        const fd = 0.08;
        box(s, s + 0.05, o.sill, topY, frameMat, fd);
        box(e - 0.05, e, o.sill, topY, frameMat, fd);
        box(s + 0.05, e - 0.05, topY - 0.05, topY, frameMat, fd);
        const y0 = o.sill + (o.sill > 0 ? 0 : 0.03), y1 = topY - 0.05;
        if (o.sill <= 0) box(s + 0.05, e - 0.05, 0, 0.03, frameMat, fd); // prag
        const x0 = s + 0.05, x1 = e - 0.05;
        const style = o.style || '';
        const sf = 0.055;
        const sash = (pv, lx0, lx1, hx) => {
          box(lx0, lx0 + sf, y0, y1, frameMat, 0.06, 0, pv);
          box(lx1 - sf, lx1, y0, y1, frameMat, 0.06, 0, pv);
          box(lx0 + sf, lx1 - sf, y0, y0 + sf, frameMat, 0.06, 0, pv);
          box(lx0 + sf, lx1 - sf, y1 - sf, y1, frameMat, 0.06, 0, pv);
          box(lx0 + sf, lx1 - sf, y0 + sf, y1 - sf, glassMat, 0.012, 0, pv);
          if (hx !== null) {
            const hy = o.type === 'balcony' ? 1.05 : (y0 + y1) / 2;
            box(hx - 0.01, hx + 0.01, hy - 0.08, hy + 0.04, mat(0xd9d9d9, { metalness: 0.6, roughness: 0.3 }), 0.02, sideN0 * 0.045, pv);
          }
        };
        const noun = o.type === 'balcony' ? 'balkonska vrata' : 'prozor';
        if (style === 'fixed') {
          const pv = new THREE.Group();
          g.add(pv);
          sash(pv, x0, x1, null);
        } else if (style === 'sliding') {
          // dva krila u dvije ravnine; jedno klizi preko drugoga
          const half = (x1 - x0) / 2;
          const a = new THREE.Group(), b2 = new THREE.Group();
          a.position.set(x0, 0, -0.03);
          b2.position.set(x0 + half - 0.03, 0, 0.03);
          g.add(a, b2);
          sash(a, 0, half + 0.03, half - 0.02);
          sash(b2, 0, half + 0.03, 0.04);
          I = this._register(o.id, [a, b2], { noun, def: 0 }, [{ o: b2, prop: 'px', delta: -(half - 0.08) }]);
        } else {
          const n = o.type === 'balcony' ? 2 : Math.max(1, Math.round(W / 0.9));
          const pw = (x1 - x0) / n;
          const sashes = [], partsW = [];
          for (let i = 0; i < n; i++) {
            const hingeRight = n > 1 && i >= n / 2;
            const dir = hingeRight ? -1 : 1;
            const pv = new THREE.Group();
            pv.position.set(hingeRight ? x0 + (i + 1) * pw : x0 + i * pw, 0, 0);
            g.add(pv);
            const lx0 = Math.min(0, dir * pw), lx1 = Math.max(0, dir * pw);
            sash(pv, lx0, lx1, dir > 0 ? lx1 - 0.035 : lx0 + 0.035);
            sashes.push(pv);
            partsW.push({ o: pv, prop: 'ry', delta: -dir * sideN0 * 1.25 });
          }
          I = this._register(o.id, sashes, { noun, def: 0 }, partsW);
        }
      } else {
        box(s, s + 0.04, 0, topY, frameMat, T + 0.02);
        box(e - 0.04, e, 0, topY, frameMat, T + 0.02);
        box(s + 0.04, e - 0.04, topY - 0.04, topY, frameMat, T + 0.02);
        if (o.sill > 0) box(s, e, 0, o.sill);
        if (o.type === 'door') {
          let sideN = sideN0;
          if (o.swingOut) sideN = -sideN;
          const style = o.style || '';
          const leafMat = mat(0xece6dc, { roughness: 0.55 });
          const hm = mat(0x8a8a8a, { metalness: 0.7, roughness: 0.3 });
          const LH = topY - 0.05;
          // krilo širine lw u grupi pv; ide od x=0 u smjeru dir; kvaka blizu slobodnog ruba
          const leaf = (pv, lw, dir, z = sideN * 0.02, handle = true) => {
            const m = new THREE.Mesh(new THREE.BoxGeometry(lw, LH, 0.04), leafMat);
            m.position.set((dir * lw) / 2, LH / 2, z);
            m.castShadow = true;
            pv.add(m);
            if (handle) {
              for (const sz of [-1, 1]) {
                const h = new THREE.Mesh(new THREE.BoxGeometry(0.12, 0.02, 0.02), hm);
                h.position.set(dir * (lw - 0.08), 1.02, z + sz * 0.045);
                pv.add(h);
              }
            }
          };
          const W2 = Math.max(0.2, W - 0.09);
          if (style === 'double') {
            const a = new THREE.Group(), b2 = new THREE.Group();
            a.position.set(s + 0.045, 0, sideN * (T / 2 - 0.03));
            b2.position.set(e - 0.045, 0, sideN * (T / 2 - 0.03));
            leaf(a, W2 / 2 - 0.003, 1);
            leaf(b2, W2 / 2 - 0.003, -1);
            g.add(a, b2);
            I = this._register(o.id, [a, b2], { noun: 'vrata', def: 1 }, [
              { o: a, prop: 'ry', delta: -sideN * 1.4 },
              { o: b2, prop: 'ry', delta: sideN * 1.4 },
            ]);
          } else if (style === 'sliding' || style === 'pocket') {
            // klizna: po licu zida (s vodilicom) ili u zid
            const toE = !!o.flip;
            const pv = new THREE.Group();
            const z = style === 'sliding' ? sideN * (T / 2 + 0.035) : 0;
            const lw = style === 'sliding' ? W + 0.06 : W2;
            pv.position.set(toE ? e + (style === 'sliding' ? 0.03 : -0.045) : s - (style === 'sliding' ? 0.03 : -0.045), 0, z);
            leaf(pv, lw, toE ? -1 : 1, 0);
            g.add(pv);
            if (style === 'sliding') {
              const rail = new THREE.Mesh(new THREE.BoxGeometry(2 * W + 0.1, 0.05, 0.05), hm);
              const rx = toE ? e - W + 0.03 : s + W - 0.03;
              rail.position.set(rx, LH + 0.03, sideN * (T / 2 + 0.035));
              g.add(rail);
            }
            I = this._register(o.id, [pv], { noun: 'vrata', def: 1 }, [{ o: pv, prop: 'px', delta: (toE ? 1 : -1) * (lw - (style === 'sliding' ? 0.1 : 0.05)) }]);
          } else if (style === 'folding') {
            const hingeAtE = !!o.flip;
            const dir = hingeAtE ? -1 : 1;
            const a = new THREE.Group();
            a.position.set(hingeAtE ? e - 0.045 : s + 0.045, 0, sideN * (T / 2 - 0.03));
            leaf(a, W2 / 2, dir, sideN * 0.02, false);
            const b2 = new THREE.Group();
            b2.position.set((dir * W2) / 2, 0, 0);
            leaf(b2, W2 / 2, dir, sideN * 0.02);
            a.add(b2);
            g.add(a);
            const d1 = -dir * sideN * 1.35;
            I = this._register(o.id, [a, b2], { noun: 'vrata', def: 1 }, [
              { o: a, prop: 'ry', delta: d1 },
              { o: b2, prop: 'ry', delta: -2 * d1 },
            ]);
          } else {
            const hingeAtE = !!o.flip;
            const pivot = new THREE.Group();
            pivot.position.set(hingeAtE ? e - 0.045 : s + 0.045, 0, sideN * (T / 2 - 0.03));
            leaf(pivot, W2, hingeAtE ? -1 : 1);
            g.add(pivot);
            I = this._register(o.id, [pivot], { noun: 'vrata', def: 1 }, [{ o: pivot, prop: 'ry', delta: hingeAtE ? sideN * 1.4 : -sideN * 1.4 }]);
          }
        }
      }
      if (I) {
        // nevidljiva ploha u otvoru – cilj za klik ili tipku E
        const proxy = new THREE.Mesh(new THREE.BoxGeometry(W, Math.max(0.1, topY - o.sill), T + 0.04), frameMat);
        proxy.position.set((s + e) / 2, (o.sill + topY) / 2, 0);
        proxy.visible = false;
        proxy.userData.inter = I;
        g.add(proxy);
      }
      if (low) {
        solids.push([solidStart, s]);
        solidStart = e;
        if (I) gaps.push([s, e, I]);
      }
      cur = Math.max(cur, e);
    }
    box(cur, L + eb, 0, H);
    solids.push([solidStart, L + eb]);
    if (roofOff != null) g.traverse((o) => { if (o.isMesh && o.material?.userData?.roofOff != null) o.customDepthMaterial = roofDepth(roofOff); });
    this._tgt.add(g);
    if (this._passive) return;
    this.wallGroups.set(w.id, g);
    const ux = dx / L, uz = dz / L;
    for (const [s0, s1] of solids) {
      if (s1 - s0 < 0.01) continue;
      this.colliders.push({ ax: A.x + ux * s0, az: A.y + uz * s0, bx: A.x + ux * s1, bz: A.y + uz * s1, r: T / 2 });
    }
    // zatvorena vrata i balkonska vrata ne propuštaju
    for (const [s0, s1, I] of gaps) {
      this.colliders.push({ ax: A.x + ux * s0, az: A.y + uz * s0, bx: A.x + ux * s1, bz: A.y + uz * s1, r: 0.05, inter: I });
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
    const toPts = (h) => h.map(([x, y]) => ({ x, y }));
    const inPoly = (x, y, poly) => {
      let c = false;
      for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
        const a = poly[i], b = poly[j];
        if ((a.y > y) !== (b.y > y) && x < ((b.x - a.x) * (y - a.y)) / (b.y - a.y) + a.x) c = !c;
      }
      return c;
    };
    let curPts = null;
    const withHoles = (shape, holes) => {
      for (const h of holes || []) if (!curPts || inPoly(h.reduce((a, q) => a + q[0], 0) / h.length, h.reduce((a, q) => a + q[1], 0) / h.length, curPts)) shape.holes.push(new THREE.Path(toPts(h).map((q) => new THREE.Vector2(q.x, -q.y))));
      return shape;
    };
    const mk = (pts, material, y, opts = {}) => {
      curPts = pts;
      const geo = new THREE.ShapeGeometry(withHoles(this._shapeFrom(pts), opts.holes)).rotateX(-Math.PI / 2);
      const m = new THREE.Mesh(geo, material);
      m.position.y = y;
      m.receiveShadow = true;
      if (opts.ceiling) this.ceilings.push(m);
      if (opts.userData && !this._passive) m.userData = opts.userData;
      this._tgt.add(m);
      return m;
    };
    const elev = this._tgt === this.world ? 0 : this._tgt.position.y;
    for (const o of p.outlines || []) {
      if (o.length < 3) continue;
      const pts = o.map(([x, y]) => ({ x, y }));
      if (Math.abs(elev) <= 0.05) mk(pts, slabMat, 0.004, { holes: p.holes });
      else {
        // međukatna ploča (25 cm) – vidi se izvana između etaža; otvor za stubište
        curPts = pts;
        const geo = new THREE.ExtrudeGeometry(withHoles(this._shapeFrom(pts), p.holes), { depth: 0.25 - 0.006, bevelEnabled: false }).rotateX(-Math.PI / 2);
        const m = new THREE.Mesh(geo, mat(0xd8d2c8, { tex: 'plaster', roughness: 0.95 }));
        m.position.y = -0.25 + 0.004; // dno 4 mm iznad stropa etaže ispod, vrh 2 mm ispod poda
        m.castShadow = true;
        m.receiveShadow = true;
        this._tgt.add(m);
      }
    }
    for (const r of p.rooms || []) {
      const pts = (r.nodeIds || []).map((id) => nodes[id]).filter(Boolean);
      if (pts.length < 3) continue;
      mk(pts, mat(r.floorColor, { tex: r.floorTexture, roughness: r.floorTexture === 'wood' ? 0.82 : 0.86, env: 0.3, double: true }), 0.03,
        { userData: { kind: 'room', id: r.id }, holes: p.holes });
      if (!this._passive && !p.attic) mk(pts, mat(0xfbfaf8, { double: true, roughness: 1 }), maxH, { ceiling: true, holes: p.ceilHoles });
    }
  }

  // ------------------------------------------------------------------ parcela i okolina
  // Sve je u koordinatama „uz ulicu” (a) i „prema ulici” (o): rub parcele prema ulici je na o = e.
  _buildSite(site, seedKey) {
    this.siteGroup = null;
    this.nightMats = [];
    if (!site || !site.rect) {
      this.ground.material = mat(0xa9bb92, { tex: 'grass', roughness: 1 });
      return;
    }
    const G = new THREE.Group();
    this.world.add(G);
    this.siteGroup = G;
    const [x0, y0, x1, y1] = site.rect;
    const N = { S: [0, 1], N: [0, -1], E: [1, 0], W: [-1, 0] }[site.street] || [0, 1];
    const T = [-N[1], N[0]]; // smjer uz ulicu
    const toW = (a, o) => ({ x: T[0] * a + N[0] * o, z: T[1] * a + N[1] * o });
    const toA = (x, z) => ({ a: T[0] * x + T[1] * z, o: N[0] * x + N[1] * z });
    const corners = [toA(x0, y0), toA(x1, y0), toA(x1, y1), toA(x0, y1)];
    const a0 = Math.min(...corners.map((c) => c.a)), a1 = Math.max(...corners.map((c) => c.a));
    const oB = Math.min(...corners.map((c) => c.o)), e = Math.max(...corners.map((c) => c.o));
    const hb = site.house;
    const hc = [toA(hb[0], hb[1]), toA(hb[2], hb[1]), toA(hb[2], hb[3]), toA(hb[0], hb[3])];
    const hFront = Math.max(...hc.map((c) => c.o));
    const hMid = (Math.min(...hc.map((c) => c.a)) + Math.max(...hc.map((c) => c.a))) / 2;
    const door = site.door ? toA(site.door[0], site.door[1]) : null;
    const gateA = clamp(door ? door.a : hMid, a0 + 2.5, a1 - 2.5);
    const r = rnd(Array.from(String(seedKey || 'p')).reduce((h, ch) => (h * 31 + ch.charCodeAt(0)) >>> 0, 7));
    const ang = Math.atan2(T[1], T[0]);

    // pravokutnik u (a, o) na visini y
    const slab = (A0, A1, O0, O1, y, h, m, cast = false) => {
      const w = A1 - A0, d = O1 - O0;
      if (w <= 0 || d <= 0) return null;
      const geo = new THREE.BoxGeometry(w, h, d);
      scaleBoxUV(geo, w, h, d);
      // UV gornje plohe u metrima svijeta (teksture se ne rastežu)
      const msh = new THREE.Mesh(geo, m);
      const c = toW((A0 + A1) / 2, (O0 + O1) / 2);
      msh.position.set(c.x, y + h / 2, c.z);
      msh.rotation.y = -ang;
      msh.receiveShadow = true;
      msh.castShadow = cast;
      G.add(msh);
      return msh;
    };
    const env = site.env || 'suburb';
    const meadow = env === 'city' ? 0x9aa58a : 0xb2b98d;
    this.ground.material = mat(env === 'none' ? 0xa9bb92 : meadow, { tex: 'grass', roughness: 1 });

    // travnjak parcele
    slab(a0, a1, oB, e, -0.012, 0.01, mat(0x8db567, { tex: 'lawn', roughness: 1 }));
    // pločnik, rubnjak, cesta, pločnik preko
    const L = 400;
    const walk = mat(0xc9c5bc, { tex: 'paving', roughness: 0.9 });
    const road = mat(0x55585b, { tex: 'asphalt', roughness: 0.95 });
    slab(-L, L, e, e + 2, -0.01, 0.12, walk);
    slab(-L, L, e + 2, e + 2.15, -0.01, 0.14, mat(0xb9b6ae, { roughness: 0.9 }));
    slab(-L, L, e + 2.15, e + 9.15, -0.01, 0.02, road);
    for (let a = -L; a < L; a += 6) slab(a, a + 3, e + 5.6, e + 5.72, 0.012, 0.002, mat(0xf2f2f0, { roughness: 0.6 }));
    slab(-L, L, e + 9.15, e + 9.3, -0.01, 0.14, mat(0xb9b6ae, { roughness: 0.9 }));
    slab(-L, L, e + 9.3, e + 11.3, -0.01, 0.12, walk);
    // prilaz od ulice do kuće (do ulaznih vrata, ako ih ima)
    if (site.driveway) {
      const dA = door ? door.a : gateA;
      const end = door ? door.o + 0.15 : hFront;
      if (end < e) {
        slab(gateA - 1.6, gateA + 1.6, Math.max(end, e - 6), e, -0.01, 0.025, mat(0xbdb8ae, { tex: 'paving', roughness: 0.9 }));
        if (door && Math.abs(dA - gateA) > 1.6) {
          // staza od prilaza do vrata
          const lo = Math.min(dA, gateA), hi = Math.max(dA, gateA);
          slab(lo - 0.6, hi + 0.6, end, end + 1.2, -0.01, 0.028, mat(0xbdb8ae, { tex: 'paving', roughness: 0.9 }));
        }
        if (end < e - 6) slab(dA - 0.6, dA + 0.6, end, e - 6 + 0.01, -0.01, 0.028, mat(0xbdb8ae, { tex: 'paving', roughness: 0.9 }));
        // upušteni rubnjak na ulazu
        slab(gateA - 1.6, gateA + 1.6, e, e + 2.15, -0.01, 0.125, mat(0xbdb8ae, { tex: 'paving', roughness: 0.9 }));
      }
    }

    // ograda po rubu parcele (s ulazom na strani ulice)
    if (site.fence && site.fence !== 'none') {
      const fh = clamp(site.fenceH || 1.2, 0.4, 2.2);
      const edges = [
        [[a0, e], [gateA - 2.2, e]],
        [[gateA + 2.2, e], [a1, e]],
        [[a1, e], [a1, oB]],
        [[a1, oB], [a0, oB]],
        [[a0, oB], [a0, e]],
      ];
      for (const [[pa, po], [qa, qo]] of edges) this._fence(G, toW(pa, po), toW(qa, qo), site.fence, fh);
      // stupovi ulaza
      for (const ga of [gateA - 2.2, gateA + 2.2]) {
        const c = toW(ga, e);
        const post = new THREE.Mesh(new THREE.BoxGeometry(0.3, fh + 0.2, 0.3), mat(0xd8d2c8, { tex: 'plaster', roughness: 0.95 }));
        post.position.set(c.x, (fh + 0.2) / 2, c.z);
        post.castShadow = true;
        G.add(post);
      }
    }

    // ulična rasvjeta
    const poleMat = mat(0x3a3d40, { metalness: 0.5, roughness: 0.5 });
    const headMat = new THREE.MeshStandardMaterial({ color: 0xf6f2e8, emissive: 0xffd9a0, emissiveIntensity: 0 });
    this.nightMats.push({ m: headMat, e: 2.2 });
    for (let a = Math.floor(a0 / 24) * 24 - 72; a < a1 + 72; a += 24) {
      const c = toW(a, e + 1.6);
      const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.06, 0.08, 5, 8), poleMat);
      pole.position.set(c.x, 2.5, c.z);
      G.add(pole);
      const arm = toW(a, e + 2.4);
      const head = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.08, 0.22), headMat);
      head.position.set(arm.x, 4.95, arm.z);
      head.rotation.y = -ang;
      G.add(head);
    }

    if (env === 'none') return;
    // drveće (instancirano)
    const trees = [];
    const free = (a, o) => !(a > a0 - 1 && a < a1 + 1 && o > oB - 1 && o < e + 12);
    const lotW = 22;
    // susjedstvo: kuće lijevo i desno uz ulicu i preko ceste
    const houses = [];
    if (env === 'suburb' || env === 'countryside') {
      const gap = env === 'suburb' ? 0 : 14;
      const depth = Math.max(18, e - oB);
      for (const dir of [-1, 1]) {
        let a = dir < 0 ? a0 - gap : a1 + gap;
        for (let k = 0; k < (env === 'suburb' ? 4 : 2); k++) {
          const w = lotW + r() * 6;
          const la0 = dir < 0 ? a - w : a, la1 = dir < 0 ? a : a + w;
          houses.push({ a0: la0, a1: la1, o0: e - depth, o1: e, front: e });
          a = dir < 0 ? la0 - (env === 'suburb' ? 0 : 20 + r() * 30) : la1 + (env === 'suburb' ? 0 : 20 + r() * 30);
        }
      }
      if (env === 'suburb') {
        for (let a = a0 - 70 + r() * 6; a < a1 + 70; a += lotW + r() * 6) houses.push({ a0: a, a1: a + lotW, o0: e + 11.3, o1: e + 11.3 + depth, front: e + 11.3, across: true });
      } else {
        for (let i = 0; i < 3; i++) {
          const a = a0 - 60 + r() * (a1 - a0 + 120);
          houses.push({ a0: a, a1: a + 24, o0: e + 30 + r() * 30, o1: e + 60 + r() * 20, front: e + 30, across: true, farm: true });
        }
      }
      for (const h of houses) this._neighbor(G, h, toW, ang, r, env, trees, free);
      if (env === 'countryside') {
        // polja
        const cols = [0xc9b66a, 0x9db86b, 0xb58e5a, 0x8fae5c];
        for (let i = 0; i < 8; i++) {
          const fa = a0 - 150 + r() * 300, fo = r() < 0.5 ? oB - 40 - r() * 120 : e + 40 + r() * 120;
          const fw = 40 + r() * 60, fd = 30 + r() * 50;
          if (!free(fa, fo)) continue;
          const f = slab(fa, fa + fw, fo, fo + fd, -0.011, 0.005, mat(cols[i % cols.length], { tex: 'field', roughness: 1 }));
          if (f) f.rotation.y += (r() - 0.5) * 0.3;
        }
      }
    }
    if (env === 'city') {
      // stambene zgrade uokolo
      const facade = mat(0xe3ddd3, { tex: 'facadeWin', roughness: 0.9 });
      const blocks = [];
      for (let a = a0 - 90; a < a1 + 90; a += 34) blocks.push([a, e + 14, 26, 14 + r() * 6]);
      for (const dir of [-1, 1]) for (let k = 0; k < 2; k++) blocks.push([dir < 0 ? a0 - 6 - 30 * (k + 1) : a1 + 6 + 30 * k, oB - 4, 24, e - oB - 2]);
      for (let a = a0 - 60; a < a1 + 60; a += 36) blocks.push([a, oB - 40, 28, 16]);
      for (const [ba, bo, bw, bd] of blocks) {
        const h = 9 + Math.floor(r() * 5) * 3;
        const m = slab(ba, ba + bw, bo, bo + bd, 0, h, facade, true);
        if (m) {
          const win = new THREE.MeshStandardMaterial({ color: 0x2b3640, emissive: 0xffc98a, emissiveIntensity: 0, transparent: true, opacity: 0.0 });
          this.nightMats.push({ m: win, e: 0.6, op: 0.55 });
          const glow = m.clone();
          glow.material = win;
          glow.scale.set(1.004, 0.98, 1.004);
          G.add(glow);
        }
      }
    }
    // stabla po okolici i drvored uz ulicu
    const n = env === 'city' ? 40 : env === 'countryside' ? 260 : 120;
    for (let i = 0; i < n; i++) {
      const a = a0 - 160 + r() * (a1 - a0 + 320), o = oB - 160 + r() * (e - oB + 320);
      if (!free(a, o) || (o > e - 1 && o < e + 12)) continue;
      if (houses.some((h) => a > h.a0 + 2 && a < h.a1 - 2 && o > h.front - 16 && o < h.front + 16 && o > Math.min(h.o0, h.o1) && o < Math.max(h.o0, h.o1))) continue;
      trees.push([a, o, 0.8 + r() * 0.9, r()]);
    }
    for (let a = a0 - 70; a < a1 + 70; a += 12) if (Math.abs(a - gateA) > 4) trees.push([a + r() * 2, e + 10.3, 0.75 + r() * 0.2, r(), true]);
    this._trees(G, trees.map(([a, o, s, k, st]) => ({ ...toW(a, o), s, k, st })));
    // brda u daljini
    const hills = new THREE.Group();
    const hm = mat(0x7f9a74, { roughness: 1 });
    const cx = (x0 + x1) / 2, cz = (y0 + y1) / 2;
    for (let i = 0; i < 26; i++) {
      const t = (i / 26) * Math.PI * 2 + r() * 0.2;
      const R = 250 + r() * 100, rad = 70 + r() * 80, h = 14 + r() * 34;
      const hill = new THREE.Mesh(new THREE.SphereGeometry(1, 16, 8, 0, Math.PI * 2, 0, Math.PI / 2), hm);
      hill.position.set(cx + Math.cos(t) * R, -1, cz + Math.sin(t) * R);
      hill.scale.set(rad, h, rad * (0.6 + r() * 0.6));
      hill.rotation.y = r() * 3;
      hills.add(hill);
    }
    G.add(hills);
    this._applyNight();
  }

  _fence(G, p, q, type, fh) {
    const dx = q.x - p.x, dz = q.z - p.z, len = Math.hypot(dx, dz);
    if (len < 0.2) return;
    const ang = Math.atan2(dz, dx);
    const grp = new THREE.Group();
    grp.position.set(p.x, 0, p.z);
    grp.rotation.y = -ang;
    G.add(grp);
    const box = (w, h, d, x, y, z, m, cast = true) => {
      const geo = new THREE.BoxGeometry(w, h, d);
      scaleBoxUV(geo, w, h, d, x - w / 2, y - h / 2);
      const b = new THREE.Mesh(geo, m);
      b.position.set(x, y, z);
      b.castShadow = cast;
      b.receiveShadow = true;
      grp.add(b);
      return b;
    };
    if (type === 'hedge') {
      box(len, fh, 0.7, len / 2, fh / 2, 0, mat(0x4d7436, { tex: 'carpet', roughness: 1 }));
      return;
    }
    if (type === 'wall') {
      box(len, fh, 0.2, len / 2, fh / 2, 0, mat(0xe6e0d6, { tex: 'plaster', roughness: 0.95 }));
      box(len + 0.04, 0.05, 0.26, len / 2, fh + 0.025, 0, mat(0xb9b3a8, { tex: 'stone', roughness: 0.8 }));
      return;
    }
    const n = Math.max(1, Math.round(len / 2.2));
    const step = len / n;
    const postMat = type === 'wood' ? mat(0x7a5a3e, { roughness: 0.8 }) : mat(type === 'panel' ? 0x2f5a3a : 0x2e3236, { metalness: 0.4, roughness: 0.5 });
    for (let i = 0; i <= n; i++) box(0.08, fh + 0.05, 0.08, i * step, (fh + 0.05) / 2, 0, postMat);
    if (type === 'wood') {
      box(len, fh - 0.08, 0.025, len / 2, (fh - 0.08) / 2 + 0.05, 0.05, mat(0xa77d55, { tex: 'woodPanel', roughness: 0.85 }));
    } else if (type === 'panel') {
      const m = mat(0x2f5a3a, { roughness: 0.6, opacity: 0.45 });
      m.depthWrite = false;
      box(len, fh - 0.05, 0.01, len / 2, fh / 2, 0, m, false);
    } else {
      box(len, 0.04, 0.04, len / 2, fh - 0.05, 0, postMat);
      box(len, 0.04, 0.04, len / 2, 0.12, 0, postMat);
      const bars = Math.floor(len / 0.12);
      const geo = new THREE.BoxGeometry(0.02, fh - 0.15, 0.02);
      const inst = new THREE.InstancedMesh(geo, postMat, bars);
      const m4 = new THREE.Matrix4();
      for (let i = 0; i < bars; i++) {
        m4.makeTranslation((i + 0.5) * (len / bars), (fh - 0.15) / 2 + 0.07, 0);
        inst.setMatrixAt(i, m4);
      }
      inst.castShadow = true;
      grp.add(inst);
    }
  }

  // jednostavna susjedna kuća na svojoj parceli
  _neighbor(G, h, toW, ang, r, env, trees, free) {
    const lotW = h.a1 - h.a0;
    const w = Math.min(lotW - 6, 9 + r() * 4), d = 8 + r() * 3.5;
    const floors = h.farm ? 1 : r() < 0.45 ? 2 : 1;
    const H = floors * 2.9;
    const am = (h.a0 + h.a1) / 2 + (r() - 0.5) * (lotW - w - 6);
    const setback = 5 + r() * 3;
    const oc = h.across ? h.front + setback + d / 2 : h.front - setback - d / 2;
    const c = toW(am, oc);
    const grp = new THREE.Group();
    grp.position.set(c.x, 0, c.z);
    grp.rotation.y = -ang;
    G.add(grp);
    const walls = [0xf1ebe0, 0xe8dcc7, 0xdfe3e0, 0xf3e6d8, 0xd9cdbd, 0xece7df][Math.floor(r() * 6)];
    const roofC = [0xa5533a, 0x8c3b2a, 0x5e4033, 0x3f4347][Math.floor(r() * 4)];
    const body = new THREE.Mesh(new THREE.BoxGeometry(w, H, d), mat(walls, { tex: 'plaster', roughness: 0.95 }));
    scaleBoxUV(body.geometry, w, H, d);
    body.position.y = H / 2;
    body.castShadow = body.receiveShadow = true;
    grp.add(body);
    // prozori (noću svijetle)
    const win = new THREE.MeshStandardMaterial({ color: 0x33404b, roughness: 0.2, emissive: 0xffcf8f, emissiveIntensity: 0 });
    this.nightMats.push({ m: win, e: 0.9 * (0.4 + r() * 0.6) });
    for (let f = 0; f < floors; f++) {
      for (let i = 0; i < Math.floor(w / 2.6); i++) {
        const x = -w / 2 + 1.3 + i * ((w - 2.6) / Math.max(1, Math.floor(w / 2.6) - 1));
        for (const sz of [-1, 1]) {
          const m = new THREE.Mesh(new THREE.BoxGeometry(1.1, 1.3, 0.04), win);
          m.position.set(x, f * 2.9 + 1.55, sz * (d / 2 + 0.02));
          grp.add(m);
        }
      }
    }
    // dvostrešni krov
    const pitch = 0.6, ov = 0.5;
    const rise = (d / 2 + ov) * pitch;
    const shape = new THREE.Shape([new THREE.Vector2(-d / 2 - ov, 0), new THREE.Vector2(d / 2 + ov, 0), new THREE.Vector2(0, rise)]);
    const roof = new THREE.Mesh(new THREE.ExtrudeGeometry(shape, { depth: w + 2 * ov, bevelEnabled: false }), mat(roofC, { tex: 'roof', roughness: 0.85 }));
    roof.rotation.y = Math.PI / 2;
    roof.position.set(-w / 2 - ov, H - ov * pitch, 0);
    roof.castShadow = true;
    grp.add(roof);
    // vrt: drvo ili dva
    for (let k = 0; k < 2; k++) {
      const ta = h.a0 + 2 + r() * (lotW - 4);
      const to = h.across ? h.front + setback + d + 3 + r() * 6 : h.front - setback - d - 3 - r() * 6;
      if (free(ta, to)) trees.push([ta, to, 0.8 + r() * 0.6, r()]);
    }
    // živica uz ulicu
    if (env === 'suburb' && r() < 0.7) {
      const p = toW(h.a0 + 0.5, h.front + (h.across ? 0.5 : -0.5)), q = toW(h.a1 - 4.5, h.front + (h.across ? 0.5 : -0.5));
      this._fence(G, p, q, r() < 0.5 ? 'hedge' : 'wood', 1.1);
    }
  }

  _trees(G, list) {
    if (!list.length) return;
    const trunkGeo = new THREE.CylinderGeometry(0.12, 0.18, 1, 6);
    const crownGeo = new THREE.IcosahedronGeometry(1, 1);
    const coneGeo = new THREE.ConeGeometry(1, 1, 8);
    const trunks = new THREE.InstancedMesh(trunkGeo, mat(0x5e4a36, { roughness: 1 }), list.length);
    const crowns = new THREE.InstancedMesh(crownGeo, mat(0xffffff, { roughness: 1 }), list.length);
    const cones = new THREE.InstancedMesh(coneGeo, mat(0x3e5f34, { roughness: 1 }), list.length);
    const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), sc = new THREE.Vector3(), pos = new THREE.Vector3();
    const col = new THREE.Color();
    let nc = 0, nk = 0;
    list.forEach((t, i) => {
      const s = t.s * 4;
      const conifer = !t.st && t.k > 0.75;
      m4.compose(pos.set(t.x, s * 0.25, t.z), q.identity(), sc.set(s * 0.12, s * 0.5, s * 0.12));
      trunks.setMatrixAt(i, m4);
      if (conifer) {
        m4.compose(pos.set(t.x, s * 0.25 + s * 0.55, t.z), q.identity(), sc.set(s * 0.32, s * 1.2, s * 0.32));
        cones.setMatrixAt(nk++, m4);
      } else {
        q.setFromEuler(new THREE.Euler(0, t.k * 6, 0));
        m4.compose(pos.set(t.x, s * 0.5 + s * 0.3, t.z), q, sc.set(s * 0.42, s * 0.38, s * 0.42));
        crowns.setMatrixAt(nc, m4);
        crowns.setColorAt(nc++, col.setHSL(0.25 + t.k * 0.07, 0.45 + t.k * 0.2, 0.17 + t.k * 0.08));
      }
    });
    crowns.count = nc;
    cones.count = nk;
    for (const m of [trunks, crowns, cones]) {
      m.castShadow = true;
      m.receiveShadow = true;
      G.add(m);
    }
  }

  // ------------------------------------------------------------------ krov
  // Krov prati obris zgrade: pravokutni (i zakrenuti) obrisi rastave se na najveće pravokutnike
  // koji se preklapaju; svaki dobije svoje krovne plohe, a njihova presjecišta daju uvale (L, T, U kuće).
  _buildRoofs(p, maxH, style = {}) {
    const type = style.type || 'gable';
    const t = Math.tan(THREE.MathUtils.degToRad(clamp(style.pitch || 30, 5, 60)));
    const ov = clamp(style.overhang ?? 0.5, 0, 1.5);
    const color = style.color ? rgb(style.color) : 0xa5533a;
    const WT = 0.15; // pola debljine vanjskog zida (obris je po osi zida)
    const roofMat = roofCut(mat(color, { tex: 'roof', roughness: 0.85 }).clone(), 0, 1);
    const innerMat = roofCut(mat(0xf7f5f0, { roughness: 0.95, side: 'back' }).clone(), -0.2, 1);
    const fasciaMat = mat(darker(color, 0.35), { roughness: 0.8 });
    const wallMat = mat(0xece7df, { tex: 'plaster', roughness: 0.95, double: true });

    for (const o of p.outlines || []) {
      if (o.length < 3) continue;
      const poly = o.map(([x, y]) => ({ x, y }));
      // glavni smjer: najdulji brid
      let ang = 0, best = 0;
      for (let i = 0; i < poly.length; i++) {
        const a = poly[i], b = poly[(i + 1) % poly.length];
        const l = Math.hypot(b.x - a.x, b.y - a.y);
        if (l > best) { best = l; ang = Math.atan2(b.y - a.y, b.x - a.x); }
      }
      const ca = Math.cos(ang), sa = Math.sin(ang);
      const toL = (q) => ({ x: q.x * ca + q.y * sa, y: -q.x * sa + q.y * ca });
      const toW = (u, v) => ({ x: u * ca - v * sa, z: u * sa + v * ca });
      const lp = poly.map(toL);
      const rectilinear = lp.every((a, i) => {
        const b = lp[(i + 1) % lp.length];
        const dx = Math.abs(b.x - a.x), dy = Math.abs(b.y - a.y);
        return Math.min(dx, dy) < 0.03 * Math.max(dx, dy, 1e-6) + 0.005;
      });
      const inside = (u, v) => inPolygon(u, v, lp);

      // pravokutnici (u lokalnim koordinatama, po osi zida)
      let rects = [];
      if (rectilinear) rects = this._rectCover(lp);
      if (!rects.length) {
        let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
        for (const q of lp) { x0 = Math.min(x0, q.x); x1 = Math.max(x1, q.x); y0 = Math.min(y0, q.y); y1 = Math.max(y1, q.y); }
        rects = [{ x0, x1, y0, y1 }];
      }
      // stranice na obrisu dobivaju prepust; unutarnje (ispod susjednog krila) ne
      const exterior = (r, side) => {
        const n = 8;
        for (let k = 0; k <= n; k++) {
          const f = 0.02 + (0.96 * k) / n;
          let u, v;
          if (side === 'x0') { u = r.x0 - 0.2; v = r.y0 + (r.y1 - r.y0) * f; }
          else if (side === 'x1') { u = r.x1 + 0.2; v = r.y0 + (r.y1 - r.y0) * f; }
          else if (side === 'y0') { v = r.y0 - 0.2; u = r.x0 + (r.x1 - r.x0) * f; }
          else { v = r.y1 + 0.2; u = r.x0 + (r.x1 - r.x0) * f; }
          if (inside(u, v)) return false;
        }
        return true;
      };
      // ravnine krova: H = a·u + b·v + c (visina iznad vrha zida)
      let all = [];
      let ux0 = Infinity, ux1 = -Infinity, vy0 = Infinity, vy1 = -Infinity;
      for (const r of rects) { ux0 = Math.min(ux0, r.x0); ux1 = Math.max(ux1, r.x1); vy0 = Math.min(vy0, r.y0); vy1 = Math.max(vy1, r.y1); }
      const shedAlongV = (vy1 - vy0 <= ux1 - ux0) !== !!style.turn;
      rects.forEach((r0, idx) => {
        const r = { x0: r0.x0 - WT, x1: r0.x1 + WT, y0: r0.y0 - WT, y1: r0.y1 + WT };
        const e = { x0: exterior(r0, 'x0') ? ov : 0, x1: exterior(r0, 'x1') ? ov : 0, y0: exterior(r0, 'y0') ? ov : 0, y1: exterior(r0, 'y1') ? ov : 0 };
        const ext = { x0: r.x0 - e.x0, x1: r.x1 + e.x1, y0: r.y0 - e.y0, y1: r.y1 + e.y1 };
        const longU = (r.x1 - r.x0 >= r.y1 - r.y0) !== !!style.turn;
        const planes = [];
        const lower = idx * 0.004; // krila na istoj visini ne smiju biti koplanarna (treperenje)
        if (type === 'shed') {
          if (shedAlongV) planes.push({ a: 0, b: -t, c: (vy1 + WT) * t - lower });
          else planes.push({ a: -t, b: 0, c: (ux1 + WT) * t - lower });
        } else {
          if (longU || type === 'hip') {
            planes.push({ a: 0, b: t, c: -r.y0 * t - lower }); // prednja
            planes.push({ a: 0, b: -t, c: r.y1 * t - lower }); // stražnja
          }
          if (!longU || type === 'hip') {
            planes.push({ a: t, b: 0, c: -r.x0 * t - lower });
            planes.push({ a: -t, b: 0, c: r.x1 * t - lower });
          }
        }
        all.push({ r, ext, planes });
      });
      if (type === 'shed') {
        // jedna ravnina preko cijele zgrade => jedan poligon (bez preklapanja)
        const pl = all[0].planes[0];
        all = [{ r: null, ext: { x0: ux0 - WT - ov, x1: ux1 + WT + ov, y0: vy0 - WT - ov, y1: vy1 + WT + ov }, planes: [pl], poly: this._offsetPoly(lp, WT + ov) }];
      }

      this.roofClip.push({ ca, sa, base: maxH, all, type });
      const g = new THREE.Group();
      g.position.y = maxH;
      const pos = [], uvs = [];
      const H = (pl, u, v) => pl.a * u + pl.b * v + pl.c;
      const addPoly = (pts, pl) => {
        // pts: lokalni [u, v] konveksnog ili jednostavnog poligona
        if (pts.length < 3) return;
        const tri = THREE.ShapeUtils.triangulateShape(pts.map(([u, v]) => new THREE.Vector2(u, v)), []);
        const nrm = Math.hypot(pl.a, pl.b) || 1;
        const du = -pl.a / nrm, dv = -pl.b / nrm; // smjer pada (za teksturu)
        for (const [i0, i1, i2] of tri) {
          // trokut mora gledati prema gore (vanjska ploha krova); inače zamijeni redoslijed
          const P = (k) => { const [u, v] = pts[k]; const w = toW(u, v); return new THREE.Vector3(w.x, H(pl, u, v), w.z); };
          const p0 = P(i0), p1 = P(i1), p2 = P(i2);
          const up = p1.clone().sub(p0).cross(p2.clone().sub(p0)).y >= 0;
          for (const k of up ? [i0, i1, i2] : [i0, i2, i1]) {
            const [u, v] = pts[k];
            const w = toW(u, v);
            pos.push(w.x, H(pl, u, v), w.z);
            const s = Math.hypot(1, Math.hypot(pl.a, pl.b));
            uvs.push((u * dv - v * du), (u * du + v * dv) * s);
          }
        }
      };
      const fascia = [];
      // je li rub ove plohe ispod krova drugog krila (unutar L/T spoja)
      const underOther = (u, v, pl) => {
        const h = H(pl, u, v);
        for (const R of all) {
          if (R.poly || u < R.ext.x0 - 1e-6 || u > R.ext.x1 + 1e-6 || v < R.ext.y0 - 1e-6 || v > R.ext.y1 + 1e-6) continue;
          let m = Infinity;
          for (const q of R.planes) m = Math.min(m, H(q, u, v));
          if (m > h + 0.01) return true;
        }
        return false;
      };
      for (const R of all) {
        for (let i = 0; i < R.planes.length; i++) {
          let pts = R.poly ? R.poly.map((q) => [q.x, q.y]) : [[R.ext.x0, R.ext.y0], [R.ext.x1, R.ext.y0], [R.ext.x1, R.ext.y1], [R.ext.x0, R.ext.y1]];
          const pi = R.planes[i];
          for (let j = 0; j < R.planes.length; j++) {
            if (j === i) continue;
            const pj = R.planes[j];
            // zadrži dio gdje je pi niža (pi − pj ≤ 0)
            pts = clipPoly(pts, (u, v) => H(pi, u, v) - H(pj, u, v) - 1e-9);
          }
          addPoly(pts, pi);
          // čeone daske uz rub krova (strehe i zabati)
          for (let k = 0; k < pts.length; k++) {
            const a = pts[k], b = pts[(k + 1) % pts.length];
            const onEdge = (q) => R.poly ? true : Math.abs(q[0] - R.ext.x0) < 1e-6 || Math.abs(q[0] - R.ext.x1) < 1e-6 || Math.abs(q[1] - R.ext.y0) < 1e-6 || Math.abs(q[1] - R.ext.y1) < 1e-6;
            const sameSide = R.poly ? true : (Math.abs(a[0] - b[0]) < 1e-6 && (Math.abs(a[0] - R.ext.x0) < 1e-6 || Math.abs(a[0] - R.ext.x1) < 1e-6)) || (Math.abs(a[1] - b[1]) < 1e-6 && (Math.abs(a[1] - R.ext.y0) < 1e-6 || Math.abs(a[1] - R.ext.y1) < 1e-6));
            if (onEdge(a) && onEdge(b) && sameSide) {
              // daska samo na dijelovima koji nisu ispod drugog krila
              const len = Math.hypot(b[0] - a[0], b[1] - a[1]);
              const n = Math.max(1, Math.ceil(len / 0.1));
              let start = null;
              for (let q = 0; q <= n; q++) {
                const f0 = q / n, f1 = Math.min(1, (q + 1) / n);
                const fm = (f0 + f1) / 2;
                const ok = q < n && !underOther(a[0] + (b[0] - a[0]) * fm, a[1] + (b[1] - a[1]) * fm, pi);
                if (ok && start == null) start = f0;
                if (!ok && start != null) {
                  const P = (f) => [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f];
                  fascia.push([P(start), P(f0), pi]);
                  start = null;
                }
              }
            }
          }
        }
      }
      if (type !== 'flat' && pos.length) {
        const geo = new THREE.BufferGeometry();
        geo.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
        geo.setAttribute('uv', new THREE.Float32BufferAttribute(uvs, 2));
        geo.computeVertexNormals();
        const m = new THREE.Mesh(geo, roofMat);
        m.castShadow = true;
        m.receiveShadow = true;
        g.add(m);
        // donja strana: kosi strop (gips) 20 cm ispod pokrova
        const inner = new THREE.Mesh(geo, innerMat);
        inner.position.y = -0.2;
        inner.receiveShadow = true;
        g.add(inner);
        // čeone daske
        for (const [a, b, pl] of fascia) {
          const wa = toW(a[0], a[1]), wb = toW(b[0], b[1]);
          const ha = H(pl, a[0], a[1]), hb = H(pl, b[0], b[1]);
          const fg = new THREE.BufferGeometry();
          const d = 0.16;
          fg.setAttribute('position', new THREE.Float32BufferAttribute([
            wa.x, ha + 0.01, wa.z, wb.x, hb + 0.01, wb.z, wb.x, hb - d, wb.z,
            wa.x, ha + 0.01, wa.z, wb.x, hb - d, wb.z, wa.x, ha - d, wa.z,
          ], 3));
          fg.computeVertexNormals();
          const fm = new THREE.Mesh(fg, fasciaMat);
          fm.castShadow = true;
          g.add(fm);
        }
      }

      // visina krova u točki (najviša ploha iznad nje)
      const roofH = (u, v) => {
        let best = -Infinity;
        for (const R of all) {
          if (!R.poly && (u < R.ext.x0 - 1e-6 || u > R.ext.x1 + 1e-6 || v < R.ext.y0 - 1e-6 || v > R.ext.y1 + 1e-6)) continue;
          let h = Infinity;
          for (const pl of R.planes) h = Math.min(h, H(pl, u, v));
          best = Math.max(best, h);
        }
        return best;
      };

      if (type === 'flat') {
        // ravni krov: ploča s atikom
        const outer = this._offsetPoly(lp, WT + Math.min(ov, 0.25));
        const shape = new THREE.Shape(outer.map((q) => new THREE.Vector2(q.x, q.y)));
        const slab = new THREE.ExtrudeGeometry(shape, { depth: 0.22, bevelEnabled: false });
        slab.rotateX(Math.PI / 2);
        const sm = new THREE.Mesh(slab, mat(0xd8d2c8, { tex: 'plaster', roughness: 0.95 }));
        sm.position.y = 0.22;
        sm.rotation.y = -ang;
        sm.castShadow = true;
        sm.receiveShadow = true;
        const holder = new THREE.Group();
        holder.add(sm);
        g.add(holder);
        const top = this._offsetPoly(lp, WT + Math.min(ov, 0.25) - 0.02);
        const roofTop = new THREE.Shape(top.map((q) => new THREE.Vector2(q.x, q.y)));
        const inner = this._offsetPoly(lp, WT + Math.min(ov, 0.25) - 0.2);
        roofTop.holes.push(new THREE.Path(inner.map((q) => new THREE.Vector2(q.x, q.y)).reverse()));
        const parapet = new THREE.ExtrudeGeometry(roofTop, { depth: 0.45, bevelEnabled: false });
        parapet.rotateX(Math.PI / 2);
        const pm = new THREE.Mesh(parapet, mat(0xece7df, { tex: 'plaster', roughness: 0.95 }));
        pm.position.y = 0.22 + 0.45;
        pm.rotation.y = -ang;
        pm.castShadow = true;
        g.add(pm);
        // pokrov (šljunak/membrana)
        const cover = new THREE.Mesh(new THREE.ShapeGeometry(new THREE.Shape(inner.map((q) => new THREE.Vector2(q.x, q.y)))).rotateX(Math.PI / 2), mat(color, { roughness: 1 }));
        cover.position.y = 0.226;
        cover.rotation.y = -ang;
        cover.receiveShadow = true;
        g.add(cover);
      } else if (!style.attic) {
        // zabati: zid od vrha zida do krova uz svaki brid obrisa (vanjsko lice zida)
        const face = this._offsetPoly(lp, WT);
        for (let i = 0; i < face.length; i++) {
          const a = face[i], b = face[(i + 1) % face.length];
          const L = Math.hypot(b.x - a.x, b.y - a.y);
          if (L < 0.05) continue;
          const n = Math.max(2, Math.ceil(L / 0.05));
          const top = [];
          for (let k = 0; k <= n; k++) {
            const f = k / n;
            const u = a.x + (b.x - a.x) * f, v = a.y + (b.y - a.y) * f;
            top.push([f * L, Math.max(0, roofH(u, v) - 0.005)]);
          }
          if (Math.max(...top.map((q) => q[1])) < 0.02) continue;
          const sh = new THREE.Shape();
          sh.moveTo(0, 0);
          for (const [x, y] of top) sh.lineTo(x, y);
          sh.lineTo(L, 0);
          sh.closePath();
          const gm = new THREE.Mesh(new THREE.ShapeGeometry(sh), wallMat);
          const wa = toW(a.x, a.y), wb = toW(b.x, b.y);
          gm.position.set(wa.x, 0, wa.z);
          gm.rotation.y = -Math.atan2(wb.z - wa.z, wb.x - wa.x);
          gm.castShadow = true;
          gm.receiveShadow = true;
          g.add(gm);
        }
      }
      this.world.add(g);
      this.roofs.push(g);
    }
  }

  // krovne plohe u uniforme shadera za rezanje
  _roofUniforms() {
    let n = 0;
    for (const R of this.roofClip || []) {
      if (R.type === 'flat') continue;
      for (const q of R.all) {
        if (n >= ROOF_MAX) break;
        roofU.uRA.value[n].set(q.ext.x0, q.ext.x1, q.ext.y0, q.ext.y1);
        roofU.uRB.value[n].set(R.ca, R.sa, R.base, Math.min(4, q.planes.length));
        for (let k = 0; k < 4; k++) {
          const pl = q.planes[k];
          if (pl) roofU.uRP.value[n * 4 + k].set(pl.a, pl.b, pl.c, 0);
        }
        n++;
      }
    }
    roofU.uRN.value = n;
  }

  // visina pokrova (svjetska y) iznad točke; -Infinity ako tu nema kosog krova
  _roofTop(x, z) {
    let best = -Infinity;
    for (const R of this.roofClip || []) {
      if (R.type === 'flat') continue;
      const u = R.ca * x + R.sa * z, v = -R.sa * x + R.ca * z;
      for (const q of R.all) {
        if (u < q.ext.x0 - 1e-3 || u > q.ext.x1 + 1e-3 || v < q.ext.y0 - 1e-3 || v > q.ext.y1 + 1e-3) continue;
        let h = Infinity;
        for (const pl of q.planes) h = Math.min(h, pl.a * u + pl.b * v + pl.c);
        best = Math.max(best, R.base + h);
      }
    }
    return best;
  }

  // ploha krova koja vlada točkom: { y, A, B } za y = A·x + B·z + C (svjetske koordinate)
  _roofPlaneAt(x, z) {
    let best = null;
    for (const R of this.roofClip || []) {
      if (R.type === 'flat') continue;
      const u = R.ca * x + R.sa * z, v = -R.sa * x + R.ca * z;
      for (const q of R.all) {
        if (u < q.ext.x0 - 1e-3 || u > q.ext.x1 + 1e-3 || v < q.ext.y0 - 1e-3 || v > q.ext.y1 + 1e-3) continue;
        let h = Infinity, pl = null;
        for (const c of q.planes) { const hc = c.a * u + c.b * v + c.c; if (hc < h) { h = hc; pl = c; } }
        if (pl && (!best || R.base + h > best.y)) best = { y: R.base + h, A: pl.a * R.ca - pl.b * R.sa, B: pl.a * R.sa + pl.b * R.ca };
      }
    }
    return best;
  }

  // najviša točka krova iznad zida (uzorci duž zida)
  _roofTopOver(A, B) {
    let m = -Infinity;
    for (let k = 0; k <= 20; k++) {
      const f = k / 20;
      m = Math.max(m, this._roofTop(A.x + (B.x - A.x) * f, A.y + (B.y - A.y) * f));
    }
    return Number.isFinite(m) ? m : 0;
  }

  // je li točka pogotka u odrezanom (nevidljivom) dijelu zida potkrovlja
  _cutAway(h) {
    const off = h.object.material?.userData?.roofOff ?? (Array.isArray(h.object.material) ? h.object.material[0]?.userData?.roofOff : undefined);
    if (off == null) return false;
    const r = this._roofTop(h.point.x, h.point.z);
    return r > -1e4 && h.point.y > r + off;
  }

  // ravnine krova iznad točke (x, z) kao ravnine rezanja: zadrži ono ispod kosog stropa
  _roofClipAt(x, z) {
    for (const R of this.roofClip || []) {
      const u = R.ca * x + R.sa * z, v = -R.sa * x + R.ca * z;
      let rect = null;
      for (const q of R.all) {
        if (q.poly || (u >= q.ext.x0 - 1e-3 && u <= q.ext.x1 + 1e-3 && v >= q.ext.y0 - 1e-3 && v <= q.ext.y1 + 1e-3)) { rect = q; break; }
      }
      if (!rect || R.type === 'flat') continue;
      return rect.planes.map((pl) => {
        const A = pl.a * R.ca - pl.b * R.sa, B = pl.a * R.sa + pl.b * R.ca, C = R.base + pl.c - 0.2;
        return new THREE.Plane(new THREE.Vector3(A, -1, B), C).normalize();
      });
    }
    return null;
  }

  // pomak pravokutnog poligona prema van za d (lokalne koordinate)
  _offsetPoly(pts, d) {
    let area = 0;
    for (let i = 0; i < pts.length; i++) { const a = pts[i], b = pts[(i + 1) % pts.length]; area += a.x * b.y - b.x * a.y; }
    const s = area > 0 ? 1 : -1; // CCW => vanjska normala desno od smjera
    const n = pts.length, out = [];
    for (let i = 0; i < n; i++) {
      const p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n];
      const e1 = norm2(p1.x - p0.x, p1.y - p0.y), e2 = norm2(p2.x - p1.x, p2.y - p1.y);
      const n1 = { x: e1.y * s, y: -e1.x * s }, n2 = { x: e2.y * s, y: -e2.x * s };
      const bx = n1.x + n2.x, by = n1.y + n2.y;
      const bl = Math.hypot(bx, by) || 1;
      const cos = (n1.x * bx + n1.y * by) / bl;
      const k = d / Math.max(0.2, cos);
      out.push({ x: p1.x + (bx / bl) * k, y: p1.y + (by / bl) * k });
    }
    return out;
  }

  // najveći pravokutnici (koji se smiju preklapati) što zajedno pokrivaju pravokutni poligon
  _rectCover(lp) {
    const snap = (v) => Math.round(v * 100) / 100;
    const xs = [...new Set(lp.map((q) => snap(q.x)))].sort((a, b) => a - b);
    const ys = [...new Set(lp.map((q) => snap(q.y)))].sort((a, b) => a - b);
    const nx = xs.length - 1, ny = ys.length - 1;
    if (nx < 1 || ny < 1 || nx * ny > 900) return [];
    const cell = [];
    for (let i = 0; i < nx; i++) {
      cell.push([]);
      for (let j = 0; j < ny; j++) cell[i].push(inPolygon((xs[i] + xs[i + 1]) / 2, (ys[j] + ys[j + 1]) / 2, lp));
    }
    // svi maksimalni pravokutnici
    const cand = [];
    for (let j0 = 0; j0 < ny; j0++) {
      for (let j1 = j0; j1 < ny; j1++) {
        let i = 0;
        while (i < nx) {
          const ok = (ii) => { for (let j = j0; j <= j1; j++) if (!cell[ii][j]) return false; return true; };
          if (!ok(i)) { i++; continue; }
          let k = i;
          while (k + 1 < nx && ok(k + 1)) k++;
          cand.push({ i0: i, i1: k, j0, j1 });
          i = k + 1;
        }
      }
    }
    const contains = (a, b) => a.i0 <= b.i0 && a.i1 >= b.i1 && a.j0 <= b.j0 && a.j1 >= b.j1;
    const maximal = cand.filter((c) => !cand.some((d) => d !== c && contains(d, c) && !(contains(c, d))));
    const area = (c) => (xs[c.i1 + 1] - xs[c.i0]) * (ys[c.j1 + 1] - ys[c.j0]);
    // pohlepno pokrivanje: najveći doprinos nepokrivenih ćelija
    const covered = cell.map((col) => col.map(() => false));
    const out = [];
    for (let guard = 0; guard < 40; guard++) {
      let bestC = null, bestGain = 0;
      for (const c of maximal) {
        let gain = 0;
        for (let i = c.i0; i <= c.i1; i++) for (let j = c.j0; j <= c.j1; j++) if (!covered[i][j]) gain += (xs[i + 1] - xs[i]) * (ys[j + 1] - ys[j]);
        if (gain > bestGain + 1e-9 || (Math.abs(gain - bestGain) < 1e-9 && bestC && area(c) > area(bestC))) { bestGain = gain; bestC = c; }
      }
      if (!bestC || bestGain < 1e-6) break;
      for (let i = bestC.i0; i <= bestC.i1; i++) for (let j = bestC.j0; j <= bestC.j1; j++) covered[i][j] = true;
      out.push({ x0: xs[bestC.i0], x1: xs[bestC.i1 + 1], y0: ys[bestC.j0], y1: ys[bestC.j1 + 1] });
    }
    return out;
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
      if (!h.object.visible || this._cutAway(h)) continue;
      let o = h.object;
      while (o && !o.userData?.kind) o = o.parent;
      if (o && o.userData.kind) return { kind: o.userData.kind, id: o.userData.id, obj: o, point: h.point };
    }
    return null;
  }

  _groundAt(e) {
    this.raycaster.setFromCamera(this._ndc(e), this.camera);
    const p = new THREE.Vector3();
    return this.raycaster.ray.intersectPlane(new THREE.Plane(new THREE.Vector3(0, 1, 0), -this.fy), p) ? p : null;
  }

  _bindPointer() {
    const el = this.renderer.domElement;
    el.addEventListener('wheel', (e) => {
      if (this.mode !== 'third') return;
      e.preventDefault();
      this.tp.dist = clamp(this.tp.dist * Math.exp(e.deltaY / 600), 1.4, 12);
    }, { passive: false });
    el.addEventListener('pointerdown', (e) => {
      this.kbd = true;
      if (this.mode === 'third') {
        if (e.pointerType === 'touch') { this._touchStart(e); return; }
        this.tpDrag = { x: e.clientX, y: e.clientY, sx: e.clientX, sy: e.clientY, id: e.pointerId };
        try { el.setPointerCapture(e.pointerId); } catch (_) { /* ignore */ }
        return;
      }
      if (this.mode === 'walk') {
        if (e.pointerType === 'touch') { this._touchStart(e); return; }
        if (!this.fpv.isLocked) this.fpv.lock();
        else if (e.button === 0 && !this._measureAt(new THREE.Vector2(0, 0))) this._interact();
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
      if (this.mode === 'third') {
        if (e.pointerType === 'touch') { this._touchMove(e); return; }
        const d = this.tpDrag;
        if (!d) return;
        this.tp.yaw -= (e.clientX - d.x) * 0.006;
        this.tp.pitch = clamp(this.tp.pitch + (e.clientY - d.y) * 0.005, 0.05, 1.35);
        d.x = e.clientX;
        d.y = e.clientY;
        return;
      }
      if (this.mode === 'walk') { if (e.pointerType === 'touch') this._touchMove(e); return; }
      const d = this.dragItem;
      if (!d) return;
      const p = this._groundAt(e);
      if (!p) return;
      const nx = Math.round((d.start.x + p.x - d.g0.x) * 100) / 100;
      const nz = Math.round((d.start.z + p.z - d.g0.z) * 100) / 100;
      d.g.position.x = nx;
      d.g.position.z = nz;
      d.moved = true;
    });
    const up = (e) => {
      if (this.mode === 'third') {
        if (e.pointerType === 'touch') { this._touchEnd(e); return; }
        const td = this.tpDrag;
        this.tpDrag = null;
        if (td && this.meas?.on && Math.hypot(e.clientX - td.sx, e.clientY - td.sy) < 5) this._measureAt(this._ndc(e));
        return;
      }
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
      if (this._measureAt(this._ndc(e))) return;
      const hit = dn.hit;
      if (hit && (hit.kind === 'item' || hit.kind === 'wall' || hit.kind === 'room')) this.emit('select', { kind: hit.kind, id: hit.id });
      else this.emit('select', { kind: '', id: '' });
    };
    el.addEventListener('pointerup', up);
    el.addEventListener('pointercancel', up);
    el.addEventListener('contextmenu', (e) => e.preventDefault());
    el.addEventListener('dblclick', (e) => {
      if (this.mode !== 'orbit') return;
      this.raycaster.setFromCamera(this._ndc(e), this.camera);
      const I = this._interHit(this.raycaster, 80);
      if (I) this._toggle(I);
    });
  }

  _touchStart(e) {
    const r = this.renderer.domElement.getBoundingClientRect();
    const x = e.clientX - r.left, y = e.clientY - r.top;
    if (x < r.width / 2 && !this.touch.move) {
      this.touch.move = { id: e.pointerId, x, y };
      Object.assign(this.stick.style, { left: x + 'px', top: y + 'px', display: 'block' });
      Object.assign(this.knob.style, { left: x + 'px', top: y + 'px', display: 'block' });
    } else if (!this.touch.look) {
      this.touch.look = { id: e.pointerId, x, y, sx: x, sy: y, t0: performance.now(), cx: e.clientX, cy: e.clientY };
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
      if (this.mode === 'third') {
        this.tp.yaw -= dx * 0.007;
        this.tp.pitch = clamp(this.tp.pitch + dy * 0.006, 0.05, 1.35);
        return;
      }
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
    if (t.look && t.look.id === e.pointerId) {
      const L = t.look;
      t.look = null;
      if (performance.now() - L.t0 < 300 && Math.hypot(L.x - L.sx, L.y - L.sy) < 8) {
        if (this._measureAt(this._ndc({ clientX: L.cx, clientY: L.cy }))) { /* mjerenje */ }
        else if (this.mode === 'third') this._interact();
        else {
          this.raycaster.setFromCamera(this._ndc({ clientX: L.cx, clientY: L.cy }), this.camera);
          const I = this._interHit(this.raycaster, 2.8);
          if (I) this._toggle(I);
        }
      }
    }
    this._updateHint();
  }

  // ------------------------------------------------------------------ otvaranje i paljenje
  // roots: objekti čiji se pogodak računa kao ovaj element; parts: {o, prop, delta} ili {mat, emi, light, li}
  _register(id, roots, info, parts) {
    const st = this.openState.has(id) ? this.openState.get(id) : info.def || 0;
    const I = { id, noun: info.noun, light: !!info.light, t: st, target: st, parts: [] };
    for (const p of parts) {
      if (p.o) {
        const key = p.prop === 'ry' ? ['rotation', 'y'] : p.prop === 'rx' ? ['rotation', 'x'] : p.prop === 'pz' ? ['position', 'z'] : ['position', 'x'];
        I.parts.push({ ...p, key, base: p.o[key[0]][key[1]] });
      } else I.parts.push(p);
    }
    for (const r of roots) r.userData.inter = I;
    this._applyInter(I);
    if (!this._passive) this.inters.push(I);
    return I;
  }

  _applyInter(I) {
    const e = I.t < 0.5 ? 2 * I.t * I.t : 1 - Math.pow(-2 * I.t + 2, 2) / 2; // glatko
    for (const p of I.parts) {
      if (p.o) p.o[p.key[0]][p.key[1]] = p.base + p.delta * e;
      if (p.mat) p.mat.emissiveIntensity = p.emi * I.t;
      if (p.light) p.light.intensity = (p.li || 0) * I.t;
    }
  }

  _toggle(I) {
    I.target = I.target > 0.5 ? 0 : 1;
    this.openState.set(I.id, I.target);
  }

  _label(I) {
    const on = I.target > 0.5;
    if (I.light) return (on ? 'Ugasi ' : 'Upali ') + I.noun;
    return (on ? 'Zatvori ' : 'Otvori ') + I.noun;
  }

  // prvi element u smjeru zrake (zidovi i namještaj zaklanjaju)
  _interHit(ray, max) {
    ray.far = max;
    const hits = ray.intersectObjects(this.world.children, true);
    ray.far = Infinity;
    for (const h of hits) {
      let o = h.object;
      if (this._cutAway(h)) continue;
      if (!o.visible && !o.userData.inter) continue;
      let vis = true;
      for (let q = o; q; q = q.parent) if (q !== o && !q.visible) { vis = false; break; }
      if (!vis) continue;
      while (o && !o.userData.inter) o = o.parent;
      if (o) return o.userData.inter;
      if (!h.object.material?.transparent) return null; // zid ili neprozirni objekt ispred
    }
    return null;
  }

  // što je ispred promatrača (prvo lice: sredina ekrana; treće lice: najbliže ispred lika)
  _target() {
    if (this.mode === 'walk') {
      this.raycaster.setFromCamera(new THREE.Vector2(0, 0), this.camera);
      return this._interHit(this.raycaster, 2.8);
    }
    if (this.mode === 'third') {
      const tp = this.tp;
      const hx = Math.sin(tp.heading), hz = Math.cos(tp.heading);
      const o = new THREE.Vector3(tp.x - hx * 0.2, this.fy + (tp.off || 0) + 1.1, tp.z - hz * 0.2);
      let best = null;
      for (const da of [0, -0.35, 0.35, -0.7, 0.7]) {
        const a = tp.heading + da;
        this.raycaster.set(o, new THREE.Vector3(Math.sin(a), -0.15, Math.cos(a)).normalize());
        best = this._interHit(this.raycaster, 2.2);
        if (best) break;
      }
      return best;
    }
    return null;
  }

  _interact() {
    const I = this._target();
    if (I) this._toggle(I);
  }

  _animateInters(dt) {
    for (const I of this.inters) {
      if (I.t === I.target) continue;
      const step = dt * 2.6;
      I.t = I.target > I.t ? Math.min(I.target, I.t + step) : Math.max(I.target, I.t - step);
      this._applyInter(I);
    }
    // natpis „E – Otvori vrata”
    if (this.mode !== 'orbit') {
      const now = performance.now();
      if (now - this.aimAt > 120) {
        this.aimAt = now;
        const active = this.mode === 'third' || this.fpv.isLocked || this.touch.look || this.touch.move;
        const I = active ? this._target() : null;
        const label = I ? this._label(I) : '';
        if (label !== this.aim) {
          this.aim = label;
          this._updateHint();
        }
      }
    } else if (this.aim) {
      this.aim = null;
      this._updateHint();
    }
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
    if (this.mode === 'third') {
      const v = this._bestView(x, z);
      this._placeAvatar(v.x, v.z, Math.atan2(v.dx, v.dz));
    } else {
      this._placeViewer(x, z);
    }
    this._emitPose(true);
  }

  // visina stuba ispod točke (x, z) u odnosu na pod aktivne etaže; dir: +1 = vrh stubišta, −1 = dno stubišta odozgo
  _stairs(x, z) {
    const p = this.plan || {};
    const local = (it) => {
      const r = it.rotation || 0, dx = x - it.x, dz = z - it.y;
      return { lx: dx * Math.cos(r) + dz * Math.sin(r), lz: -dx * Math.sin(r) + dz * Math.cos(r) };
    };
    for (const it of p.items || []) {
      if (!STAIRS.has(it.shape)) continue;
      const { lx, lz } = local(it);
      const k = stairProgress(it, lx, lz, false); // 0 dno, 1 vrh
      if (k === null) continue;
      return { off: k * it.h, dir: p.hasAbove && k > 0.9 ? 1 : 0 };
    }
    for (const it of p.stairsBelow || []) {
      const { lx, lz } = local(it);
      const k = stairProgress(it, lx, lz, true);
      if (k === null) continue;
      const drop = (1 - k) * (it.h + 0.25);
      return { off: -drop, dir: p.hasBelow && k < 0.1 ? -1 : 0 };
    }
    return { off: 0, dir: 0 };
  }

  _stairStep(x, z) {
    const s = this._stairs(x, z);
    if (s.dir && !this._levelPending) {
      this._levelPending = true;
      setTimeout(() => (this._levelPending = false), 1500);
      this.emit('level', { dir: s.dir });
    }
    // glatko penjanje/spuštanje
    this._stairOff = this._stairOff == null ? s.off : this._stairOff + (s.off - this._stairOff) * 0.35;
    return this._stairOff;
  }

  _blocked(x, z) {
    for (const c of this.colliders) {
      if (c.inter && c.inter.t > 0.35) continue; // otvorena vrata
      if (c.obb) {
        const dx = x - c.cx, dz = z - c.cz;
        const lx = dx * c.ux.x + dz * c.ux.z, lz = dx * c.uz.x + dz * c.uz.z;
        const qx = lx - clamp(lx, -c.hw, c.hw), qz = lz - clamp(lz, -c.hd, c.hd);
        if (qx * qx + qz * qz < RADIUS * RADIUS * 0.8) return true;
        continue;
      }
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
    p.y = EYE + this.fy + this._stairStep(p.x, p.z);
    return true;
  }

  _emitPose(force) {
    const now = performance.now();
    if (!force && now - this.lastPose < 90) return;
    this.lastPose = now;
    if (this.mode === 'third') {
      const h = this.tp.heading;
      this.emit('pose', { x: this.tp.x, y: this.tp.z, yaw: Math.atan2(Math.sin(h), -Math.cos(h)) });
      return;
    }
    const dir = new THREE.Vector3();
    this.camera.getWorldDirection(dir);
    this.emit('pose', { x: this.camera.position.x, y: this.camera.position.z, yaw: Math.atan2(dir.x, -dir.z) });
    this.indoor.position.set(this.camera.position.x, this.camera.position.y + 0.55, this.camera.position.z);
  }

  _makeAvatar() {
    const root = new THREE.Group();
    const skin = mat(0xe2b993, { roughness: 0.7 });
    const shirt = mat(ACCENT, { roughness: 0.85 });
    const pants = mat(0x2f3437, { roughness: 0.9 });
    const shoe = mat(0x1d1d1d, { roughness: 0.6 });
    const hair = mat(0x3b2a1e, { roughness: 1 });
    const add = (parent, geo, m, x, y, z) => {
      const mesh = new THREE.Mesh(geo, m);
      mesh.position.set(x, y, z);
      mesh.castShadow = true;
      parent.add(mesh);
      return mesh;
    };
    const legs = [], arms = [];
    for (const sx of [-1, 1]) {
      const hip = new THREE.Group();
      hip.position.set(sx * 0.1, 0.9, 0);
      root.add(hip);
      add(hip, new THREE.CapsuleGeometry(0.068, 0.7, 4, 10), pants, 0, -0.43, 0);
      add(hip, new THREE.BoxGeometry(0.11, 0.07, 0.24), shoe, 0, -0.865, 0.04);
      legs.push(hip);
      const sh = new THREE.Group();
      sh.position.set(sx * 0.245, 1.43, 0);
      root.add(sh);
      add(sh, new THREE.CapsuleGeometry(0.05, 0.46, 4, 10), shirt, 0, -0.27, 0);
      add(sh, new THREE.SphereGeometry(0.052, 12, 10), skin, 0, -0.56, 0);
      arms.push(sh);
    }
    const torso = add(root, new THREE.CapsuleGeometry(0.19, 0.38, 6, 16), shirt, 0, 1.2, 0);
    torso.scale.set(1.08, 1, 0.68);
    add(root, new THREE.CylinderGeometry(0.05, 0.06, 0.08, 12), skin, 0, 1.5, 0);
    const head = add(root, new THREE.SphereGeometry(0.115, 20, 16), skin, 0, 1.62, 0);
    head.scale.set(0.92, 1.05, 1);
    const cap = add(root, new THREE.SphereGeometry(0.122, 20, 12, 0, Math.PI * 2, 0, Math.PI * 0.55), hair, 0, 1.64, -0.012);
    cap.scale.set(0.95, 1.05, 1.05);
    add(root, new THREE.SphereGeometry(0.018, 8, 6), mat(0x1d1d1d), -0.04, 1.64, 0.105);
    add(root, new THREE.SphereGeometry(0.018, 8, 6), mat(0x1d1d1d), 0.04, 1.64, 0.105);
    return { root, legs, arms, torso };
  }

  _thirdUpdate(dt) {
    const k = this.keys, tp = this.tp;
    let f = 0, s = 0;
    if (k.has('KeyW') || k.has('ArrowUp')) f += 1;
    if (k.has('KeyS') || k.has('ArrowDown')) f -= 1;
    if (k.has('KeyD') || k.has('ArrowRight')) s += 1;
    if (k.has('KeyA') || k.has('ArrowLeft')) s -= 1;
    f -= this.touch.vz;
    s += this.touch.vx;
    const fx = -Math.sin(tp.yaw), fz = -Math.cos(tp.yaw);
    const rx = Math.cos(tp.yaw), rz = -Math.sin(tp.yaw);
    let mx = fx * f + rx * s, mz = fz * f + rz * s;
    const len = Math.hypot(mx, mz);
    const run = k.has('ShiftLeft') || k.has('ShiftRight');
    const target = len > 0.05 ? (run ? RUN : WALK * 1.1) * Math.min(1, len) : 0;
    tp.speed += (target - tp.speed) * Math.min(1, dt * 10);
    if (len > 0.05) {
      mx /= len;
      mz /= len;
      const want = Math.atan2(mx, mz);
      let diff = want - tp.heading;
      while (diff > Math.PI) diff -= Math.PI * 2;
      while (diff < -Math.PI) diff += Math.PI * 2;
      tp.heading += diff * Math.min(1, dt * 12);
    }
    if (tp.speed > 0.01) {
      const hx = Math.sin(tp.heading), hz = Math.cos(tp.heading);
      const dx = hx * tp.speed * dt, dz = hz * tp.speed * dt;
      const stuck = this._blocked(tp.x, tp.z);
      if (stuck || !this._blocked(tp.x + dx, tp.z)) tp.x += dx;
      if (stuck || !this._blocked(tp.x, tp.z + dz)) tp.z += dz;
      this._emitPose(false);
    }
    // animacija hoda
    const a = this.avatar;
    const amt = Math.min(1, tp.speed / WALK);
    tp.phase += dt * (4 + tp.speed * 3.2) * (amt > 0.02 ? 1 : 0);
    const sw = Math.sin(tp.phase) * 0.62 * amt;
    a.legs[0].rotation.x = sw;
    a.legs[1].rotation.x = -sw;
    a.arms[0].rotation.x = -sw * 0.8;
    a.arms[1].rotation.x = sw * 0.8;
    tp.off = this._stairStep(tp.x, tp.z);
    a.root.position.set(tp.x, this.fy + tp.off + Math.abs(Math.cos(tp.phase)) * 0.035 * amt, tp.z);
    a.root.rotation.y = tp.heading;
    this._thirdCamera(dt, false);
  }

  _thirdCamera(dt, snap) {
    const tp = this.tp;
    const target = new THREE.Vector3(tp.x, 1.45 + this.fy + (tp.off || 0), tp.z);
    const off = new THREE.Vector3(Math.sin(tp.yaw) * Math.cos(tp.pitch), Math.sin(tp.pitch), Math.cos(tp.yaw) * Math.cos(tp.pitch));
    let dist = tp.dist;
    if (this.wallMeshes.length) {
      this.raycaster.set(target, off);
      this.raycaster.far = dist;
      const hit = this.raycaster.intersectObjects(this.wallMeshes, false)[0];
      this.raycaster.far = Infinity;
      if (hit) dist = Math.max(0.5, hit.distance - 0.25);
    }
    const desired = target.clone().addScaledVector(off, dist);
    if (dist < tp.dist * 0.6) {
      // zid je preblizu: podigni kameru iznad zidova i gledaj odozgo
      const lift = Math.min(2.4, (tp.dist - dist) * 0.6);
      desired.y += lift;
    }
    if (snap) this.camera.position.copy(desired);
    else this.camera.position.lerp(desired, 1 - Math.exp(-dt * 14));
    this.camera.up.set(0, 1, 0);
    this.camera.lookAt(target);
  }

  _loop() {
    requestAnimationFrame(this._loop);
    const dt = Math.min(this.clock.getDelta(), 0.05);
    this._animateInters(dt);
    this._updateMeasureLabel();
    if (this.mode === 'third') {
      this._thirdUpdate(dt);
      this.indoor.intensity = 0;
      this.ambient.intensity = 0.25 * (1 - 0.7 * (this.night || 0));
    } else if (this.mode === 'walk') {
      const active = this.fpv.isLocked || this.touch.move || this.touch.look;
      if (this.fpv.isLocked || this.touch.move) this._walk(dt);
      if (active) this._emitPose(false);
      const nn = this.night || 0;
      this.indoor.intensity = 2.2 * (1 - 0.75 * nn);
      this.ambient.intensity = 0.55 * (1 - 0.7 * nn);
    } else {
      this.orbit.update();
      this.indoor.intensity = 0;
      this.ambient.intensity = 0;
    }
    // bliža ravnina kamere prati udaljenost (bolja preciznost dubine izdaleka => nema treperenja ploha)
    const near = this.mode === 'orbit' ? clamp(this.camera.position.distanceTo(this.orbit.target) * 0.012, 0.1, 2) : 0.08;
    if (Math.abs(near - this.camera.near) > near * 0.15) {
      this.camera.near = near;
      this.camera.updateProjectionMatrix();
    }
    if (this.container && this.container.isConnected) this.renderer.render(this.scene, this.camera);
  }
}

const engine = new Engine();
const prev = window.Planstratiq3D || {};
const api = {
  ready: true,
  wantsKeys: () => !!(engine && ((engine.mode === 'third' && engine.kbd) || (engine.mode === 'walk' && engine.fpv && engine.fpv.isLocked))),
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
Object.defineProperty(api, "_engine", { value: engine, enumerable: false }); // za dijagnostiku
for (const [fn, args] of prev._q || []) if (api[fn]) api[fn](...args);
