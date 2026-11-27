// Run the rocq command of rocq-web (rocq c, rocq dep) once, in a browser
// Web Worker started by the extension's bootstrap.js.
//
// The host sends {init: {root, manifest, run: {args, files}}}, where files
// ([[path, Uint8Array], ...]) are added to the file system (e.g. the files
// of the workspace) and args is the command line after "rocq" (the first
// one is the subcommand, c or dep: a program of manifest.rocq). The worker
// posts back {exit, stdout, stderr, written}, where written are the files
// produced by compiling the .v files of args (their .vo, .vos and .vok,
// [[path, Uint8Array], ...]). The host should terminate the worker
// afterwards.
"use strict";

async function importUrl(url, before = () => {}) {
  const r = await fetch(url);
  if (!r.ok) throw new Error(`${url}: HTTP ${r.status}`);
  const blob = new Blob([await r.text()], { type: "text/javascript" });
  const u = URL.createObjectURL(blob);
  before();
  try { importScripts(u); } finally { URL.revokeObjectURL(u); }
}

async function run({ root, manifest, run, debug }) {
  let stdout = "", stderr = "";
  const consoleLog = console.log.bind(console);
  const log = debug ? (s) => consoleLog(s) : null;
  const lfs = makeLazyFs(manifest, root, { log });
  // Outside of node, the runtime writes stdout and stderr to the console
  console.log = (s) => { stdout += s; };
  console.error = (s) => { stderr += s; };
  // no environment variable in a browser: Rocq wants a home directory
  globalThis.jsoo_env = { HOME: "/static", ...globalThis.jsoo_env };

  const [cmd, ...args] = run.args;
  const program = manifest.rocq[cmd];
  if (!program) throw new Error("no rocq " + cmd + " in the root");
  globalThis.jsoo_argv = ["rocq-" + cmd, ...args];
  // the functions the program gives to its host (rocq-web.host)
  let host = null;
  globalThis.rocqWebInit = (h) => { host = h; };
  let done = false;
  const finish = (exit) => {
    if (done) return;
    done = true;
    const written = [];
    for (const a of host ? args.filter((a) => a.endsWith(".v")) : [])
      for (const p of [a + "o", a + "s", a + "k"]) {
        const data = host.readFile(p);
        if (data) written.push([p, data]);
      }
    self.postMessage({ exit, stdout, stderr, written },
      written.map(([, d]) => d.buffer));
  };
  globalThis.jsoo_exit = finish;
  // e.g. a stack overflow (RangeError) in the program
  const crash = (e) => { stderr += `\n${e.message ?? e.reason ?? e}\n`; finish(255); };
  self.addEventListener("error", crash);
  self.addEventListener("unhandledrejection", crash);
  await lfs.prefetch(manifest.prefetch);
  const url = new URL(program, root).href;
  globalThis.document = { currentScript: { src: url } };
  await importUrl(url, () => lfs.install(new Map(run.files ?? [])));
}

self.onmessage = (e) => {
  const init = e.data && e.data.init;
  if (!init) return;
  run(init).catch((err) =>
    self.postMessage({ exit: 255, stdout: "", stderr: String(err), written: [] }));
};
