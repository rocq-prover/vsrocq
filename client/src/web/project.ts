// The files of the workspace, for the web build of the extension.
//
// - Mirror: Rocq runs in Web Workers, which can't read the workspace (only
//   the extension host can, asynchronously, with workspace.fs). The project
//   files, .v and .vo of the workspace are copied in the file systems of the
//   workers, at the path of their URI (the path the server uses for a
//   document), and kept up to date.
// - Compile: compile the files of the project (_RocqProject or
//   _CoqProject at the root of a workspace folder) with rocq dep and rocq c,
//   running in Web Workers, and write the .vo files in the workspace.
import {
    CancellationToken,
    commands,
    ExtensionContext,
    FileType,
    ProgressLocation,
    Uri,
    window,
    workspace,
} from "vscode";
import Client from "../client";

const PATTERN = "**/{_RocqProject,_CoqProject,*.v,*.vo}";
const EXCLUDE = "**/{node_modules,.git,_build}/**";
const MAX_FILES = 5000;

type Files = Map<string, Uint8Array>; // path -> content

interface Worker {
    postMessage(message: any, transfer?: any): void;
    terminate(): void;
    onmessage: ((e: { data: any }) => void) | null;
    onerror: ((e: any) => void) | null;
}
export type MakeWorker = () => Worker;

// Where the mirror sends the files (the unwrapped postMessage of a worker)
type Post = (message: any) => void;

const channel = window.createOutputChannel("Rocq Compile");
// the output channel, also kept as text (the result of the command)
let outputText = "";
const output = {
    clear: () => { channel.clear(); outputText = ""; },
    append: (s: string) => { channel.append(s); outputText += s; },
    appendLine: (s: string) => { channel.appendLine(s); outputText += s + "\n"; },
    show: (preserveFocus: boolean) => channel.show(preserveFocus),
};

export class WorkspaceMirror {
    public files: Files = new Map();
    private servers = new Set<Post>();

    // Read the files of the workspace
    public async load(): Promise<void> {
        const uris = await workspace.findFiles(PATTERN, EXCLUDE, MAX_FILES);
        if (uris.length === MAX_FILES) {
            Client.writeToVsrocqChannel(
                `[Workspace] More than ${MAX_FILES} files: only ${MAX_FILES} are visible to Rocq`,
            );
        }
        await Promise.all(uris.map((u) => this.read(u)));
        Client.writeToVsrocqChannel(`[Workspace] ${this.files.size} files visible to Rocq`);
    }

    private async read(uri: Uri): Promise<[string, Uint8Array] | undefined> {
        try {
            const data = await workspace.fs.readFile(uri);
            this.files.set(uri.path, data);
            return [uri.path, data];
        } catch (e) {
            Client.writeToVsrocqChannel(`[Workspace] cannot read ${uri.toString()}: ${e}`);
            return undefined;
        }
    }

    // Add or replace a file (e.g. a .vo written by compileProject), also in
    // the servers
    public update(path: string, data: Uint8Array) {
        this.files.set(path, data);
        for (const post of this.servers) post({ fs: { write: [[path, data]] } });
    }

    // Send the files to a server worker, and keep it up to date
    public attach(post: Post) {
        this.servers.add(post);
        post({ fs: { write: [...this.files] } });
    }

    public watch(context: ExtensionContext) {
        const w = workspace.createFileSystemWatcher(PATTERN);
        const update = async (uri: Uri) => {
            const f = await this.read(uri);
            if (f) for (const post of this.servers) post({ fs: { write: [f] } });
        };
        w.onDidCreate(update);
        w.onDidChange(update);
        w.onDidDelete((uri) => {
            this.files.delete(uri.path);
            for (const post of this.servers) post({ fs: { remove: [uri.path] } });
        });
        context.subscriptions.push(w);
    }
}

interface RunResult {
    exit: number;
    stdout: string;
    stderr: string;
    written: [string, Uint8Array][];
}

// Run a rocq command (rocq-web) in a fresh worker
function runRocq(makeWorker: MakeWorker, args: string[], files: Files): Promise<RunResult> {
    return new Promise((resolve) => {
        const worker = makeWorker();
        const done = (r: RunResult) => {
            worker.terminate();
            resolve(r);
        };
        worker.onmessage = (e) => {
            const m = e.data;
            if (m && typeof m.exit === "number") done(m);
            else if (m && m.error) done({ exit: 255, stdout: "", stderr: m.error, written: [] });
        };
        worker.onerror = (e) =>
            done({ exit: 255, stdout: "", stderr: String(e?.message ?? e), written: [] });
        worker.postMessage({ init: { run: { args, files: [...files] } } });
    });
}

