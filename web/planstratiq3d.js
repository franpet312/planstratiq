// Planstratiq 3D engine (Three.js).
// Flutter šalje tlocrt kao JSON (Planstratiq3D.setPlan), engine iz njega gradi
// zidove s otvorima, podove, stropove i namještaj, te nudi dva načina prikaza:
//   orbit – pogled odozgo/sa strane (rotacija, pomak, zoom)
//   walk  – šetnja u prvom licu (WASD + miš, kolizija sa zidovima)
//
// Koordinate: tlocrt (x, y) u metrima  ->  3D (x, 0, z=y), y je visina.

import * as THREE from 'three';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { PointerLockControls } from 'three/addons/controls/PointerLockControls.js';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

const EYE = 1.65;      // visina očiju (m)
const RADIUS = 0.25;   // "debljina" osobe za koliziju
const WALK = 1.6;      // m/s
const RUN = 3.4;       // m/s uz Shift

const rgb = (c) => (Number(c) & 0xffffff);

class Engine {
  constructor() {
    const r = (this.renderer = new THREE.WebGLRenderer({ antialias: true }));
    r.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
    r.shadowMap.enabled = true;
    r.shadowMap.type = THREE.PCFSoftShadowMap;
    r.outputColorSpace = THREE.SRGBColorSpace;
    r.toneMapping = THREE.ACESFilmicToneMapping;
    r.toneMappingExposure = 1.05;
    Object.assign(r.domElement.style, { display: 'block', width: '100%', height: '100%', outline: 'none' });

    const scene = (this.scene = new THREE.Scene());
    scene.background = new THREE.Color(0xbcd7ef);
    scene.fog = new THREE.Fog(0xbcd7ef, 60, 220);

    this.camera = new THREE.PerspectiveCamera(70, 1, 0.05, 600);
    this.camera.position.set(14, 16, 20);

    scene.add(new THREE.HemisphereLight(0xffffff, 0x8a7f6a, 1.1));
    const sun = (this.sun = new THREE.DirectionalLight(0xfff4e0, 2.4));
    sun.position.set(18, 28, 12);
    sun.castShadow = true;
    sun.shadow.mapSize.set(2048, 2048);
    sun.shadow.bias = -0.0004;
    sun.shadow.normalBias = 0.02;
    Object.assign(sun.shadow.camera, { left: -30, right: 30, top: 30, bottom: -30, near: 1, far: 100 });
    scene.add(sun, sun.target);
    // slabo unutarnje svjetlo da prostorije u šetnji ne budu mračne
    this.indoor = new THREE.AmbientLight(0xfff1dd, 0.0);
    scene.add(this.indoor);

    const ground = new THREE.Mesh(
      new THREE.PlaneGeometry(600, 600).rotateX(-Math.PI / 2),
      new THREE.MeshStandardMaterial({ color: 0x86b05f, roughness: 1 })
    );
    ground.position.y = -0.02;
    ground.receiveShadow = true;
    scene.add(ground);

    this.world = new THREE.Group();
    scene.add(this.world);

    this.orbit = new OrbitControls(this.camera, r.domElement);
    this.orbit.enableDamping = true;
    this.orbit.maxPolarAngle = Math.PI / 2.05;
    this.orbit.minDistance = 1;
    this.orbit.maxDistance = 250;

    this.fpv = new PointerLockControls(this.camera, r.domElement);
    this.fpv.addEventListener('lock', () => this._updateHint());
    this.fpv.addEventListener('unlock', () => { this.keys.clear(); this._updateHint(); });

    this.mode = 'orbit';
    this.keys = new Set();
    this.colliders = [];
    this.ceilings = [];
    this.plan = null;
    this.framed = false;
    this.savedOrbit = null;
    this.matCache = new Map();
    this.gltfCache = new Map();
    this.loader = new GLTFLoader();
    this.clock = new THREE.Clock();

    window.addEventListener('keydown', (e) => {
      if (this.mode === 'walk' && this.fpv.isLocked) {
        this.keys.add(e.code);
        e.preventDefault();
        e.stopPropagation();
      }
    }, true);
    window.addEventListener('keyup', (e) => this.keys.delete(e.code), true);
    r.domElement.addEventListener('click', () => {
      if (this.mode === 'walk' && !this.fpv.isLocked) this.fpv.lock();
    });

    this.hint = document.createElement('div');
    Object.assign(this.hint.style, {
      position: 'absolute', left: '50%', bottom: '18px', transform: 'translateX(-50%)',
      padding: '8px 14px', borderRadius: '10px', background: 'rgba(20,24,28,.72)', color: '#fff',
      font: '500 13px system-ui, sans-serif', pointerEvents: 'none', whiteSpace: 'nowrap',
    });
    this.cross = document.createElement('div');
    Object.assign(this.cross.style, {
      position: 'absolute', left: '50%', top: '50%', width: '6px', height: '6px', margin: '-3px 0 0 -3px',
      borderRadius: '50%', background: 'rgba(255,255,255,.9)', boxShadow: '0 0 0 1px rgba(0,0,0,.35)',
      pointerEvents: 'none', display: 'none',
    });

    this._loop = this._loop.bind(this);
    this.running = false;
  }

