// Planstratiq – prepoznavanje zidova, vrata i prozora sa slike tlocrta (u pregledniku, bez servera).
//
// Pristup (za uobičajene nacrte s vodoravnim i okomitim zidovima):
//  1. sivi tonovi → crno/bijelo (Otsu prag)
//  2. procjena debljine zida iz duljina tamnih nizova
//  3. erozija kvadratom: ostaju samo debele linije (zidovi), nestaju tekst, kote i namještaj
//  4. vodoravne i okomite trake u erodiranoj slici → segmenti zidova (os + debljina)
//  5. spajanje kolinearnih segmenata preko praznina: prazna praznina = vrata, praznina s tankim
//     linijama = prozor; krajevi zidova se lijepe na osi okomitih zidova
//
// Rezultat je u pikselima izvorne slike; Dart ga pretvara u metre prema kalibraciji podloge.
(function (root) {
  'use strict';

  function otsu(gray) {
    const hist = new Array(256).fill(0);
    for (let i = 0; i < gray.length; i++) hist[gray[i]]++;
    const total = gray.length;
    let sum = 0;
    for (let t = 0; t < 256; t++) sum += t * hist[t];
    let sumB = 0, wB = 0, best = 0, thr = 128;
    for (let t = 0; t < 256; t++) {
      wB += hist[t];
      if (!wB) continue;
      const wF = total - wB;
      if (!wF) break;
      sumB += t * hist[t];
      const mB = sumB / wB, mF = (sum - sumB) / wF;
      const between = wB * wF * (mB - mF) * (mB - mF);
      if (between > best) { best = between; thr = t; }
    }
    return thr;
  }

  // najčešća "debela" duljina tamnog niza (okomito i vodoravno) ≈ debljina zida u pikselima
  function estimateThickness(mask, w, h) {
    const hist = new Float64Array(200);
    const scan = (len, get, outer) => {
      for (let o = 0; o < outer; o++) {
        let run = 0;
        for (let i = 0; i <= len; i++) {
          if (i < len && get(o, i)) run++;
          else {
            if (run >= 3 && run < 200) hist[run] += run;
            run = 0;
          }
        }
      }
    };
    scan(h, (x, y) => mask[y * w + x], w);
    scan(w, (y, x) => mask[y * w + x], h);
    // izgladi i nađi vrh među duljinama ≥ 4
    let best = 0, bestV = -1;
    for (let t = 4; t < 120; t++) {
      const v = hist[t - 1] * 0.5 + hist[t] + hist[t + 1] * 0.5;
      if (v > bestV) { bestV = v; best = t; }
    }
    return best || 6;
  }

  function erode(mask, w, h, k) {
    // kvadratna erozija preko integralne slike
    const W = w + 1;
    const ii = new Int32Array(W * (h + 1));
    for (let y = 0; y < h; y++) {
      let row = 0;
      for (let x = 0; x < w; x++) {
        row += mask[y * w + x];
        ii[(y + 1) * W + x + 1] = ii[y * W + x + 1] + row;
      }
    }
    const out = new Uint8Array(w * h);
    const r0 = Math.floor((k - 1) / 2), r1 = k - 1 - r0;
    const full = k * k;
    for (let y = r0; y < h - r1; y++) {
      for (let x = r0; x < w - r1; x++) {
        const x0 = x - r0, y0 = y - r0, x1 = x + r1 + 1, y1 = y + r1 + 1;
        const s = ii[y1 * W + x1] - ii[y0 * W + x1] - ii[y1 * W + x0] + ii[y0 * W + x0];
        if (s === full) out[y * w + x] = 1;
      }
    }
    return out;
  }

  // trake duž osi: horiz=true → vodoravni zidovi
  function bands(er, w, h, horiz, minLen, maxThick) {
    const outer = horiz ? h : w, len = horiz ? w : h;
    const at = horiz ? (o, i) => er[o * w + i] : (o, i) => er[i * w + o];
    const open = [];
    const done = [];
    for (let o = 0; o < outer; o++) {
      const runs = [];
      let s = -1;
      for (let i = 0; i <= len; i++) {
        const v = i < len && at(o, i);
        if (v && s < 0) s = i;
        else if (!v && s >= 0) {
          if (i - s >= minLen) runs.push([s, i - 1]);
          s = -1;
        }
      }
      const used = new Set();
      const still = [];
      for (const b of open) {
        let hit = -1;
        for (let r = 0; r < runs.length; r++) {
          if (used.has(r)) continue;
          const [a0, a1] = runs[r];
          const ov = Math.min(a1, b.e) - Math.max(a0, b.s);
          if (ov > 0.6 * Math.min(a1 - a0, b.e - b.s)) { hit = r; break; }
        }
        if (hit >= 0) {
          used.add(hit);
          const [a0, a1] = runs[hit];
          b.o1 = o;
          b.starts.push(a0);
          b.ends.push(a1);
          b.s = Math.min(b.s, a0);
          b.e = Math.max(b.e, a1);
          still.push(b);
        } else done.push(b);
      }
      for (let r = 0; r < runs.length; r++) {
        if (used.has(r)) continue;
        still.push({ o0: o, o1: o, s: runs[r][0], e: runs[r][1], starts: [runs[r][0]], ends: [runs[r][1]] });
      }
      open.length = 0;
      open.push(...still);
    }
    done.push(...open);
    const med = (a) => { const b = a.slice().sort((x, y) => x - y); return b[b.length >> 1]; };
    const out = [];
    for (const b of done) {
      const thick = b.o1 - b.o0 + 1;
      if (thick > maxThick) continue;
      // krajevi: medijan je otporniji od min/max na izbočine (npr. namještaj uz zid)
      out.push({ horiz, c: (b.o0 + b.o1) / 2, t: thick, s: med(b.starts), e: med(b.ends) });
    }
    return out;
  }

  // zatvaranje (dilatacija pa erozija): popuni šrafuru i uske razmake između linija obruba zida
  function close(mask, w, h, k) {
    const inv = new Uint8Array(w * h);
    for (let i = 0; i < inv.length; i++) inv[i] = mask[i] ? 0 : 1;
    const di = erode(inv, w, h, k); // erozija pozadine = dilatacija crteža
    for (let i = 0; i < di.length; i++) di[i] = di[i] ? 0 : 1;
    return erode(di, w, h, k);
  }

  function detectFromGray(gray, w, h, opts = {}) {
    const first = detectOnce(gray, w, h, opts, 0);
    if (opts.closePx != null || first.walls.length >= 4) return first;
    // malo zidova: nacrt vjerojatno ima šrafirane ili samo obrubljene zidove – probaj sa zatvaranjem
    let best = first;
    const total = (r) => r.walls.reduce((a, q) => a + Math.hypot(q.bx - q.ax, q.by - q.ay), 0);
    const side = Math.max(w, h);
    for (const c of [5, 9, 13, 17]) {
      const r = detectOnce(gray, w, h, opts, Math.round((c * side) / 1500) | 1);
      if (r.walls.length >= 4 && total(r) > total(best)) best = r;
    }
    return best;
  }

  function detectOnce(gray, w, h, opts, closePx) {
    const thr = Math.max(70, Math.min(200, opts.threshold || otsu(gray)));
    let mask = new Uint8Array(w * h);
    for (let i = 0; i < gray.length; i++) mask[i] = gray[i] < thr ? 1 : 0;
    const raw = mask;
    if (closePx || opts.closePx) mask = close(mask, w, h, closePx || opts.closePx);
    const T = opts.thicknessPx || estimateThickness(mask, w, h);
    const k = Math.max(3, Math.round(T * 0.42));
    const er = erode(mask, w, h, k);
    const minLen = Math.max(opts.minLenPx || 0, T * 1.6);
    const grow = k - 1; // erozija skrati trake s obje strane za ~k/2
    const segs = [
      ...bands(er, w, h, true, minLen, T * 2.6),
      ...bands(er, w, h, false, minLen, T * 2.6),
    ].map((b) => ({ horiz: b.horiz, c: b.c, t: b.t + grow, s: b.s - grow / 2, e: b.e + grow / 2 }));

    // spoji gotovo paralelne trake na istoj osi (dvostruko otkriveni zid)
    const byAxis = (hz) => segs.filter((s) => s.horiz === hz).sort((a, b) => a.c - b.c || a.s - b.s);
    const openings = [];
    const merged = [];
    for (const hz of [true, false]) {
      const list = byAxis(hz);
      const used = new Array(list.length).fill(false);
      for (let i = 0; i < list.length; i++) {
        if (used[i]) continue;
        used[i] = true;
        let cur = { ...list[i] };
        // skupi sve trake iste osi, poredane po početku
        const same = [cur];
        for (let j = i + 1; j < list.length; j++) {
          if (used[j]) continue;
          if (Math.abs(list[j].c - cur.c) <= Math.max(cur.t, list[j].t) * 0.5) { same.push({ ...list[j] }); used[j] = true; }
        }
        same.sort((a, b) => a.s - b.s);
        let run = { ...same[0] };
        for (let q = 1; q < same.length; q++) {
          const nx = same[q];
          const gap = nx.s - run.e;
          if (gap <= 0) {
            run.e = Math.max(run.e, nx.e);
            run.c = (run.c + nx.c) / 2;
            run.t = Math.max(run.t, nx.t);
            continue;
          }
          // što je u praznini? udio tamnih piksela u izvornoj slici unutar trake zida
          const tt = Math.max(run.t, nx.t);
          const c = (run.c + nx.c) / 2;
          let dark = 0, all = 0;
          for (let a = Math.round(run.e + 1); a < nx.s; a++) {
            for (let b = Math.round(c - tt / 2); b <= Math.round(c + tt / 2); b++) {
              const x = hz ? a : b, y = hz ? b : a;
              if (x < 0 || y < 0 || x >= w || y >= h) continue;
              all++;
              dark += raw[y * w + x];
            }
          }
          const frac = all ? dark / all : 0;
          const maxDoor = opts.maxDoorPx || T * 8;
          const maxWin = opts.maxWindowPx || T * 18;
          let type = null;
          if (frac > 0.07 && gap <= maxWin) type = 'window';
          else if (frac <= 0.07 && gap <= maxDoor && gap >= T * 2) type = 'door';
          if (type) {
            openings.push({ type, horiz: hz, c, s: run.e, e: nx.s });
            run.e = nx.e;
            run.t = Math.max(run.t, nx.t);
          } else {
            merged.push(run);
            run = { ...nx };
          }
        }
        merged.push(run);
      }
    }

    // krajevi zidova: zalijepi na os okomitog zida (L- i T-spojevi)
    const tol = T * 1.2;
    for (const s of merged) {
      for (const end of ['s', 'e']) {
        let best = null, bestD = Infinity;
        for (const o of merged) {
          if (o.horiz === s.horiz) continue;
          // okomiti zid mora prolaziti kroz os ovog zida
          if (s.c < o.s - tol || s.c > o.e + tol) continue;
          const d = Math.abs(o.c - s[end]);
          if (d < Math.max(tol, o.t) && d < bestD) { bestD = d; best = o; }
        }
        if (best) {
          s[end] = best.c;
          // produži okomiti zid do ove osi ako je malo kraći
          if (s.c < best.s && best.s - s.c < tol) best.s = s.c;
          if (s.c > best.e && s.c - best.e < tol) best.e = s.c;
        }
      }
    }

    // poravnaj gotovo jednake osi (npr. 412.4 i 413.1) da se zidovi spoje u isti čvor
    for (const hz of [true, false]) {
      const list = merged.filter((m) => m.horiz === hz).sort((a, b) => a.c - b.c);
      for (let i = 1; i < list.length; i++) {
        if (Math.abs(list[i].c - list[i - 1].c) < T * 0.35) list[i].c = list[i - 1].c;
      }
    }

    const walls = merged
      .filter((m) => m.e - m.s >= T * 1.5)
      .map((m) => (m.horiz
        ? { ax: m.s, ay: m.c, bx: m.e, by: m.c, t: m.t }
        : { ax: m.c, ay: m.s, bx: m.c, by: m.e, t: m.t }));
    const ops = openings.map((o) => ({
      type: o.type,
      x: o.horiz ? (o.s + o.e) / 2 : o.c,
      y: o.horiz ? o.c : (o.s + o.e) / 2,
      width: o.e - o.s,
    }));
    return { threshold: thr, thicknessPx: T, walls, openings: ops };
  }

  function loadImage(src) {
    return new Promise((res, rej) => {
      const img = new Image();
      img.onload = () => res(img);
      img.onerror = rej;
      img.src = src;
    });
  }

  async function detect(dataUrl, optsJson) {
    const opts = optsJson ? JSON.parse(optsJson) : {};
    const img = await loadImage(dataUrl);
    const maxSide = 2200;
    const sc = Math.min(1, maxSide / Math.max(img.width, img.height));
    const w = Math.round(img.width * sc), h = Math.round(img.height * sc);
    const cv = document.createElement('canvas');
    cv.width = w;
    cv.height = h;
    const g = cv.getContext('2d', { willReadFrequently: true });
    g.fillStyle = '#fff';
    g.fillRect(0, 0, w, h);
    g.drawImage(img, 0, 0, w, h);
    const d = g.getImageData(0, 0, w, h).data;
    const gray = new Uint8Array(w * h);
    for (let i = 0, j = 0; j < gray.length; i += 4, j++) gray[j] = (d[i] * 0.299 + d[i + 1] * 0.587 + d[i + 2] * 0.114) | 0;
    if (opts.minLenPx) opts.minLenPx *= sc;
    if (opts.maxDoorPx) opts.maxDoorPx *= sc;
    if (opts.maxWindowPx) opts.maxWindowPx *= sc;
    const r = detectFromGray(gray, w, h, opts);
    // natrag u piksele izvorne slike
    const inv = 1 / sc;
    for (const wl of r.walls) { wl.ax *= inv; wl.ay *= inv; wl.bx *= inv; wl.by *= inv; wl.t *= inv; }
    for (const o of r.openings) { o.x *= inv; o.y *= inv; o.width *= inv; }
    r.thicknessPx *= inv;
    return JSON.stringify(r);
  }

  // ---------------------------------------------------------------- priprema slike
  const PDFJS = 'https://cdn.jsdelivr.net/npm/pdfjs-dist@4.10.38/build/';

  async function pdfToCanvas(bytes) {
    const pdfjs = await import(PDFJS + 'pdf.min.mjs');
    pdfjs.GlobalWorkerOptions.workerSrc = PDFJS + 'pdf.worker.min.mjs';
    const doc = await pdfjs.getDocument({ data: bytes }).promise;
    const page = await doc.getPage(1);
    const v1 = page.getViewport({ scale: 1 });
    const scale = Math.min(6, 2600 / Math.max(v1.width, v1.height));
    const vp = page.getViewport({ scale });
    const cv = document.createElement('canvas');
    cv.width = Math.round(vp.width);
    cv.height = Math.round(vp.height);
    const g = cv.getContext('2d');
    g.fillStyle = '#fff';
    g.fillRect(0, 0, cv.width, cv.height);
    await page.render({ canvasContext: g, viewport: vp }).promise;
    return cv;
  }

  // nagib skena: kut (u stupnjevima) pri kojem su tamni pikseli najviše poravnati u retke i stupce
  function skewAngle(cv) {
    const sc = Math.min(1, 900 / Math.max(cv.width, cv.height));
    const w = Math.max(1, Math.round(cv.width * sc)), h = Math.max(1, Math.round(cv.height * sc));
    const c2 = document.createElement('canvas');
    c2.width = w;
    c2.height = h;
    const g = c2.getContext('2d', { willReadFrequently: true });
    g.fillStyle = '#fff';
    g.fillRect(0, 0, w, h);
    g.drawImage(cv, 0, 0, w, h);
    const d = g.getImageData(0, 0, w, h).data;
    const gray = new Uint8Array(w * h);
    for (let i = 0, j = 0; j < gray.length; i += 4, j++) gray[j] = (d[i] * 0.299 + d[i + 1] * 0.587 + d[i + 2] * 0.114) | 0;
    const thr = otsu(gray);
    const xs = [], ys = [];
    const step = Math.max(1, Math.floor((w * h) / 250000));
    for (let i = 0; i < gray.length; i += step) if (gray[i] < thr) { xs.push(i % w); ys.push((i / w) | 0); }
    if (xs.length < 200) return 0;
    const diag = Math.ceil(Math.hypot(w, h)) + 2;
    const score = (deg) => {
      const a = (deg * Math.PI) / 180, cs = Math.cos(a), sn = Math.sin(a);
      const rows = new Float64Array(2 * diag), cols = new Float64Array(2 * diag);
      for (let k = 0; k < xs.length; k++) {
        const x = xs[k], y = ys[k];
        rows[Math.round(-x * sn + y * cs) + diag]++;
        cols[Math.round(x * cs + y * sn) + diag]++;
      }
      let s = 0;
      for (let k = 0; k < rows.length; k++) s += rows[k] * rows[k] + cols[k] * cols[k];
      return s;
    };
    let best = 0, bestS = score(0);
    for (let a = -6; a <= 6; a += 0.25) { const sc2 = score(a); if (sc2 > bestS) { bestS = sc2; best = a; } }
    for (let a = best - 0.25; a <= best + 0.25; a += 0.05) { const sc2 = score(a); if (sc2 > bestS) { bestS = sc2; best = a; } }
    return best;
  }

  function rotateCanvas(cv, deg) {
    const a = (deg * Math.PI) / 180;
    const out = document.createElement('canvas');
    out.width = cv.width;
    out.height = cv.height;
    const g = out.getContext('2d');
    g.fillStyle = '#fff';
    g.fillRect(0, 0, out.width, out.height);
    g.translate(out.width / 2, out.height / 2);
    g.rotate(-a);
    g.drawImage(cv, -cv.width / 2, -cv.height / 2);
    return out;
  }

  // PDF → slika prve stranice; skenu ispravi nagib. Vraća JSON {dataUrl, angle, pdf}.
  async function prepare(dataUrl) {
    let cv, pdf = false, changed = false;
    if (dataUrl.startsWith('data:application/pdf')) {
      const b64 = dataUrl.substring(dataUrl.indexOf(',') + 1);
      const bin = atob(b64);
      const bytes = new Uint8Array(bin.length);
      for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
      cv = await pdfToCanvas(bytes);
      pdf = true;
      changed = true;
    } else {
      const img = await loadImage(dataUrl);
      cv = document.createElement('canvas');
      cv.width = img.width;
      cv.height = img.height;
      const g = cv.getContext('2d');
      g.fillStyle = '#fff';
      g.fillRect(0, 0, cv.width, cv.height);
      g.drawImage(img, 0, 0);
    }
    let angle = 0;
    try { angle = skewAngle(cv); } catch (e) { angle = 0; }
    if (Math.abs(angle) >= 0.2) { cv = rotateCanvas(cv, angle); changed = true; } else angle = 0;
    return JSON.stringify({ dataUrl: changed ? cv.toDataURL('image/jpeg', 0.88) : dataUrl, angle, pdf });
  }

  const api = { detect, detectFromGray, prepare };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.psqDetect = api;
})(typeof window !== 'undefined' ? window : globalThis);
