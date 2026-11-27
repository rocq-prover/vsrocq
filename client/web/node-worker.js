// The worker thread of node-server.js: runs the wasm language server of a
// published root, or one of its programs (rocq c, rocq dep: workerData.run),
// with the file system of the computer, except below the prefix of the root
// (the prefix of the switch it was made from), where the files are the ones
// of the root, fetched when they are read (lazyfs.js of the root, as in the
// browser). The command line is the worker's argv.
//
// Under node, the wasm_of_ocaml runtime uses the real file system, and files
// can only be created from JavaScript in an in-memory device: when it
// starts, the program calls rocqWebInit (rocq-web.host), which mounts one at
// the prefix and creates the files of the root there, as lazy files.
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

// process.chdir is not available in a worker thread. The runtime can still
// change directory into an in-memory device (e.g. Rocq computing the
// absolute path of a directory of the root), but then not back to the
// current directory: allow that one, since it does not change.
const cwd = process.cwd();
const chdir = process.chdir;
process.chdir = (d) => {
  if (require("node:path").resolve(cwd, d) !== cwd) chdir.call(process, d);
};

const { makeLazyFs } = require(lazyfs);
const lfs = makeLazyFs(manifest, root, {
  log: process.env.VSROCQ_WASM_DEBUG ? (s) => console.error(s) : null,
});
globalThis.rocqWebInit = (host) => {
  host.mount(lfs.prefix);
  lfs.install();
};

if (run) {
  lfs.prefetch(manifest.prefetch).then(() => require(server));
  return;
}

// For the server, writes to the standard output go to stderr: in a worker
// thread, fd 1 is the stdout of the process, the protocol. The runtime
// writes with node:fs.
const writeSync = nodefs.writeSync;
nodefs.writeSync = (fd, ...args) => writeSync(fd === 1 ? 2 : fd, ...args);

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
