// The script of the Web Workers running the language server, or a rocq
// command, in VS Code for the web. It does not depend on their version: it
// loads their glue (worker.js or runner.js, and lazyfs.js) from the
// published opam root given in the first message:
//   server: {init: {root, interrupt?, args?, debug?}}
//   rocq:   {init: {root, run: {args, files}, debug?}}
// See web/worker.js and web/runner.js in the vsrocq sources.
"use strict";
const queue = [];

async function load(url) {
  const r = await fetch(url);
  if (!r.ok) throw new Error(`${url}: HTTP ${r.status}`);
  const blob = new Blob([await r.text()], { type: "text/javascript" });
  const u = URL.createObjectURL(blob);
  try { importScripts(u); } finally { URL.revokeObjectURL(u); }
}

async function boot(init) {
  try {
    const root = new URL(init.root, self.location.href).href;
    const r = await fetch(new URL("manifest.json", root));
    if (!r.ok) throw new Error(`${root}manifest.json: HTTP ${r.status}`);
    const manifest = await r.json();
    await load(new URL(manifest.lazyfs, root));
    // installs self.onmessage
    await load(new URL(init.run ? manifest.runner : manifest.worker, root));
    const handler = self.onmessage;
    queue[0] = { init: { ...init, root, manifest } };
    for (const data of queue) handler({ data });
  } catch (e) {
    self.postMessage({ error: String(e) });
  }
}

self.onmessage = (e) => {
  queue.push(e.data);
  if (queue.length === 1) boot(e.data.init);
};
