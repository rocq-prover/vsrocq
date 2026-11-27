// Run the wasm language server in a node worker thread, speaking LSP on
// stdio (like vsrocqtop). For testing. When the client sends
// prover/interrupt the shared interrupt flag is set (as the web client does).
// Usage: node node-bridge.js path/to/vsrocq_web.bc.wasm.js [server args...]
"use strict";
const { Worker } = require("worker_threads");
const path = require("path");
const server = path.resolve(process.argv[2]);
const interrupt = new SharedArrayBuffer(4);
const flag = new Int32Array(interrupt);
const worker = new Worker(path.join(__dirname, "worker.js"),
  { argv: process.argv.slice(3), stdout: false, stderr: false });
worker.postMessage({ init: { server, interrupt } });
worker.on("message", (m) => {
  if (typeof m !== "string") return;
  const b = Buffer.from(m, "utf8");
  process.stdout.write(`Content-Length: ${b.length}\r\n\r\n`);
  process.stdout.write(b);
});
worker.on("error", (e) => { console.error("worker error", e); process.exit(1); });
worker.on("exit", (c) => process.exit(c));
let buf = Buffer.alloc(0);
process.stdin.on("data", (d) => {
  buf = Buffer.concat([buf, d]);
  for (;;) {
    const i = buf.indexOf("\r\n\r\n");
    if (i < 0) return;
    const m = /Content-Length: *(\d+)/i.exec(buf.slice(0, i).toString());
    const n = parseInt(m[1]);
    if (buf.length < i + 4 + n) return;
    const msg = buf.slice(i + 4, i + 4 + n).toString("utf8");
    buf = buf.slice(i + 4 + n);
    if (msg.includes('"prover/interrupt"')) { Atomics.store(flag, 0, 1); }
    worker.postMessage(msg);
  }
});
process.stdin.on("end", () => process.exit(0));
