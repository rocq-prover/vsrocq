// The worker thread of node-server.js: runs the wasm language server of a
// published root, or one of its programs (rocq c, rocq dep: workerData.run),
// with the file system of the computer, except below the prefix of the root
// (the prefix of the switch it was made from), where the files are the ones
// of the root, fetched when they are read (lazyfs.js of the root, as in the
// browser). The command line is the worker's argv.
"use strict";
const { workerData, parentPort, receiveMessageOnPort } = require("node:worker_threads");
const nodefs = require("node:fs");

const { root, manifest, interrupt, fetched, port, server, lazyfs, run } = workerData;
const flag = new Int32Array(interrupt);
const done = new Int32Array(fetched);

// The synchronous XMLHttpRequest used by lazyfs.js: the main thread fetches
// the URL while this thread waits
globalThis.XMLHttpRequest = class {
  open(_method, url) { this.url = url; }
  send() {
    Atomics.store(done, 0, 0);
    port.postMessage(this.url);
    Atomics.wait(done, 0, 0);
    const r = receiveMessageOnPort(port).message;
    if (r.error) throw new Error(`${this.url}: ${r.error}`);
    this.status = r.status;
    this.response = r.data;
  }
};

const { makeLazyFs } = require(lazyfs);
const lfs = makeLazyFs(manifest, root, {
  cwd: process.cwd(),
  log: process.env.VSROCQ_WASM_DEBUG ? (s) => console.error(s) : null,
  stdout: (s) => process.stdout.write(s),
  stderr: (s) => process.stderr.write(s),
});

// The file system of the server: the root below its prefix, the computer
// elsewhere. The file descriptors of the root are shifted by ROOT_FD, so
// that they do not collide with the ones of the computer. For the server,
// writes to the standard output go to stderr: in a worker thread, fd 1 is
// the stdout of the process, the protocol.
const prefix = lfs.prefix;
const inRoot = (p) =>
  typeof p === "string" && (p === prefix || p.startsWith(prefix + "/"));
const ROOT_FD = 1 << 20;
const byPath = (name) => (p, ...args) =>
  (inRoot(p) ? lfs.fs : nodefs)[name](p, ...args);
const byFd = (name) => (fd, ...args) =>
  fd >= ROOT_FD
    ? lfs.fs[name](fd - ROOT_FD, ...args)
    : nodefs[name](fd === 1 && !run ? 2 : fd, ...args);
const fs = { constants: nodefs.constants };
for (const name of ["existsSync", "statSync", "lstatSync", "accessSync",
  "readdirSync", "opendirSync", "mkdirSync", "rmdirSync", "unlinkSync",
  "chmodSync", "truncateSync", "utimesSync", "readlinkSync", "symlinkSync"])
  fs[name] = byPath(name);
for (const name of ["fstatSync", "readSync", "writeSync", "fsyncSync",
  "ftruncateSync", "fchmodSync"])
  fs[name] = byFd(name);
fs.openSync = (p, ...args) =>
  inRoot(p) ? lfs.fs.openSync(p, ...args) + ROOT_FD : nodefs.openSync(p, ...args);
fs.closeSync = byFd("closeSync");
fs.renameSync = (a, b) => {
  if (inRoot(a) !== inRoot(b)) {
    const e = new Error(`EXDEV: cross-device link not permitted, rename '${a}' -> '${b}'`);
    e.code = "EXDEV";
    throw e;
  }
  return (inRoot(a) ? lfs.fs : nodefs).renameSync(a, b);
};
fs.linkSync = (a, b) => (inRoot(a) ? lfs.fs : nodefs).linkSync(a, b);
globalThis.jsoo_fs = fs;

if (run) {
  lfs.prefetch(manifest.prefetch).then(() => require(server));
  return;
}

// The LSP glue of the server (see vsrocq_web.ml)
let ready = false;
let pending = [];
globalThis.vsrocqSend = (s) => parentPort.postMessage(s);
globalThis.vsrocqInterrupted = () => Atomics.exchange(flag, 0, 0) !== 0;
globalThis.vsrocqReady = () => {
  ready = true;
  for (const m of pending) globalThis.vsrocq.push(m);
  pending = [];
};
parentPort.on("message", (m) => {
  // idle: an interruption request is about this message, which comes too late
  Atomics.store(flag, 0, 0);
  if (ready) globalThis.vsrocq.push(m);
  else pending.push(m);
});

lfs.prefetch(manifest.prefetch).then(() => require(server), (e) => {
  console.error(`vsrocq: cannot prefetch: ${e}`);
  require(server);
});