  // ------------------------------------------------------------------ API
  mount(el) {
    this.container = el;
    el.style.position = 'relative';
    el.style.overflow = 'hidden';
    el.appendChild(this.renderer.domElement);
    el.appendChild(this.hint);
    el.appendChild(this.cross);
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
    try {
      this.plan = typeof json === 'string' ? JSON.parse(json) : json;
    } catch (e) {
      console.error('[Planstratiq3D] neispravan JSON', e);
      return;
    }
    this._rebuild();
    if (!this.framed && (this.plan.walls?.length || this.plan.items?.length)) {
      this.framed = true;
      this.frame();
    }
  }

  setMode(mode) {
    if (mode === this.mode) return;
    if (mode === 'walk') {
      this.savedOrbit = { pos: this.camera.position.clone(), target: this.orbit.target.clone() };
      this.orbit.enabled = false;
      this._spawn();
    } else {
      if (this.fpv.isLocked) this.fpv.unlock();
      this.orbit.enabled = true;
      if (this.savedOrbit) {
        this.camera.position.copy(this.savedOrbit.pos);
        this.orbit.target.copy(this.savedOrbit.target);
      }
      this.camera.up.set(0, 1, 0);
      this.camera.lookAt(this.orbit.target);
    }
    this.mode = mode;
    for (const c of this.ceilings) c.visible = mode === 'walk';
    this.indoor.intensity = mode === 'walk' ? 0.55 : 0.0;
    this._updateHint();
  }

  frame() {
    const b = this._bounds();
    const size = Math.max(b.max.x - b.min.x, b.max.z - b.min.z, 6);
    const c = new THREE.Vector3((b.min.x + b.max.x) / 2, 0, (b.min.z + b.max.z) / 2);
    this.orbit.target.copy(c);
    this.camera.position.set(c.x + size * 0.55, size * 0.85, c.z + size * 0.95);
    this.camera.lookAt(c);
    this.sun.position.set(c.x + 18, 28, c.z + 12);
    this.sun.target.position.copy(c);
    const sc = this.sun.shadow.camera;
    const half = Math.max(20, size);
    Object.assign(sc, { left: -half, right: half, top: half, bottom: -half });
    sc.updateProjectionMatrix();
  }

