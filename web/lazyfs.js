// The files of a published opam root (see vsrocq-make-web-root), served
// over HTTP, for the pseudo filesystem of the wasm_of_ocaml runtime outside
// of node.
//
// The files listed in the manifest are created as lazy files of the
// runtime at manifest.prefix, the prefix of the opam switch they come from,
// so that the paths compiled in the programs (findlib.conf, Rocq's coqlib)
// work unchanged: they exist and are listed in their directories, with
// their size, and their content is only fetched when they are read, with a
// synchronous XMLHttpRequest (allowed in a Web Worker), and cached.
// prefetch() fetches files in parallel beforehand. Paths which are not in
// the manifest do not exist, and are never fetched.
//
// In manifest.files, a file published compressed with gzip, at its path
// followed by "z" (e.g. Foo.voz), has [size, compressed size] instead of its
// size; it is decompressed when fetched (see gunzip below). Roots of
// version 1 list them in manifest.compressed instead.
//
// install() gives the files to the runtime: before the program is loaded,
// with globalThis.jsoo_fs_tmp, otherwise with globalThis.jsoo_create_file.
// Outside of node, the runtime keeps the other files in memory: the program
// can write anywhere (even replace published files). Under node, the files
// can only be created in an in-memory device of the runtime, which the
// program mounts at the prefix (see rocq-web.host).
"use strict";

// Decompress a gzip file (RFC 1952, a single member) into a buffer of
// size bytes. It is synchronous, unlike DecompressionStream, because files
// are fetched synchronously. Huffman codes are decoded as in zlib's puff.
const gunzip = (() => {
  const LBASE = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35,
    43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258];
  const LEXT = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4,
    4, 4, 4, 5, 5, 5, 5, 0];
  const DBASE = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
    257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289,
    16385, 24577];
  const DEXT = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9,
    9, 10, 10, 11, 11, 12, 12, 13, 13];
  const ORDER = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];

  // a canonical Huffman code: the number of codes of each length, and the
  // symbols ordered by code
  function huffman(lengths, n) {
    const count = new Uint16Array(16), symbol = new Uint16Array(n);
    for (let i = 0; i < n; i++) count[lengths[i]]++;
    const offs = new Uint16Array(16);
    for (let len = 1; len < 15; len++) offs[len + 1] = offs[len] + count[len];
    for (let i = 0; i < n; i++) if (lengths[i]) symbol[offs[lengths[i]]++] = i;
    count[0] = 0;
    return { count, symbol };
  }
  const fixed = (() => {
    const l = new Uint8Array(288);
    l.fill(8, 0, 144); l.fill(9, 144, 256); l.fill(7, 256, 280); l.fill(8, 280, 288);
    return [huffman(l, 288), huffman(new Uint8Array(30).fill(5), 30)];
  })();

  return function gunzip(src, size) {
    if (src[0] !== 0x1f || src[1] !== 0x8b || src[2] !== 8)
      throw new Error("gunzip: not gzip data");
    const flags = src[3];
    let pos = 10;
    if (flags & 4) pos += 2 + (src[pos] | (src[pos + 1] << 8)); // FEXTRA
    if (flags & 8) while (src[pos++]); // FNAME
    if (flags & 16) while (src[pos++]); // FCOMMENT
    if (flags & 2) pos += 2; // FHCRC
    const out = new Uint8Array(size);
    let o = 0, buf = 0, cnt = 0;
    function bits(n) {
      while (cnt < n) {
        if (pos >= src.length) throw new Error("gunzip: truncated data");
        buf |= src[pos++] << cnt; cnt += 8;
      }
      const v = buf & ((1 << n) - 1);
      buf >>>= n; cnt -= n;
      return v;
    }
    function decode({ count, symbol }) {
      let code = 0, first = 0, index = 0;
      for (let len = 1; len < 16; len++) {
        if (cnt === 0) {
          if (pos >= src.length) throw new Error("gunzip: truncated data");
          buf = src[pos++]; cnt = 8;
        }
        code |= buf & 1; buf >>>= 1; cnt--;
        const c = count[len];
        if (code - c < first) return symbol[index + (code - first)];
        index += c; first = (first + c) << 1; code <<= 1;
      }
      throw new Error("gunzip: bad code");
    }
    let last;
    do {
      last = bits(1);
      const type = bits(2);
      if (type === 0) { // stored
        buf = 0; cnt = 0;
        const len = src[pos] | (src[pos + 1] << 8);
        pos += 4;
        if (o + len > size) throw new Error("gunzip: too much data");
        out.set(src.subarray(pos, pos + len), o);
        pos += len; o += len;
        continue;
      }
      let lit, dist;
      if (type === 1) [lit, dist] = fixed;
      else if (type === 2) {
        const nlen = bits(5) + 257, ndist = bits(5) + 1, ncode = bits(4) + 4;
        const lengths = new Uint8Array(320);
        for (let i = 0; i < ncode; i++) lengths[ORDER[i]] = bits(3);
        const lencode = huffman(lengths, 19);
        lengths.fill(0);
        for (let i = 0; i < nlen + ndist;) {
          const sym = decode(lencode);
          if (sym < 16) { lengths[i++] = sym; continue; }
          let len = 0, rep;
          if (sym === 16) {
            if (i === 0) throw new Error("gunzip: bad lengths");
            len = lengths[i - 1]; rep = 3 + bits(2);
          } else if (sym === 17) rep = 3 + bits(3);
          else rep = 11 + bits(7);
          if (i + rep > nlen + ndist) throw new Error("gunzip: bad lengths");
          while (rep--) lengths[i++] = len;
        }
        lit = huffman(lengths, nlen);
        dist = huffman(lengths.subarray(nlen), ndist);
      } else throw new Error("gunzip: bad block type");
      for (;;) {
        let sym = decode(lit);
        if (sym < 256) {
          if (o >= size) throw new Error("gunzip: too much data");
          out[o++] = sym;
        } else if (sym === 256) break;
        else {
          sym -= 257;
          if (sym >= 29) throw new Error("gunzip: bad length");
          const len = LBASE[sym] + bits(LEXT[sym]);
          const ds = decode(dist);
          if (ds >= 30) throw new Error("gunzip: bad distance");
          const d = DBASE[ds] + bits(DEXT[ds]);
          if (d > o) throw new Error("gunzip: distance too far");
          if (o + len > size) throw new Error("gunzip: too much data");
          if (d >= len) { out.copyWithin(o, o - d, o - d + len); o += len; }
          else for (let i = 0; i < len; i++, o++) out[o] = out[o - d];
        }
      }
    } while (!last);
    if (o !== size) throw new Error(`gunzip: ${o} bytes instead of ${size}`);
    return out;
  };
})();

