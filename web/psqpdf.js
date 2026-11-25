// Planstratiq – izrada PDF dokumenta od rasteriziranih stranica (bez vanjskih biblioteka).
// Svaka stranica je PNG slika točno veličine papira; ovdje se pretvara u JPEG i slaže u PDF 1.4.
(function () {
  const enc = new TextEncoder();

  async function pngToJpeg(png, quality) {
    const blob = new Blob([png], { type: 'image/png' });
    const bmp = await createImageBitmap(blob);
    const cv = document.createElement('canvas');
    cv.width = bmp.width;
    cv.height = bmp.height;
    const g = cv.getContext('2d');
    g.fillStyle = '#fff';
    g.fillRect(0, 0, cv.width, cv.height);
    g.drawImage(bmp, 0, 0);
    const jpg = await new Promise((res) => cv.toBlob(res, 'image/jpeg', quality));
    return { bytes: new Uint8Array(await jpg.arrayBuffer()), w: cv.width, h: cv.height };
  }

  // tekst u PDF nizu (UTF-16BE s BOM-om, za naslov dokumenta s dijakriticima)
  function pdfText(s) {
    let hex = 'FEFF';
    for (const ch of String(s)) {
      const c = ch.codePointAt(0);
      if (c > 0xffff) continue;
      hex += c.toString(16).padStart(4, '0').toUpperCase();
    }
    return `<${hex}>`;
  }

  // pages: niz Uint8Array (PNG); meta: { title, sizes: [[wPt, hPt], ...], quality }
  async function build(pages, metaJson) {
    const meta = JSON.parse(metaJson);
    const chunks = [];
    let len = 0;
    const offsets = [];
    const push = (x) => {
      const b = typeof x === 'string' ? enc.encode(x) : x;
      chunks.push(b);
      len += b.length;
    };
    const obj = (n, body) => {
      offsets[n] = len;
      push(`${n} 0 obj\n`);
      for (const part of body) push(part);
      push('\nendobj\n');
    };
    push('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n');
    const n = pages.length;
    // 1 katalog, 2 stranice, 3 podaci; zatim po stranici: stranica, sadržaj, slika
    const pageObj = (i) => 4 + i * 3;
    const kids = Array.from({ length: n }, (_, i) => `${pageObj(i)} 0 R`).join(' ');
    obj(1, ['<< /Type /Catalog /Pages 2 0 R >>']);
    obj(2, [`<< /Type /Pages /Kids [${kids}] /Count ${n} >>`]);
    const d = new Date();
    const pad = (v) => String(v).padStart(2, '0');
    const date = `D:${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
    obj(3, [`<< /Title ${pdfText(meta.title || 'Planstratiq')} /Producer (Planstratiq) /Creator (Planstratiq) /CreationDate (${date}) >>`]);
    for (let i = 0; i < n; i++) {
      const [wPt, hPt] = meta.sizes[i];
      const img = await pngToJpeg(pages[i], meta.quality || 0.9);
      const p = pageObj(i);
      const content = `q ${wPt.toFixed(2)} 0 0 ${hPt.toFixed(2)} 0 0 cm /Im0 Do Q`;
      obj(p, [`<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${wPt.toFixed(2)} ${hPt.toFixed(2)}] /Resources << /XObject << /Im0 ${p + 2} 0 R >> >> /Contents ${p + 1} 0 R >>`]);
      obj(p + 1, [`<< /Length ${content.length} >>\nstream\n${content}\nendstream`]);
      obj(p + 2, [
        `<< /Type /XObject /Subtype /Image /Width ${img.w} /Height ${img.h} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${img.bytes.length} >>\nstream\n`,
        img.bytes,
        '\nendstream',
      ]);
    }
    const total = 4 + n * 3;
    const xref = len;
    let x = `xref\n0 ${total}\n0000000000 65535 f \n`;
    for (let i = 1; i < total; i++) x += String(offsets[i]).padStart(10, '0') + ' 00000 n \n';
    push(x);
    push(`trailer\n<< /Size ${total} /Root 1 0 R /Info 3 0 R >>\nstartxref\n${xref}\n%%EOF\n`);
    const out = new Uint8Array(len);
    let o = 0;
    for (const c of chunks) {
      out.set(c, o);
      o += c.length;
    }
    return out;
  }

  window.psqPdf = { build };
})();
