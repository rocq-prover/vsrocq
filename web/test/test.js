const log = (s) => fetch("/log", { method: "POST", body: String(s) });
const result = (s) => fetch("/result", { method: "POST", body: String(s) });
const params = new URLSearchParams(location.search);
const ROOT = params.get("root") || "http://127.0.0.1:8001/";
const text = params.get("text") || "Definition x := 1 + 1.\nLemma l : x = 2. Proof. reflexivity. Qed.\nFrom Corelib Require Import ssreflect.\nLemma u (b : bool) : b = b. Proof. by case: b. Qed.\nLemma bad : 1 = 2. Proof. reflexivity. Qed.\n";
const CONF = {proof:{delegation:"None",workers:1,mode:1,block:false,pointInterpretationMode:0},
  goals:{diff:{mode:"off"},messages:{full:true}},completion:{enable:false,algorithm:1,unificationLimit:100},
  diagnostics:{enable:true,full:false},memory:{limit:4}};
const t0 = performance.now();
const ms = () => Math.round(performance.now() - t0);
log(`crossOriginIsolated=${self.crossOriginIsolated}`);
const w = new Worker("bootstrap.js");
const sab = new SharedArrayBuffer(4);
let id = 0;
const send = (o) => w.postMessage({ jsonrpc: "2.0", ...o });
w.onerror = (e) => result(`FAIL worker error ${e.message}`);
w.onmessage = (e) => {
  const j = typeof e.data === "string" ? JSON.parse(e.data) : e.data;
  if (j.id === 1) log(`initialized at ${ms()}ms`);
  if (j.method === "textDocument/publishDiagnostics") {
    const ds = j.params.diagnostics.map((d) => `${d.range.start.line}:${d.message}`);
    log(`${ms()}ms diagnostics ${JSON.stringify(ds)}`);
    if (ds.length) result(`OK ${ms()}ms ${JSON.stringify(ds)}`);
  } else if (j.method === "window/logMessage" && j.params.type <= 2) {
    log("log: " + j.params.message);
    if (j.params.message.startsWith("Cannot start")) result("FAIL " + j.params.message);
  }
};
w.postMessage({ init: { root: ROOT, interrupt: sab, debug: params.has("debug") } });
send({ id: ++id, method: "initialize", params: { processId: null, rootUri: null, capabilities: {}, initializationOptions: CONF } });
send({ method: "initialized", params: {} });
send({ method: "textDocument/didOpen", params: { textDocument: { uri: "file:///home/test/t.v", languageId: "rocq", version: 1, text } } });
