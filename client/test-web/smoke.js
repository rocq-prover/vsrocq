// Smoke test of the web extension, run by @vscode/test-web in the web
// extension host (see README.md): open a document, wait for the
// diagnostics of the language server.
const vscode = require("vscode");

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
// console.log of the extension host is not shown: also post to the test
// server (web/test/serve.py) if it runs
const log = (s) => {
  console.log(s);
  fetch("http://127.0.0.1:8000/log", { method: "POST", body: s }).catch(() => {});
};

exports.run = async function () {
  const t0 = Date.now();
  const ws = vscode.workspace.workspaceFolders[0].uri;
  const uri = vscode.Uri.joinPath(ws, "smoke.v");
  const doc = await vscode.workspace.openTextDocument(uri);
  await vscode.window.showTextDocument(doc);
  for (let i = 0; i < 600; i++) {
    const ds = vscode.languages.getDiagnostics(uri).map((d) => `${d.range.start.line}: ${d.message}`);
    if (ds.length > 0) {
      log(`vsrocq web smoke test: diagnostics after ${Date.now() - t0}ms: ${JSON.stringify(ds)}`);
      if (ds.some((d) => d.startsWith("4: Unable to unify"))) return;
      throw new Error("unexpected diagnostics " + JSON.stringify(ds));
    }
    await sleep(200);
  }
  const ext = vscode.extensions.getExtension("rocq-prover.vsrocq");
  throw new Error(`no diagnostics (extension ${ext ? (ext.isActive ? "active" : "inactive") : "missing"}, ` +
    `vsrocq.web.root=${vscode.workspace.getConfiguration("vsrocq.web").get("root")})`);
};
