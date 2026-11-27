// The language server for desktop VS Code with vsrocq.useWasm: the server of
// a published opam root (vsrocq.web.root, see vsrocq-make-web-root), compiled
// to WebAssembly, run by the node of VS Code. Started by vscode-languageclient,
// it speaks LSP on stdin/stdout, like vsrocqtop.
//
//   node node-server.js ROOT CACHE [server args...]
//
// ROOT is the URL of the root, CACHE a directory where the server (its .js
// and .wasm files) and the glue of the root (lazyfs.js) are downloaded, so
// that the server and the libraries always come from the same root. The
// server runs in a worker thread (node-worker.js), where the files of the
// root are fetched when they are read, as in the browser: the worker waits
// (Atomics.wait) while this thread fetches them. The other files are the
// ones of the computer (e.g. the workspace).
//
// To interrupt Rocq, the shared interrupt flag is set when the client sends
// prover/interrupt or edits a document, as in the browser.
"use strict";
const { Worker, MessageChannel } = require("node:worker_threads");
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");

const [root0, cacheBase, ...userArgs] = process.argv.slice(2);
const root = root0.endsWith("/") ? root0 : root0 + "/";
const log = (s) => process.stderr.write(`[vsrocq wasm] ${s}\n`);

async function get(rel) {
  const url = new URL(rel, root).href;
  const r = await fetch(url);
  if (!r.ok) throw new Error(`${url}: HTTP ${r.status}`);
  return new Uint8Array(await r.arrayBuffer());
}

// Download a file of the root into the cache, unless it is there with the
// right size; compressed files are decompressed
async function download(manifest, rel, dir, gunzip) {
  const size = manifest.files[rel];
  const dest = path.join(dir, rel);
  if (size !== undefined && fs.statSync(dest, { throwIfNoEntry: false })?.size === size)
    return dest;
  const gz = Object.hasOwn(manifest.compressed ?? {}, rel);
  let data = await get(gz ? rel + "z" : rel);
  if (gz) data = gunzip(data, size);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.writeFileSync(dest + ".tmp", data);
  fs.renameSync(dest + ".tmp", dest);
  return dest;
}

async function main() {
  const t0 = Date.now();
  const manifest = JSON.parse(new TextDecoder().decode(await get("manifest.json")));
  // one cache directory per root
  const id = crypto.createHash("sha256").update(root).digest("hex").slice(0, 16);
  const dir = path.join(cacheBase, id);
  // lazyfs.js is small and must match the root: always downloaded
  fs.mkdirSync(dir, { recursive: true });
  const lazyfs = path.join(dir, "lazyfs.js");
  fs.writeFileSync(lazyfs, await get(manifest.lazyfs));
  const { gunzip } = require(lazyfs);
  // the server and its assets
  fs.rmSync(path.join(dir, manifest.server), { force: true });
  const assets = manifest.server.replace(/\.js$/, ".assets/");
  const rels = Object.keys(manifest.files).filter((r) => r.startsWith(assets));
  for (const rel of [manifest.server, ...rels]) await download(manifest, rel, dir, gunzip);
  log(`server of ${root} in ${dir} (${Date.now() - t0}ms)`);

  const interrupt = new SharedArrayBuffer(4);
  const flag = new Int32Array(interrupt);
  // the synchronous fetches of the worker
  const fetched = new SharedArrayBuffer(4);
  const done = new Int32Array(fetched);
  const { port1, port2 } = new MessageChannel();
  port1.on("message", async (url) => {
    let reply;
    try {
      const r = await fetch(url);
      reply = { status: r.status, data: r.ok ? await r.arrayBuffer() : null };
    } catch (e) {
      reply = { status: 0, error: String(e) };
    }
    port1.postMessage(reply, reply.data ? [reply.data] : []);
    Atomics.store(done, 0, 1);
    Atomics.notify(done, 0);
  });

  const worker = new Worker(path.join(__dirname, "node-worker.js"), {
    argv: [...manifest.args, ...userArgs],
    workerData: {
      root, manifest, interrupt, fetched, port: port2,
      server: path.join(dir, manifest.server), lazyfs,
    },
    transferList: [port2],
    stdout: true,
    stderr: true,
    // the server uses much more stack than the native one
    resourceLimits: { stackSizeMb: 256 },
  });
  // stdout is the protocol: what the server prints goes to stderr
  worker.stdout.pipe(process.stderr);
  worker.stderr.pipe(process.stderr);
  worker.on("message", (m) => {
    const b = Buffer.from(m, "utf8");
    process.stdout.write(`Content-Length: ${b.length}\r\n\r\n`);
    process.stdout.write(b);
  });
  worker.on("error", (e) => { log(`worker error: ${e?.stack ?? e}`); process.exit(1); });
  worker.on("exit", (c) => process.exit(c));

  const interrupting = /"method"\s*:\s*"(prover\/interrupt|textDocument\/didChange)"/;
  let buf = Buffer.alloc(0);
  process.stdin.on("data", (d) => {
    buf = Buffer.concat([buf, d]);
    for (;;) {
      const i = buf.indexOf("\r\n\r\n");
      if (i < 0) return;
      const m = /Content-Length: *(\d+)/i.exec(buf.subarray(0, i).toString("ascii"));
      if (!m) { log("no Content-Length"); process.exit(1); }
      const n = Number(m[1]);
      if (buf.length < i + 4 + n) return;
      const msg = buf.subarray(i + 4, i + 4 + n).toString("utf8");
      buf = buf.subarray(i + 4 + n);
      if (interrupting.test(msg)) Atomics.store(flag, 0, 1);
      worker.postMessage(msg);
    }
  });
  process.stdin.on("end", () => process.exit(0));
}

main().catch((e) => {
  log(`cannot start the server: ${e?.stack ?? e}`);
  process.exit(1);
});