  // ------------------------------------------------------------------ interno
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
    if (!this.hint) return;
    let text = '';
    if (this.mode === 'orbit') text = 'Lijevi klik: rotacija · Desni: pomak · Kotačić: zoom';
    else if (!this.fpv.isLocked) text = 'Klikni u prikaz za šetnju · WASD / strelice · Shift = trčanje · Esc = izlaz';
    this.hint.textContent = text;
    this.hint.style.display = text ? 'block' : 'none';
    this.cross.style.display = this.mode === 'walk' && this.fpv.isLocked ? 'block' : 'none';
  }

  _mat(color, opts = {}) {
    const key = rgb(color) + JSON.stringify(opts);
    let m = this.matCache.get(key);
    if (!m) {
      m = opts.glass
        ? new THREE.MeshPhysicalMaterial({ color: 0xaad4ff, transparent: true, opacity: 0.28, roughness: 0.05, metalness: 0, depthWrite: false })
        : new THREE.MeshStandardMaterial({ color: rgb(color), roughness: opts.roughness ?? 0.85, metalness: opts.metalness ?? 0, side: opts.double ? THREE.DoubleSide : THREE.FrontSide });
      this.matCache.set(key, m);
    }
    return m;
  }

  _clearWorld() {
    this.world.traverse((o) => { if (o.geometry) o.geometry.dispose(); });
    this.world.clear();
    this.colliders = [];
    this.ceilings = [];
  }

  _bounds() {
    const p = this.plan || {};
    const b = new THREE.Box3(new THREE.Vector3(0, 0, 0), new THREE.Vector3(0, 0, 0));
    let any = false;
    const add = (x, z) => {
      if (!any) { b.min.set(x, 0, z); b.max.set(x, 0, z); any = true; }
      else b.expandByPoint(new THREE.Vector3(x, 0, z));
    };
    for (const n of Object.values(p.nodes || {})) add(n.x, n.y);
    if (!any) for (const it of p.items || []) add(it.x, it.y);
    if (!any) { b.min.set(-5, 0, -5); b.max.set(5, 0, 5); }
    return b;
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
    let maxH = 2.6;
    for (const w of p.walls || []) {
      maxH = Math.max(maxH, w.height || 2.6);
      this._buildWall(w, nodes, degree, (p.openings || []).filter((o) => o.wallId === w.id));
    }
    this._buildFloors(p, nodes, maxH);
    for (const it of p.items || []) this._buildItem(it);
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
    const mat = this._mat(w.color);

    const box = (x0, x1, y0, y1, material = mat, depth = T, z = 0) => {
      if (x1 - x0 < 0.002 || y1 - y0 < 0.002) return null;
      const m = new THREE.Mesh(new THREE.BoxGeometry(x1 - x0, y1 - y0, depth), material);
      m.position.set((x0 + x1) / 2, (y0 + y1) / 2, z);
      m.castShadow = true;
      m.receiveShadow = true;
      g.add(m);
      return m;
    };

    const ops = openings
      .map((o) => ({ ...o, s: o.t * L - o.width / 2, e: o.t * L + o.width / 2 }))
      .sort((a, b) => a.s - b.s);

    const solids = []; // dijelovi zida kroz koje se ne može proći (za koliziju)
    let cur = -ea;
    let solidStart = -ea;
    for (const o of ops) {
      const s = Math.max(o.s, cur), e = Math.min(o.e, L + eb);
      if (e <= s) continue;
      box(cur, s, 0, H);
      const top = Math.min(o.sill + o.height, H);
      box(s, e, top, H);
      if (o.sill > 0) box(s, e, 0, o.sill);
      const frameMat = this._mat(0xf7f7f5, { roughness: 0.5 });
      if (o.type === 'window') {
        box(s, e, o.sill, top, this._mat(0, { glass: true }), 0.02);
        // okvir prozora
        box(s, e, o.sill - 0.04, o.sill, frameMat, T + 0.04);
        box(s, s + 0.05, o.sill, top, frameMat, 0.07);
        box(e - 0.05, e, o.sill, top, frameMat, 0.07);
        box(s, e, top - 0.05, top, frameMat, 0.07);
        box((s + e) / 2 - 0.025, (s + e) / 2 + 0.025, o.sill, top, frameMat, 0.06);
      } else {
        // dovratnik + otvoreno krilo
        box(s, s + 0.04, 0, top, frameMat, T + 0.02);
        box(e - 0.04, e, 0, top, frameMat, T + 0.02);
        box(s, e, top - 0.04, top, frameMat, T + 0.02);
        const pivot = new THREE.Group();
        pivot.position.set(s + 0.05, 0, T / 2);
        pivot.rotation.y = -1.35;
        const leafW = Math.max(0.2, o.width - 0.1);
        const leaf = new THREE.Mesh(new THREE.BoxGeometry(leafW, top - 0.05, 0.04), this._mat(0xe9e1d3, { roughness: 0.6 }));
        leaf.position.set(leafW / 2, (top - 0.05) / 2, 0.02);
        leaf.castShadow = true;
        pivot.add(leaf);
        g.add(pivot);
        // vrata su prohodna: prekini solidni dio
        if (o.sill < 0.3) {
          solids.push([solidStart, s]);
          solidStart = e;
        }
      }
      cur = Math.max(cur, e);
    }
    box(cur, L + eb, 0, H);
    solids.push([solidStart, L + eb]);
    this.world.add(g);

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
    const rooms = p.rooms || [];
    const mk = (pts, color, y, isCeiling) => {
      const geo = new THREE.ShapeGeometry(this._shapeFrom(pts)).rotateX(-Math.PI / 2);
      const m = new THREE.Mesh(geo, this._mat(color, { double: true, roughness: isCeiling ? 0.95 : 0.7 }));
      m.position.y = y;
      m.receiveShadow = true;
      if (isCeiling) {
        m.visible = this.mode === 'walk';
        this.ceilings.push(m);
      }
      this.world.add(m);
    };
    for (const r of rooms) {
      const pts = (r.nodeIds || []).map((id) => nodes[id]).filter(Boolean);
      if (pts.length < 3) continue;
      mk(pts, r.floorColor, 0.015, false);
      mk(pts, 0xfbfaf7, maxH, true);
    }
    if (!rooms.length && (p.walls || []).length) {
      const b = this._bounds();
      const pts = [
        { x: b.min.x, y: b.min.z }, { x: b.max.x, y: b.min.z },
        { x: b.max.x, y: b.max.z }, { x: b.min.x, y: b.max.z },
      ];
      mk(pts, 0xd8c3a5, 0.015, false);
      mk(pts, 0xfbfaf7, maxH, true);
    }
  }

  // ------------------------------------------------------------ namještaj
  _buildItem(it) {
    const g = new THREE.Group();
    g.position.set(it.x, 0, it.y);
    g.rotation.y = -(it.rotation || 0);
    this.world.add(g);
    const W = it.w, D = it.d, H = it.h;
    const color = it.color;

    if (it.modelUrl) {
      this._loadModel(it.modelUrl, g, W, D, H, color);
      return;
    }
    const b = (w, h, d, x, y, z, c = color, opts) => {
      const m = new THREE.Mesh(new THREE.BoxGeometry(Math.max(w, 0.001), Math.max(h, 0.001), Math.max(d, 0.001)), this._mat(c, opts));
      m.position.set(x, y, z);
      m.castShadow = h > 0.03;
      m.receiveShadow = true;
      g.add(m);
      return m;
    };
    const cyl = (rt, rb, h, x, y, z, c, seg = 20) => {
      const m = new THREE.Mesh(new THREE.CylinderGeometry(rt, rb, h, seg), this._mat(c));
      m.position.set(x, y, z);
      m.castShadow = true;
      g.add(m);
      return m;
    };
    const sphere = (r, x, y, z, c, sy = 1) => {
      const m = new THREE.Mesh(new THREE.SphereGeometry(r, 20, 14), this._mat(c, { roughness: 1 }));
      m.position.set(x, y, z);
      m.scale.y = sy;
      m.castShadow = true;
      g.add(m);
      return m;
    };
    const legs = (w, d, h, inset = 0.05, t = 0.045, c = color) => {
      for (const sx of [-1, 1]) for (const sz of [-1, 1]) b(t, h, t, sx * (w / 2 - inset), h / 2, sz * (d / 2 - inset), c);
    };
    const lighter = (c, f = 0.25) => {
      const col = new THREE.Color(rgb(c));
      col.lerp(new THREE.Color(0xffffff), f);
      return col.getHex();
    };
    const darker = (c, f = 0.35) => {
      const col = new THREE.Color(rgb(c));
      col.lerp(new THREE.Color(0x000000), f);
      return col.getHex();
    };

    // Stražnja strana objekta je na lokalnom -z (u tlocrtu: deblja linija).
    switch (it.shape) {
      case 'bed': {
        b(W, 0.3, D, 0, 0.15, 0);
        b(W - 0.06, 0.2, D - 0.12, 0, 0.4, 0.04, 0xf4f1ea);
        b(W, H, 0.08, 0, H / 2, -D / 2 + 0.04);
        b(W - 0.1, 0.06, D * 0.55, 0, 0.53, D * 0.2, lighter(color, 0.5));
        const pw = Math.min(0.6, W * 0.42);
        for (const sx of W > 1.2 ? [-1, 1] : [0]) b(pw, 0.12, 0.36, sx * W * 0.23, 0.56, -D / 2 + 0.32, 0xffffff);
        break;
      }
      case 'sofa': {
        const seatH = 0.44;
        b(W, seatH * 0.6, D, 0, seatH * 0.3, 0, darker(color, 0.15));
        b(W - 0.36, 0.16, D - 0.25, 0, seatH * 0.6 + 0.08, 0.1, lighter(color, 0.1));
        b(W, H - seatH * 0.6, 0.22, 0, seatH * 0.6 + (H - seatH * 0.6) / 2, -D / 2 + 0.11);
        for (const sx of [-1, 1]) b(0.18, 0.64, D, sx * (W / 2 - 0.09), 0.32, 0);
        break;
      }
      case 'table': {
        b(W, 0.04, D, 0, H - 0.02, 0);
        legs(W, D, H - 0.04, 0.06, 0.05);
        break;
      }
      case 'chair': {
        const seat = Math.min(0.46, H * 0.5);
        b(W, 0.05, D, 0, seat, 0);
        legs(W, D, seat - 0.025, 0.03, 0.035);
        b(W, H - seat, 0.04, 0, seat + (H - seat) / 2, -D / 2 + 0.02);
        break;
      }
      case 'wardrobe': {
        b(W, H, D, 0, H / 2, 0);
        b(0.008, H - 0.1, 0.005, 0, H / 2, D / 2 + 0.003, darker(color, 0.5));
        for (const sx of [-1, 1]) b(0.02, 0.3, 0.03, sx * 0.05, H * 0.52, D / 2 + 0.015, 0x8c8c8c, { metalness: 0.6 });
        break;
      }
      case 'shelf': {
        const t = 0.025;
        for (const sx of [-1, 1]) b(t, H, D, sx * (W / 2 - t / 2), H / 2, 0);
        b(W, H, 0.01, 0, H / 2, -D / 2 + 0.005);
        const n = Math.max(2, Math.round(H / 0.38));
        for (let i = 0; i <= n; i++) b(W - 2 * t, t, D, 0, t / 2 + (i * (H - t)) / n, 0);
        // nekoliko "knjiga"
        for (let i = 0; i < n; i++) {
          const y0 = t + (i * (H - t)) / n;
          let x = -W / 2 + t + 0.02;
          while (x < W / 2 - t - 0.06) {
            const bw = 0.025 + Math.random() * 0.03, bh = 0.18 + Math.random() * 0.1;
            b(bw, bh, D * 0.75, x + bw / 2, y0 + bh / 2, 0.01, [0x8a3b2f, 0x2f5a8a, 0xd9b25a, 0x4e7a4a, 0x555555][Math.floor(Math.random() * 5)]);
            x += bw + 0.004;
            if (Math.random() < 0.08) x += 0.12;
          }
        }
        break;
      }
      case 'kitchen': {
        const base = Math.min(H, 0.9);
        b(W, base - 0.04, D - 0.02, 0, (base - 0.04) / 2, -0.01);
        b(W, 0.04, D, 0, base - 0.02, 0, 0x5a5a58, { roughness: 0.4 });
        const n = Math.max(1, Math.round(W / 0.6));
        for (let i = 1; i < n; i++) b(0.006, base - 0.1, 0.005, -W / 2 + (i * W) / n, (base - 0.04) / 2, D / 2 - 0.018, 0xb5b5b0);
        if (H > 1.5) {
          b(W, 0.7, 0.35, 0, H - 0.35, -D / 2 + 0.175);
          b(W, 0.5, 0.01, 0, base + 0.28, -D / 2 + 0.005, 0xe0ddd5); // pločice
        }
        break;
      }
      case 'tv': {
        b(W, 0.5, D, 0, 0.25, 0);
        const sw = Math.min(W * 0.8, 1.45), sh = sw * 0.57;
        b(sw, sh, 0.04, 0, 0.55 + sh / 2, -D / 2 + 0.12, 0x111111, { roughness: 0.25 });
        b(0.3, 0.05, 0.2, 0, 0.525, -D / 2 + 0.12, 0x222222);
        break;
      }
      case 'lamp': {
        cyl(0.15, 0.15, 0.03, 0, 0.015, 0, 0x333333);
        cyl(0.012, 0.012, H - 0.3, 0, (H - 0.3) / 2, 0, 0x333333, 8);
        const shade = cyl(W * 0.35, W * 0.48, 0.3, 0, H - 0.15, 0, color);
        shade.material = new THREE.MeshStandardMaterial({ color: rgb(color), emissive: 0xffe2a8, emissiveIntensity: 0.6, side: THREE.DoubleSide });
        break;
      }
      case 'plant': {
        cyl(W * 0.3, W * 0.24, H * 0.3, 0, H * 0.15, 0, 0xc9b8a0);
        sphere(W * 0.5, 0, H * 0.62, 0, color, (H * 0.7) / W);
        break;
      }
      case 'rug': {
        b(W, Math.max(H, 0.01), D, 0, Math.max(H, 0.01) / 2 + 0.017, 0);
        break;
      }
      case 'bath': {
        b(W, H, D, 0, H / 2, 0);
        b(W - 0.12, 0.02, D - 0.12, 0, H - 0.05, 0, 0x9fc9e0, { roughness: 0.1 });
        break;
      }
      case 'shower': {
        b(W, 0.06, D, 0, 0.03, 0, 0xffffff);
        b(W, H, 0.01, 0, H / 2, D / 2 - 0.005, 0, { glass: true });
        b(0.01, H, D, W / 2 - 0.005, H / 2, 0, 0, { glass: true });
        cyl(0.1, 0.1, 0.02, 0, H - 0.1, -D / 2 + 0.2, 0xbbbbbb);
        break;
      }
      case 'toilet': {
        b(W, 0.4, D * 0.6, 0, 0.2, D * 0.12);
        b(W, H - 0.4, 0.18, 0, 0.4 + (H - 0.4) / 2, -D / 2 + 0.09);
        break;
      }
      case 'tree': {
        const trunkH = H * 0.42;
        cyl(W * 0.04, W * 0.06, trunkH, 0, trunkH / 2, 0, 0x6b4a2f, 10);
        sphere(W * 0.5, 0, trunkH + (H - trunkH) * 0.45, 0, color, (H - trunkH) / W);
        break;
      }
      case 'hedge': {
        b(W, H, D, 0, H / 2, 0, color, { roughness: 1 });
        break;
      }
      case 'fence': {
        const n = Math.max(1, Math.round(W / 1.0));
        for (let i = 0; i <= n; i++) b(0.07, H, 0.07, -W / 2 + (i * W) / n, H / 2, 0);
        for (const y of [H * 0.3, H * 0.85]) b(W, 0.08, 0.04, 0, y, 0);
        break;
      }
      case 'pool': {
        b(W, 0.04, D, 0, 0.02, 0, color, { roughness: 0.1 });
        const rim = 0xe9e6df;
        b(W + 0.6, 0.06, 0.3, 0, 0.03, -D / 2 - 0.15, rim);
        b(W + 0.6, 0.06, 0.3, 0, 0.03, D / 2 + 0.15, rim);
        b(0.3, 0.06, D, -W / 2 - 0.15, 0.03, 0, rim);
        b(0.3, 0.06, D, W / 2 + 0.15, 0.03, 0, rim);
        break;
      }
      case 'deck': {
        const n = Math.max(2, Math.round(D / 0.15));
        for (let i = 0; i < n; i++) b(W, H, D / n - 0.01, 0, H / 2, -D / 2 + (i + 0.5) * (D / n), i % 2 ? color : lighter(color, 0.06));
        break;
      }
      case 'lounger': {
        b(W, 0.3, D, 0, 0.15, 0, 0xb9b9b4);
        b(W - 0.06, 0.06, D * 0.7, 0, 0.33, D * 0.13, color);
        const back = b(W - 0.06, 0.06, D * 0.35, 0, 0.45, -D / 2 + 0.2, color);
        back.rotation.x = 0.6;
        break;
      }
      case 'umbrella': {
        cyl(0.25, 0.25, 0.05, 0, 0.025, 0, 0x555555);
        cyl(0.02, 0.02, H, 0, H / 2, 0, 0x777777, 8);
        const top = new THREE.Mesh(new THREE.ConeGeometry(W / 2, 0.45, 16, 1, true), this._mat(color, { double: true }));
        top.position.y = H - 0.15;
        top.castShadow = true;
        g.add(top);
        break;
      }
      case 'car': {
        b(W, H * 0.45, D, 0, 0.18 + H * 0.225, 0);
        b(W * 0.9, H * 0.4, D * 0.5, 0, 0.18 + H * 0.45 + H * 0.2, -D * 0.05, 0x2b3440, { roughness: 0.2 });
        for (const sx of [-1, 1]) for (const sz of [-1, 1]) {
          const wheel = cyl(0.32, 0.32, 0.22, sx * (W / 2 - 0.1), 0.32, sz * (D / 2 - 0.75), 0x1a1a1a);
          wheel.rotation.z = Math.PI / 2;
        }
        break;
      }
      default:
        b(W, H, D, 0, H / 2, 0);
    }
  }

  _loadModel(url, g, W, D, H, color) {
    const ph = new THREE.Mesh(new THREE.BoxGeometry(W, H, D), this._mat(color));
    ph.position.y = H / 2;
    g.add(ph);
    const place = (src) => {
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
    };
    let p = this.gltfCache.get(url);
    if (!p) {
      p = this.loader.loadAsync(url).then((gltf) => gltf.scene);
      this.gltfCache.set(url, p);
    }
    p.then(place).catch((e) => console.warn('[Planstratiq3D] model nije učitan', url, e));
  }

  // ------------------------------------------------------------ šetnja
  _spawn() {
    const p = this.plan || {};
    const nodes = p.nodes || {};
    let x, z;
    const room = (p.rooms || []).find((r) => (r.nodeIds || []).every((id) => nodes[id]));
    if (room) {
      const pts = room.nodeIds.map((id) => nodes[id]);
      x = pts.reduce((s, q) => s + q.x, 0) / pts.length;
      z = pts.reduce((s, q) => s + q.y, 0) / pts.length;
    } else {
      const b = this._bounds();
      x = (b.min.x + b.max.x) / 2;
      z = (b.min.z + b.max.z) / 2;
    }
    this.camera.position.set(x, EYE, z);
    this.camera.up.set(0, 1, 0);
    this.camera.rotation.set(0, 0, 0, 'YXZ');
    this.camera.lookAt(x, EYE, z - 1);
  }

  _blocked(x, z) {
    for (const c of this.colliders) {
      const abx = c.bx - c.ax, abz = c.bz - c.az;
      const l2 = abx * abx + abz * abz;
      let t = l2 ? ((x - c.ax) * abx + (z - c.az) * abz) / l2 : 0;
      t = Math.max(0, Math.min(1, t));
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
    if (!f && !s) return;
    const len = Math.hypot(f, s);
    f /= len; s /= len;
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
  }

  _loop() {
    requestAnimationFrame(this._loop);
    const dt = Math.min(this.clock.getDelta(), 0.05);
    if (this.mode === 'walk') {
      if (this.fpv.isLocked) this._walk(dt);
    } else {
      this.orbit.update();
    }
    if (this.container && this.container.isConnected) this.renderer.render(this.scene, this.camera);
  }
}

const engine = new Engine();
const api = {
  mount: (el) => engine.mount(el),
  setPlan: (json) => engine.setPlan(json),
  setMode: (mode) => engine.setMode(mode),
  frame: () => engine.frame(),
};
const queued = (window.Planstratiq3D && window.Planstratiq3D._q) || [];
window.Planstratiq3D = api;
for (const [fn, args] of queued) api[fn](...args);
