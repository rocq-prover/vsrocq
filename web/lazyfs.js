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
// The published files are read only; files can be created in memory
// anywhere else (or replace published ones), by the program or with
// writeFile (e.g. to mirror the files of the workspace). Writes to fd 1
// and 2 go to the stdout and stderr callbacks, by default the console.
//
// The API is the subset of node:fs used by the wasm_of_ocaml runtime.
"use strict";

function makeLazyFs(manifest, baseUrl,
    { cwd = "/static", log = null, stdout = null, stderr = null } = {}) {
  const prefix = manifest.prefix.replace(/\/+$/, "");
  const files = new Map(); // absolute path -> { size, url }
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
  for (const [rel, size] of Object.entries(manifest.files)) {
    const p = prefix + "/" + rel;
    files.set(p, { size, url: new URL(rel, baseUrl).href });
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
        if (r.ok) cache.set(f.url, new Uint8Array(await r.arrayBuffer()));
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

if (typeof module === "object") module.exports = { makeLazyFs };
else globalThis.makeLazyFs = makeLazyFs;