// dir/p, without "." components nor double slashes
function joinPath(dir: string, p: string): string {
    return ("/" + dir + "/" + p).split("/").filter((c) => c !== "" && c !== ".").reduce(
        (acc, c) => (c === ".." ? acc.replace(/\/[^/]*$/, "") : acc + "/" + c), "") || "/";
}

// The -coqlib option in the arguments of rocq c (rocq dep needs it too)
function coqlibArgs(args: string[]): string[] {
    const i = args.indexOf("-coqlib");
    return i >= 0 ? args.slice(i, i + 2) : [];
}

// The arguments of a project file: the options for rocq, and the .v files
function parseProject(text: string, dir: string): { args: string[]; vfiles: string[] } {
    const toks =
        text
            .replace(/#.*$/gm, "")
            .match(/"[^"]*"|\S+/g)
            ?.map((t) => t.replace(/^"(.*)"$/, "$1")) ?? [];
    const abs = (p: string) => (p.startsWith("/") ? p : joinPath(dir, p));
    const args: string[] = [];
    const vfiles: string[] = [];
    for (let i = 0; i < toks.length; i++) {
        const t = toks[i];
        if (t === "-Q" || t === "-R") args.push(t, abs(toks[++i]), toks[++i]);
        else if (t === "-I") args.push(t, abs(toks[++i]));
        else if (t === "-arg") args.push(...(toks[++i].match(/"[^"]*"|\S+/g) ?? []));
        else if (t.endsWith(".v")) vfiles.push(abs(t));
    }
    return { args, vfiles };
}

// rocq dep output: "a.vo a.glob a.v.beautified a.required_vo: a.v b.vo c.vo"
function parseDeps(out: string): Map<string, string[]> {
    const deps = new Map<string, string[]>();
    for (const line of out.replace(/\\\n/g, " ").split("\n")) {
        const i = line.indexOf(":");
        if (i < 0) continue;
        const targets = line.slice(0, i).trim().split(/\s+/);
        const vo = targets.find((t) => t.endsWith(".vo"));
        if (!vo) continue;
        const ds = line.slice(i + 1).trim().split(/\s+/).filter((d) => d.endsWith(".vo"));
        deps.set(vo.slice(0, -1), ds.map((d) => d.slice(0, -1))); // .v files
    }
    return deps;
}

export async function compileProject(
    mirror: WorkspaceMirror,
    makeWorker: MakeWorker,
    rocqArgs: string[],
    token: CancellationToken,
    progress: (message: string) => void,
): Promise<void> {
    const folder = workspace.workspaceFolders?.[0];
    if (!folder) throw new Error("No workspace folder");
    let project: Uri | undefined;
    for (const name of ["_RocqProject", "_CoqProject"]) {
        const u = Uri.joinPath(folder.uri, name);
        try {
            if ((await workspace.fs.stat(u)).type === FileType.File) { project = u; break; }
        } catch {}
    }
    if (!project) throw new Error("No _RocqProject or _CoqProject at the root of the workspace");
    const dir = folder.uri.path;
    const text = new TextDecoder().decode(await workspace.fs.readFile(project));
    const { args, vfiles } = parseProject(text, dir);
    if (vfiles.length === 0) throw new Error("No .v file in " + project.path);
    output.clear();
    output.appendLine(`rocq ${args.join(" ")} (${vfiles.length} files)`);
    const rel = (v: string) => (v.startsWith(dir) ? v.slice(dir.length).replace(/^\//, "") : v);

    progress("dependencies");
    const dep = await runRocq(makeWorker, ["dep", ...coqlibArgs(rocqArgs), ...args, ...vfiles],
        mirror.files);
    if (dep.exit !== 0) {
        output.append(dep.stdout + dep.stderr);
        output.show(true);
        throw new Error("rocq dep failed");
    }
    const deps = parseDeps(dep.stdout);

    // Which files must be compiled: no .vo, or older than the .v or a dep
    const mtime = async (p: string) => {
        try { return (await workspace.fs.stat(folder.uri.with({ path: p }))).mtime; }
        catch { return undefined; }
    };
    const order: string[] = [];
    const visit = (v: string, seen: Set<string>) => {
        if (seen.has(v)) return;
        seen.add(v);
        for (const d of deps.get(v) ?? []) if (vfiles.includes(d)) visit(d, seen);
        order.push(v);
    };
    const seen = new Set<string>();
    for (const v of vfiles) visit(v, seen);
    const stale = new Set<string>();
    for (const v of order) {
        const vo = await mtime(v + "o");
        const src = await mtime(v);
        const depStale = (deps.get(v) ?? []).some((d) => stale.has(d));
        let depNewer = false;
        for (const d of deps.get(v) ?? []) {
            const t = await mtime(d + "o");
            if (vo !== undefined && t !== undefined && t > vo) depNewer = true;
        }
        if (vo === undefined || (src !== undefined && src > vo) || depStale || depNewer) stale.add(v);
    }
    if (stale.size === 0) {
        window.showInformationMessage("Rocq: the project is up to date");
        return;
    }

    // Compile, in dependency order, PARALLEL files at a time
    const PARALLEL = 2;
    const todo = order.filter((v) => stale.has(v));
    const finished = new Set<string>();
    const running = new Set<string>();
    let failed: string | undefined;
    let count = 0;
    const ready = (v: string) =>
        (deps.get(v) ?? []).every((d) => !stale.has(d) || finished.has(d));
    await new Promise<void>((resolve) => {
        const next = () => {
            if (failed || token.isCancellationRequested) {
                if (running.size === 0) resolve();
                return;
            }
            if (todo.length === 0 && running.size === 0) return resolve();
            while (running.size < PARALLEL) {
                const i = todo.findIndex(ready);
                if (i < 0) break;
                const v = todo.splice(i, 1)[0];
                running.add(v);
                progress(`${++count}/${stale.size} ${rel(v)}`);
                const t0 = Date.now();
                runRocq(makeWorker, ["c", ...rocqArgs, "-noglob", ...args, v], mirror.files).then(
                    async (r) => {
                        running.delete(v);
                        if (r.stdout || r.stderr) output.append(r.stdout + r.stderr);
                        if (r.exit !== 0) {
                            failed = failed ?? rel(v);
                            output.appendLine(`${rel(v)}: failed (exit ${r.exit})`);
                        } else {
                            output.appendLine(`${rel(v)}: ${Date.now() - t0}ms`);
                            for (const [p, data] of r.written) {
                                if (!p.endsWith(".vo")) continue;
                                mirror.update(p, data);
                                await workspace.fs.writeFile(folder.uri.with({ path: p }), data);
                            }
                            finished.add(v);
                        }
                        next();
                    },
                );
            }
        };
        next();
    });
    if (failed) {
        output.show(true);
        throw new Error(`compilation of ${failed} failed, see the output "Rocq Compile"`);
    }
    if (token.isCancellationRequested) throw new Error("cancelled");
    window.showInformationMessage(`Rocq: compiled ${finished.size} files`);
    // Check the open documents again, with the new .vo files
    const active = window.activeTextEditor;
    for (const e of window.visibleTextEditors.filter((e) => e.document.languageId === "rocq")) {
        await window.showTextDocument(e.document, e.viewColumn);
        await commands.executeCommand("extension.rocq.reset");
    }
    if (active) await window.showTextDocument(active.document, active.viewColumn);
}

export function registerCompileCommand(
    context: ExtensionContext,
    mirror: WorkspaceMirror,
    makeWorker: MakeWorker,
    rocqArgs: () => string[],
) {
    context.subscriptions.push(
        // Resolves to {ok, error?, log}
        commands.registerCommand("extension.rocq.compileProject", () =>
            window.withProgress(
                { location: ProgressLocation.Notification, title: "Rocq: compiling", cancellable: true },
                (p, token) =>
                    compileProject(mirror, makeWorker, rocqArgs(), token, (message) =>
                        p.report({ message }),
                    ).then(
                        () => ({ ok: true, log: outputText }),
                        (e) => {
                            const error = String(e?.message ?? e);
                            window.showErrorMessage("Rocq: " + error);
                            return { ok: false, error, log: outputText };
                        },
                    ),
            ),
        ),
    );
}
