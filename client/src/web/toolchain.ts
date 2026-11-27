// utilities/toolchain for the web build of the extension (see
// vite.config.web.ts, which substitutes this module).
//
// There is no local installation: Rocq and the language server, compiled to
// WebAssembly, come from a published opam root (the setting vsrocq.web.root,
// see vsrocq-make-web-root). The server runs in a Web Worker, started by
// web/bootstrap.js, which loads the server glue from the root.
//
// Interruption: while Rocq computes, the worker does not process messages,
// so an interruption is requested through shared memory, when the client
// sends prover/interrupt or edits a document. This needs cross-origin
// isolation (in vscode.dev, add ?vscode-coi to the URL).
//
// The files of the workspace are mirrored in the file system of the
// server, and the command extension.rocq.compileProject compiles the
// project in workers running rocq (see project.ts).
import { ExtensionContext, extensions, Uri, workspace } from "vscode";
import { Disposable } from "vscode-languageclient";
import Client from "../client";
import { registerCompileCommand, WorkspaceMirror } from "./project";

export enum ToolChainErrorCode {
    notFound = 1,
    launchError = 2,
}

export interface ToolchainError {
    status: ToolChainErrorCode;
    message: string;
}

export const parseRocqVersion = (output: string) => {
    const versionRegexp =
        /\bversion (\d+\.\d+(?:\.\d+)?(?:\+rc\d+|\+alpha|\+beta\d*|\.dev)?)(?!\S)/;
    const match = output.match(versionRegexp);
    return match ? match[1] : undefined;
};

// Documents can come from any file system (e.g. vscode-vfs for GitHub)
export const documentSelector = [{ language: "rocq" }];

export const platform = () => `web (${navigator.userAgent})`;

// The Web Worker running the server (the DOM types are not available here)
interface ServerWorker {
    postMessage(message: any, transfer?: any): void;
    terminate(): void;
    onmessage: ((e: { data: any }) => void) | null;
    onerror: ((e: any) => void) | null;
}

interface Manifest {
    prefix: string;
    server: string;
    worker: string;
    lazyfs: string;
    args: string[];
    packages: { [name: string]: string };
    files: { [path: string]: number };
}

// Messages from the client which interrupt a running computation
const interrupting = new Set(["prover/interrupt", "textDocument/didChange"]);

export default class VsRocqToolchainManager implements Disposable {
    private _root: string = "";
    private _manifest: Manifest | undefined;
    private _mirror = new WorkspaceMirror();

    public dispose(): void {}

    public registerCommands(context: ExtensionContext): void {
        this._mirror.watch(context);
        registerCompileCommand(context, this._mirror, () => this.makeWorker(),
            () => this._manifest?.args ?? []);
    }

    private debug(): boolean {
        return workspace.getConfiguration("vsrocq.web").get<boolean>("debug") ?? false;
    }

    // A worker started by bootstrap.js; the root is added to its init message
    private makeWorker(): ServerWorker {
        const ext = extensions.getExtension("rocq-prover.vsrocq")!;
        const bootstrap = Uri.joinPath(ext.extensionUri, "dist", "web", "bootstrap.js");
        const WorkerCtor: new (url: string) => ServerWorker = (globalThis as any).Worker;
        const worker = new WorkerCtor(bootstrap.toString(true));
        const post = worker.postMessage.bind(worker);
        worker.postMessage = (m: any, transfer?: any) =>
            post(m && m.init ? { init: { root: this._root, debug: this.debug(), ...m.init } } : m,
                transfer);
        return worker;
    }

    public async intialize(): Promise<void> {
        const root = workspace.getConfiguration("vsrocq.web").get<string>("root") ?? "";
        if (root === "") {
            throw {
                status: ToolChainErrorCode.notFound,
                message:
                    "Set vsrocq.web.root to the URL of a published opam root providing the web language server.",
            } as ToolchainError;
        }
        this._root = root.endsWith("/") ? root : root + "/";
        Client.writeToVsrocqChannel("[Toolchain] Using " + this._root);
        try {
            const r = await fetch(this._root + "manifest.json");
            if (!r.ok) throw new Error("HTTP " + r.status);
            this._manifest = (await r.json()) as Manifest;
        } catch (e) {
            throw {
                status: ToolChainErrorCode.notFound,
                message: `Cannot read ${this._root}manifest.json: ${e}`,
            } as ToolchainError;
        }
        Client.writeToVsrocqChannel(
            "[Toolchain] Rocq " + this.getRocqVersion() + ", language server " +
                this._manifest!.packages["vsrocq-language-server"],
        );
        await this._mirror.load();
    }

    public getServerConfiguration(): any {
        const worker = this.makeWorker();
        const isolated =
            typeof SharedArrayBuffer !== "undefined" &&
            (globalThis as any).crossOriginIsolated === true;
        const interrupt = isolated ? new SharedArrayBuffer(4) : undefined;
        if (!interrupt) {
            Client.writeToVsrocqChannel(
                "[Toolchain] Not cross-origin isolated: Rocq can't be interrupted " +
                    "(in vscode.dev, add ?vscode-coi to the URL)",
            );
        }
        const args = workspace.getConfiguration("vsrocq").get<string[]>("args") ?? [];
        worker.postMessage({
            init: { interrupt, args: [...this._manifest!.args, ...args] },
        });
        // The messages of the client go through JSON (as with node): they
        // may contain objects which can't be cloned by postMessage, such as
        // the WorkspaceConfiguration of the initializationOptions. The
        // worker accepts JSON strings.
        const flag = interrupt ? new Int32Array(interrupt) : undefined;
        if (this.debug()) {
            // the console of the server worker may not be visible
            const w = worker as any;
            w.addEventListener("error", (e: any) =>
                console.error("vsrocq: server worker error:", e?.message ?? e));
            w.addEventListener("message", (e: any) => {
                const m = e.data;
                if (m && m.method === "window/logMessage")
                    console.log("vsrocq server: " + m.params.message);
                else if (m && m.method === "textDocument/publishDiagnostics")
                    console.log(`vsrocq <- diagnostics ${JSON.stringify(
                        m.params.diagnostics.map((d: any) => `${d.range.start.line}: ${d.message.slice(0, 40)}`))}`);
                else if (m && m.method !== "$/logTrace")
                    console.log(`vsrocq <- ${m?.method ?? "response " + m?.id}`);
            });
        }
        const debug = this.debug();
        const post = worker.postMessage.bind(worker);
        this._mirror.attach(post);
        worker.postMessage = (m: any) => {
            if (debug) console.log(`vsrocq -> ${m?.method ?? "response " + m?.id}`);
            if (flag && m && interrupting.has(m.method)) Atomics.store(flag, 0, 1);
            return post(JSON.stringify(m));
        };
        return worker;
    }

    public getVsRocqTopPath(): string {
        return this._root + (this._manifest?.server ?? "");
    }

    public getRocqPath(): string {
        return this._root;
    }

    public getRocqVersion(): string {
        return this._manifest?.packages["rocq-runtime"] ?? "";
    }

    public getversionFullOutput(): string {
        const p = this._manifest?.packages ?? {};
        return `The Rocq Prover, version ${p["rocq-runtime"]} (web, OCaml ${p["ocaml"]})`;
    }
}
