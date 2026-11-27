// Planstratiq – veliki podaci projekta (slike nacrta) u IndexedDB-u; localStorage ima samo ~5 MB.
(function () {
  let dbp = null;
  function db() {
    if (!dbp) {
      dbp = new Promise((res, rej) => {
        const r = indexedDB.open('planstratiq', 1);
        r.onupgradeneeded = () => r.result.createObjectStore('blobs');
        r.onsuccess = () => res(r.result);
        r.onerror = () => rej(r.error);
      });
      // zamoli preglednik da podatke ne briše sam kad ponestane mjesta
      try { navigator.storage && navigator.storage.persist && navigator.storage.persist(); } catch (_) {}
    }
    return dbp;
  }
  function tx(mode, f) {
    return db().then((d) => new Promise((res, rej) => {
      const t = d.transaction('blobs', mode);
      const st = t.objectStore('blobs');
      let out = null;
      const r = f(st);
      if (r) r.onsuccess = () => { out = r.result; };
      t.oncomplete = () => res(out === undefined ? null : out);
      t.onerror = () => rej(t.error);
      t.onabort = () => rej(t.error);
    }));
  }
  window.psqStore = {
    get: (k) => tx('readonly', (s) => s.get(k)).then((v) => (typeof v === 'string' ? v : null)).catch(() => null),
    put: (k, v) => tx('readwrite', (s) => s.put(v, k)).then(() => true).catch(() => false),
    del: (k) => tx('readwrite', (s) => s.delete(k)).then(() => true).catch(() => false),
    // obriši sve ključeve koji počinju s prefiksom
    delPrefix: (p) => tx('readwrite', (s) => s.delete(IDBKeyRange.bound(p, p + '￿'))).then(() => true).catch(() => false),
  };
})();
