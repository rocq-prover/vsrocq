// A file system for the wasm_of_ocaml runtime outside of node
// (globalThis.jsoo_fs), serving a published opam root over HTTP.
//
// The files listed in the manifest (see make-web-root.py) are mounted at
// manifest.prefix, the prefix of the opam switch they come from, so that
// the paths compiled in the programs (findlib.conf, Rocq's coqlib) work
// unchanged. Their content is fetched when they are opened, with a
// synchronous XMLHttpRequest (allowed in a Web Worker), and cached.
// prefetch() fetches files in parallel beforehand.
//
// Files listed in manifest.compressed are published compressed with gzip,
// at their path followed by "z" (e.g. Foo.voz), and are decompressed when
// fetched (see gunzip below): the size in manifest.files is the size of
// the decompressed file.
//
// The published files are read only; files can be created in memory
// anywhere else (or replace published ones), by the program or with
// writeFile (e.g. to mirror the files of the workspace). Writes to fd 1
// and 2 go to the stdout and stderr callbacks, by default the console.
//
// The API is the subset of node:fs used by the wasm_of_ocaml runtime.
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

function makeLazyFs(manifest, baseUrl,
    { cwd = "/static", log = null, stdout = null, stderr = null } = {}) {
  const prefix = manifest.prefix.replace(/\/+$/, "");
  const files = new Map(); // absolute path -> { size, url, gzip }
  const dirs = new Set(["/"]);
  const cache = new Map(); // url -> Uint8Array
  const overlay = new Map(); // absolute path -> { data: Uint8Array, size }
  const overlayDirs = new Set();
  const misses = new Set();
  const written = new Set(); // the files opened for writing by the program
  const mtime = Date.now();

  function addDirs(p) {
    for (let i = p.lastIndexOf("/"); i > 0; i = p.lastIndexOf("/", i - 1))
      dirs.add(p.slice(0, i));
  }
  const compressed = manifest.compressed ?? {};
  for (const [rel, size] of Object.entries(manifest.files)) {
    const p = prefix + "/" + rel;
    const gzip = Object.hasOwn(compressed, rel);
    files.set(p, { size, gzip, url: new URL(gzip ? rel + "z" : rel, baseUrl).href });
    addDirs(p);
  }
  dirs.add(prefix);
  // the current directory of the wasm_of_ocaml runtime outside of node
  dirs.add(cwd);
  addDirs(cwd);

  function normalize(p) {
    if (typeof p !== "string") p = String(p);
    if (!p.startsWith("/")) p = cwd + "/" + p;
    const out = [];
    for (const c of p.split("/")) {
      if (c === "" || c === ".") continue;
      if (c === "..") out.pop();
      else out.push(c);
    }
    return "/" + out.join("/");
  }

  function error(code, syscall, path) {
    const msgs = {
      ENOENT: "no such file or directory",
      ENOTDIR: "not a directory",
      EISDIR: "illegal operation on a directory",
      EBADF: "bad file descriptor",
      EROFS: "read-only file system",
      EEXIST: "file already exists",
      ENOSYS: "function not implemented",
      EIO: "i/o error",
    };
    const e = new Error(`${code}: ${msgs[code]}, ${syscall} '${path}'`);
    e.code = code;
    e.syscall = syscall;
    e.path = path;
    return e;
  }

  function isDir(p) {
    return dirs.has(p) || overlayDirs.has(p);
  }
  function kind(p) {
    if (overlay.has(p)) return "file";
    if (isDir(p)) return "dir";
    if (files.has(p)) return "file";
    return null;
  }
  function miss(p) {
    if (log && !misses.has(p)) log("lazyfs: no " + p);
    misses.add(p);
  }

  function fetchSync(url) {
    const xhr = new XMLHttpRequest();
    xhr.open("GET", url, false);
    xhr.responseType = "arraybuffer";
    xhr.send();
    if (xhr.status !== 200 && xhr.status !== 0)
      throw new Error(`lazyfs: ${url}: HTTP ${xhr.status}`);
    return new Uint8Array(xhr.response);
  }
  function content(p) {
    const o = overlay.get(p);
    if (o) return o.data.subarray(0, o.size);
    const f = files.get(p);
    let data = cache.get(f.url);
    if (!data) {
      if (log) log("lazyfs: fetch " + p);
      data = fetchSync(f.url);
      if (f.gzip) data = gunzip(data, f.size);
      cache.set(f.url, data);
    }
    return data;
  }

  async function prefetch(rels, { parallel = 16 } = {}) {
    const todo = rels
      .map((rel) => files.get(prefix + "/" + rel))
      .filter((f) => f && !cache.has(f.url));
    let i = 0;
    async function worker() {
      while (i < todo.length) {
        const f = todo[i++];
        const r = await fetch(f.url);
        if (!r.ok) continue;
        const data = new Uint8Array(await r.arrayBuffer());
        cache.set(f.url, f.gzip ? gunzip(data, f.size) : data);
      }
    }
    await Promise.all(new Array(parallel).fill(0).map(worker));
  }

  function stats(p, k, size) {
    const file = k === "file";
    return {
      dev: 1,
      ino: 0,
      mode: file ? 0o100644 : 0o40755,
      nlink: 1,
      uid: 0,
      gid: 0,
      rdev: 0,
      size,
      blksize: 4096,
      blocks: Math.ceil(size / 512),
      atimeMs: mtime,
      mtimeMs: mtime,
      ctimeMs: mtime,
      birthtimeMs: mtime,
      isFile: () => file,
      isDirectory: () => !file,
      isCharacterDevice: () => false,
      isBlockDevice: () => false,
      isSymbolicLink: () => false,
      isFIFO: () => false,
      isSocket: () => false,
    };
  }
  function sizeOf(p) {
    const o = overlay.get(p);
    if (o) return o.size;
    const f = files.get(p);
    return f ? f.size : 0;
  }
  function withBigint(s, opts) {
    if (opts && opts.bigint) for (const k of ["size", "dev", "ino"]) s[k] = BigInt(s[k]);
    return s;
  }

  const fds = new Map(); // fd -> { path, pos, write }
  let nextFd = 100;

  const constants = {
    R_OK: 4, W_OK: 2, X_OK: 1, F_OK: 0,
    O_RDONLY: 0, O_WRONLY: 1, O_RDWR: 2, O_APPEND: 1024, O_CREAT: 64,
    O_TRUNC: 512, O_EXCL: 128, O_NONBLOCK: 2048, O_NOCTTY: 256,
    O_DSYNC: 4096, O_SYNC: 1052672,
  };
  const decoder = new TextDecoder();

  function ensureCapacity(o, n) {
    if (o.data.length >= n) return;
    const d = new Uint8Array(Math.max(n, 2 * o.data.length, 1024));
    d.set(o.data.subarray(0, o.size));
    o.data = d;
  }

  const fs = {
    constants,
    existsSync: (p) => kind(normalize(p)) !== null,
    statSync: (p0, opts) => {
      const p = normalize(p0);
      const k = kind(p);
      if (!k) {
        miss(p);
        if (opts && opts.throwIfNoEntry === false) return undefined;
        throw error("ENOENT", "stat", p0);
      }
      return withBigint(stats(p, k, k === "file" ? sizeOf(p) : 4096), opts);
    },
    lstatSync: (p, opts) => fs.statSync(p, opts),
    fstatSync: (fd, opts) => {
      const f = fds.get(fd);
      if (!f) throw error("EBADF", "fstat", fd);
      return withBigint(stats(f.path, "file", sizeOf(f.path)), opts);
    },
    accessSync: (p0, mode) => {
      const p = normalize(p0);
      const k = kind(p);
      if (!k) { miss(p); throw error("ENOENT", "access", p0); }
    },
    openSync: (p0, flags = 0, _perm) => {
      const p = normalize(p0);
      const write = (flags & 3) !== 0;
      let k = kind(p);
      if (k === "dir") throw error("EISDIR", "open", p0);
      if (write) {
        if (k && flags & constants.O_EXCL && flags & constants.O_CREAT)
          throw error("EEXIST", "open", p0);
        if (!k && !(flags & constants.O_CREAT)) throw error("ENOENT", "open", p0);
        const dir = p.slice(0, p.lastIndexOf("/")) || "/";
        if (!isDir(dir)) throw error("ENOENT", "open", p0);
        if (!overlay.has(p)) {
          // copy on write
          const data = k ? content(p).slice() : new Uint8Array(0);
          overlay.set(p, { data, size: data.length });
        }
        const o = overlay.get(p);
        if (flags & constants.O_TRUNC) o.size = 0;
        written.add(p);
      } else if (!k) {
        miss(p);
        throw error("ENOENT", "open", p0);
      } else content(p); // fetch now, so that errors are reported by open
      const fd = nextFd++;
      fds.set(fd, { path: p, pos: 0, write, append: !!(flags & constants.O_APPEND) });
      return fd;
    },
    closeSync: (fd) => {
      if (!fds.delete(fd)) throw error("EBADF", "close", fd);
    },
    readSync: (fd, buf, off, len, pos) => {
      const f = fds.get(fd);
      if (!f) throw error("EBADF", "read", fd);
      const data = content(f.path);
      const start = pos === null || pos === undefined ? f.pos : Number(pos);
      const n = Math.max(0, Math.min(len, data.length - start));
      buf.set(data.subarray(start, start + n), off);
      if (pos === null || pos === undefined) f.pos = start + n;
      return n;
    },
    writeSync: (fd, b, off, len, pos) => {
      if (typeof b === "string") b = new TextEncoder().encode(b), off = 0, len = b.length;
      if (fd === 1 || fd === 2) {
        const s = decoder.decode(b.subarray(off, off + len));
        const out = fd === 1 ? stdout : stderr;
        if (out) out(s);
        else (fd === 2 ? console.error : console.log)(s.replace(/\n$/, ""));
        return len;
      }
      const f = fds.get(fd);
      if (!f || !f.write) throw error("EBADF", "write", fd);
      const o = overlay.get(f.path);
      let start = pos === null || pos === undefined ? f.pos : Number(pos);
      if (f.append) start = o.size;
      ensureCapacity(o, start + len);
      o.data.set(b.subarray(off, off + len), start);
      o.size = Math.max(o.size, start + len);
      if (pos === null || pos === undefined) f.pos = start + len;
      return len;
    },
    fsyncSync: () => {},
    ftruncateSync: (fd, l = 0) => {
      const f = fds.get(fd);
      if (!f || !f.write) throw error("EBADF", "ftruncate", fd);
      overlay.get(f.path).size = l;
    },
    readdirSync: (p0) => {
      const p = normalize(p0);
      if (!isDir(p)) {
        if (kind(p)) throw error("ENOTDIR", "scandir", p0);
        miss(p);
        throw error("ENOENT", "scandir", p0);
      }
      const pre = p === "/" ? "/" : p + "/";
      const entries = new Set();
      for (const set of [files.keys(), overlay.keys(), dirs, overlayDirs])
        for (const q of set)
          if (q.startsWith(pre) && q.length > pre.length) {
            const rest = q.slice(pre.length);
            const i = rest.indexOf("/");
            entries.add(i < 0 ? rest : rest.slice(0, i));
          }
      return [...entries];
    },
    opendirSync: (p) => {
      const entries = fs.readdirSync(p);
      return {
        readSync: () => {
          const n = entries.shift();
          return n === undefined ? null : { name: n };
        },
        closeSync: () => {},
      };
    },
    mkdirSync: (p0) => {
      const p = normalize(p0);
      if (kind(p)) throw error("EEXIST", "mkdir", p0);
      overlayDirs.add(p);
    },
    rmdirSync: (p0) => {
      const p = normalize(p0);
      if (!overlayDirs.delete(p)) throw error(dirs.has(p) ? "EROFS" : "ENOENT", "rmdir", p0);
    },
    unlinkSync: (p0) => {
      const p = normalize(p0);
      if (!overlay.delete(p)) throw error(files.has(p) ? "EROFS" : "ENOENT", "unlink", p0);
    },
    renameSync: (a0, b0) => {
      const a = normalize(a0), b = normalize(b0);
      const o = overlay.get(a);
      if (!o) throw error(files.has(a) ? "EROFS" : "ENOENT", "rename", a0);
      overlay.delete(a);
      overlay.set(b, o);
      if (written.delete(a)) written.add(b);
    },
  };
  for (const f of ["chmodSync", "fchmodSync", "linkSync", "symlinkSync",
    "readlinkSync", "truncateSync", "utimesSync"])
    fs[f] = (p) => { throw error("ENOSYS", f.replace(/Sync$/, ""), p); };

  // Add (or replace) a file, creating its directories
  function writeFile(p0, data) {
    const p = normalize(p0);
    overlay.set(p, { data, size: data.length });
    for (let i = p.lastIndexOf("/"); i > 0; i = p.lastIndexOf("/", i - 1)) {
      const d = p.slice(0, i);
      if (!dirs.has(d)) overlayDirs.add(d);
    }
  }
  function removeFile(p0) {
    overlay.delete(normalize(p0));
  }
  // The files written by the program: [[path, Uint8Array]]
  function writtenFiles() {
    return [...written].filter((p) => overlay.has(p)).map((p) => [p, content(p).slice()]);
  }

  return { fs, prefetch, misses, prefix, writeFile, removeFile, writtenFiles };
}

if (typeof module === "object") module.exports = { makeLazyFs, gunzip };
else globalThis.makeLazyFs = makeLazyFs;
