// Test of the web extension on a multi-file project (see README.md), in
// continuous mode (project/.vscode/settings.json):
// open C.v, which requires files of the project which are not compiled;
// compile the project (extension.rocq.compileProject, which resets the
// open documents); check that C.v is checked again with the new files.
const vscode = require("vscode");

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
// console.log of the extension host is not shown: also post to the test
// server (web/test/serve.py) if it runs
const log = (s) => {
  console.log(s);
  fetch("http://127.0.0.1:8000/log", { method: "POST", body: s }).catch(() => {});
};
const diags = (uri) =>
  vscode.languages.getDiagnostics(uri).map((d) => `${d.range.start.line}: ${d.message}`);

async function until(what, uri, pred, timeout = 120000) {
  const t0 = Date.now();
  while (Date.now() - t0 < timeout) {
    const ds = diags(uri);
    if (pred(ds)) {
      log(`vsrocq web project test: ${what} after ${Date.now() - t0}ms: ${JSON.stringify(ds)}`);
      return ds;
    }
    await sleep(200);
  }
  throw new Error(`${what}: timeout, diagnostics ${JSON.stringify(diags(uri))}`);
}

exports.run = async function () {
  const ws = vscode.workspace.workspaceFolders[0].uri;
  const uri = vscode.Uri.joinPath(ws, "C.v");
  await vscode.window.showTextDocument(await vscode.workspace.openTextDocument(uri));
  await until("before compiling", uri, (ds) => ds.some((d) => d.includes("Unable to locate library A")));
  const t0 = Date.now();
  const r = await vscode.commands.executeCommand("extension.rocq.compileProject");
  log(`vsrocq web project test: compile in ${Date.now() - t0}ms: ${JSON.stringify(r)}`);
  if (!r.ok) throw new Error("the compilation failed: " + r.error);
  // only the error of the lemma bad (line 3); line 1 is the output of Check
  await until("after compiling", uri, (ds) =>
    ds.some((d) => d.startsWith("3: ")) && !ds.some((d) => d.includes("Unable to locate")));
  await sleep(500); // let the log reach the console before the browser closes
};
