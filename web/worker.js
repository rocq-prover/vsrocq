// Glue between the wasm language server and its host, for node
// worker_threads (testing) and browser Web Workers.
//
// The host sends an init message first, then LSP messages: JSON strings
// with node, objects (or strings) in a browser, as vscode-languageclient
// does. The server posts back LSP messages in the same format.
// To interrupt Rocq the host sets the first Int32 of the shared buffer to 1;
// the flag is cleared when the worker receives a message while idle, so
// the host can set it whenever a message (e.g. an edit) should interrupt
// the current computation.
// With node, the worker also posts {ready: true} once the server started.
//
// In a browser, {fs: {write: [[path, Uint8Array], ...], remove: [path, ...]}}
// adds files to (or removes files from) the file system of the server, e.g.
// to mirror the files of the workspace.
//
// node:    {init: {server, interrupt}}, where server is the path of
//          vsrocq_web.bc.wasm.js; the command line is the worker's argv.
// browser: {init: {root, manifest?, interrupt?, args?, debug?}}, where root
//          is the URL of a published opam root (see make-web-root.py), whose
//          files are served by lazyfs.js (makeLazyFs must be defined).
//          The command line is manifest.args unless args is given.
"use strict";
const isNode = typeof process === "object" && process.versions && process.versions.node;
const port = isNode ? require("worker_threads").parentPort : self;
const post = (m) => port.postMessage(m);
const onMessage = (f) => isNode ? port.on("message", f) : (self.onmessage = (e) => f(e.data));

let flag = null;
let pending = [];
let ready = false;
let lfs = null;
let fsPending = [];

function applyFs({ write = [], remove = [] }) {
  for (const [p, data] of write) lfs.writeFile(p, data);
  for (const p of remove) lfs.removeFile(p);
}

globalThis.vsrocqSend = isNode ? (s) => post(s) : (s) => post(JSON.parse(s));
globalThis.vsrocqInterrupted = () => flag !== null && Atomics.exchange(flag, 0, 0) !== 0;

globalThis.vsrocqReady = () => {
  ready = true;
  for (const m of pending) globalThis.vsrocq.push(m);
  pending = [];
  if (isNode) post({ ready: true });
};

// Load a script from another origin: when cross-origin isolated, a Web
// Worker can't importScripts a script without a CORP header (GitHub Pages
// does not send one), so fetch it (CORS) and go through a blob.
async function importUrl(url) {
  const r = await fetch(url);
  if (!r.ok) throw new Error(`${url}: HTTP ${r.status}`);
  const blob = new Blob([await r.text()], { type: "text/javascript" });
  const u = URL.createObjectURL(blob);
  try { importScripts(u); } finally { URL.revokeObjectURL(u); }
}

async function startBrowser(init) {
  const root = new URL(init.root, self.location.href).href;
  const manifest = init.manifest ??
    await (await fetch(new URL("manifest.json", root))).json();
  const log = init.debug ? (s) => console.log(s) : null;
  const t0 = performance.now();
  lfs = makeLazyFs(manifest, root, { log });
  for (const m of fsPending) applyFs(m);
  fsPending = [];
  globalThis.jsoo_fs = lfs.fs;
  // no environment variable in a browser: Rocq wants a home directory
  globalThis.jsoo_env = { HOME: "/static", ...globalThis.jsoo_env };

  globalThis.jsoo_argv = ["vsrocqtop", ...(init.args ?? manifest.args)];
  globalThis.vsrocqFs = lfs;
  await lfs.prefetch(manifest.prefetch);
  if (log) log(`vsrocq: prefetched in ${Math.round(performance.now() - t0)}ms`);
  const server = new URL(manifest.server, root).href;
  // the wasm loader finds its assets relative to the current script
  globalThis.document = { currentScript: { src: server } };
  await importUrl(server);
}

onMessage((m) => {
  if (typeof m === "object" && m.init) {
    if (m.init.interrupt) flag = new Int32Array(m.init.interrupt);
    if (isNode) require(m.init.server);
    else startBrowser(m.init).catch((e) => {
      console.error("vsrocq: cannot start the server", e);
      post({ jsonrpc: "2.0", method: "window/logMessage",
             params: { type: 1, message: "Cannot start the language server: " + e } });
    });
    return;
  }
  if (typeof m === "object" && m.fs) {
    if (lfs) applyFs(m.fs); else fsPending.push(m.fs);
    return;
  }
  if (typeof m !== "string") m = JSON.stringify(m);
  // idle: an interruption request is about this message, which comes too late
  if (flag !== null) Atomics.store(flag, 0, 0);
  if (!ready) { pending.push(m); return; }
  globalThis.vsrocq.push(m);
});