// The size of a file of the manifest, and whether it is compressed
function fileEntry(manifest, rel, entry) {
  if (Array.isArray(entry)) return [entry[0], true];
  return [entry, Object.hasOwn(manifest.compressed ?? {}, rel)];
}

function makeLazyFs(manifest, baseUrl, { log = null } = {}) {
  const prefix = manifest.prefix.replace(/\/+$/, "");
  const entries = new Map(); // relative path -> [size, compressed]
  for (const [rel, entry] of Object.entries(manifest.files))
    entries.set(rel, fileEntry(manifest, rel, entry));
  const cache = new Map(); // relative path -> Uint8Array

  function fetchSync(url) {
    const xhr = new XMLHttpRequest();
    xhr.open("GET", url, false);
    xhr.responseType = "arraybuffer";
    xhr.send();
    if (xhr.status !== 200 && xhr.status !== 0)
      throw new Error(`lazyfs: ${url}: HTTP ${xhr.status}`);
    return new Uint8Array(xhr.response);
  }
  const gzip = (rel) => entries.get(rel)[1];
  const url = (rel) => new URL(gzip(rel) ? rel + "z" : rel, baseUrl).href;
  const decode = (rel, data) => gzip(rel) ? gunzip(data, entries.get(rel)[0]) : data;

  function content(rel) {
    let data = cache.get(rel);
    if (!data) {
      if (log) log("lazyfs: fetch " + rel);
      data = decode(rel, fetchSync(url(rel)));
      cache.set(rel, data);
    }
    return data;
  }

  async function prefetch(rels, { parallel = 16 } = {}) {
    const todo = rels.filter((rel) => entries.has(rel) && !cache.has(rel));
    let i = 0;
    async function worker() {
      while (i < todo.length) {
        const rel = todo[i++];
        const r = await fetch(url(rel));
        if (!r.ok) continue;
        cache.set(rel, decode(rel, new Uint8Array(await r.arrayBuffer())));
      }
    }
    await Promise.all(new Array(parallel).fill(0).map(worker));
  }

  // Give the files to the runtime; files is a Map of other files to
  // create, path -> Uint8Array (e.g. the files of the workspace)
  function install(files = new Map()) {
    const create = globalThis.jsoo_create_file
      ?? ((name, content) => (globalThis.jsoo_fs_tmp ??= []).push({ name, content }));
    for (const [rel, [size]] of entries)
      create(prefix + "/" + rel, { size, load: () => content(rel) });
    for (const [name, content] of files) create(name, content);
  }

  return { install, prefetch, prefix };
}

if (typeof module === "object") module.exports = { makeLazyFs, gunzip, fileEntry };
else globalThis.makeLazyFs = makeLazyFs;
