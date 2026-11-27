// Run the rocq command of rocq-web (rocq c, rocq dep) once, in a browser
// Web Worker started by the extension's bootstrap.js.
//
// The host sends {init: {root, manifest, run: {args, files}}}, where files
// ([[path, Uint8Array], ...]) are added to the file system (e.g. the files
// of the workspace) and args is the command line after "rocq" (the first
// one is the subcommand, c or dep: a program of manifest.rocq). The worker
// posts back {exit, stdout, stderr, written}, where written are the files
// written by the program ([[path, Uint8Array], ...]). The host should
// terminate the worker afterwards.
"use strict";

async function importUrl(url) {
  const r = await fetch(url);
  if (!r.ok) throw new Error(`${url}: HTTP ${r.status}`);
  const blob = new Blob([await r.text()], { type: "text/javascript" });
  const u = URL.createObjectURL(blob);
  try { importScripts(u); } finally { URL.revokeObjectURL(u); }
}

async function run({ root, manifest, run, debug }) {
  let stdout = "", stderr = "";
  const log = debug ? (s) => console.log(s) : null;
  const lfs = makeLazyFs(manifest, root, {
    log,
    stdout: (s) => { stdout += s; },
    stderr: (s) => { stderr += s; },
  });
  for (const [p, data] of run.files ?? []) lfs.writeFile(p, data);
  globalThis.jsoo_fs = lfs.fs;
  // no environment variable in a browser: Rocq wants a home directory
  globalThis.jsoo_env = { HOME: "/static", ...globalThis.jsoo_env };

  const [cmd, ...args] = run.args;
  const program = manifest.rocq[cmd];
  if (!program) throw new Error("no rocq " + cmd + " in the root");
  globalThis.jsoo_argv = ["rocq-" + cmd, ...args];
  let done = false;
  const finish = (exit) => {
    if (done) return;
    done = true;
    const written = lfs.writtenFiles();
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
  await importUrl(url);
}

self.onmessage = (e) => {
  const init = e.data && e.data.init;
  if (!init) return;
  run(init).catch((err) =>
    self.postMessage({ exit: 255, stdout: "", stderr: String(err), written: [] }));
};
