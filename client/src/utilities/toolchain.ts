import { exec, fork } from "node:child_process";
import { ExtensionContext, workspace } from "vscode";
import { Disposable } from "vscode-languageclient";
import * as path from "node:path";
import { ServerOptions, TransportKind } from "vscode-languageclient/node";
import which from "which";
import Client from "../client";
import { getConfigurationOption } from "../configuration";
import { registerCompileCommand, WorkspaceMirror } from "../web/project";

export enum ToolChainErrorCode {
    notFound = 1,
    launchError = 2,
}

export interface ToolchainError {
    status: ToolChainErrorCode;
    message: string;
}

// The Rocq version in the output of [vsrocqtop -v], which also mentions the
// OCaml version: "The Rocq Prover, version 9.2\ncompiled with OCaml 4.14.2".
export const parseRocqVersion = (output: string) => {
    const versionRegexp =
        /\bversion (\d+\.\d+(?:\.\d+)?(?:\+rc\d+|\+alpha|\+beta\d*|\.dev)?)(?!\S)/;
    const match = output.match(versionRegexp);
    return match ? match[1] : undefined;
};

// The documents handled by the language server
export const documentSelector = [{ scheme: "file", language: "rocq" }];

export const platform = () => `${process.arch} ${process.platform}`;

// With vsrocq.useWasm, the root (vsrocq.web.root) providing the server and
// the libraries: the server, compiled to WebAssembly, is run by the node of
// VS Code (web/node-server.js), as in VS Code for the web
interface WasmRoot {
    url: string;
    manifest: { args: string[]; packages: { [name: string]: string } };
}

export default class VsRocqToolchainManager implements Disposable {
    private _vsrocqtopPath: string = "";
    private _rocqVersion: string = "";
    private _versionFullOutput: string = "";
    private _rocqPath: string = "";
    private _context: ExtensionContext | undefined;
    private _wasm: WasmRoot | undefined;

    public dispose(): void {}

    // Commands depending on the platform (see web/toolchain.ts)
    public registerCommands(context: ExtensionContext): void {
        this._context = context;
        // With vsrocq.useWasm, Rocq: Compile the project runs rocq dep and
        // rocq c of the root (node-server.js --run), as in the browser. They
        // read and write the files of the computer: no mirror is needed
        registerCompileCommand(context, new WorkspaceMirror(), () => this.makeRunWorker(),
            () => this._wasm?.manifest.args ?? []);
    }

    // A "worker" running a rocq command of the root (see runRocq in
    // web/project.ts): a node process, whose result is sent as a message
    private makeRunWorker() {
        const wasm = this._wasm;
        const context = this._context;
        if (!wasm || !context) {
            throw new Error(
                "compiling the project needs vsrocq.useWasm (and vsrocq.web.root): with vsrocqtop, use make or dune",
            );
        }
        const module = context.asAbsolutePath(path.join("web", "node-server.js"));
        const cache = path.join(context.globalStorageUri.fsPath, "wasm");
        let child: ReturnType<typeof fork> | undefined;
        const worker = {
            onmessage: null as ((e: { data: any }) => void) | null,
            onerror: null as ((e: any) => void) | null,
            postMessage(m: any) {
                const args: string[] = m.init.run.args;
                let stdout = "", stderr = "";
                child = fork(module, [wasm.url, cache, "--run", ...args], {
                    silent: true,
                    cwd: workspace.workspaceFolders?.[0]?.uri.fsPath,
                    env: { ...process.env, ELECTRON_RUN_AS_NODE: "1" },
                });
                child.stdout?.on("data", (d) => { stdout += d; });
                child.stderr?.on("data", (d) => { stderr += d; });
                child.on("error", (e) => worker.onerror?.(e));
                child.on("close", (code) =>
                    worker.onmessage?.({ data: { exit: code ?? 255, stdout, stderr, written: [] } }));
            },
            terminate() { child?.kill(); },
        };
        return worker;
    }

    public intialize(): Promise<void> {
        if (getConfigurationOption("useWasm")) return this.initializeWasm();
        Client.writeToVsrocqChannel("[Toolchain] Searching for vsrocqtop");
        return new Promise(
            (resolve, reject: (reason: ToolchainError) => void) => {
                this.vsrocqtopCmd().then((vsrocqtopPath) => {
                    if (vsrocqtopPath) {
                        Client.writeToVsrocqChannel(
                            "[Toolchain] Found path: " + vsrocqtopPath,
                        );
                        this._vsrocqtopPath = vsrocqtopPath;
                        this.vsrocqtopWhere().then(
                            () => {
                                resolve();
                            },
                            (err: ToolchainError) => {
                                reject(err);
                            },
                        );
                    } else {
                        Client.writeToVsrocqChannel(
                            "[Toolchain] Did not find vsrocqtop path",
                        );
                        reject({
                            status: ToolChainErrorCode.notFound,
                            message:
                                "VsRocq couldn't launch because no language server was found. You can install the language server (requires Rocq 8.18 or higher) or use VsRocq Legacy.",
                        });
                    }
                });
            },
        );
    }

    private async initializeWasm(): Promise<void> {
        let url = getConfigurationOption("web", "root") as string;
        if (!url) {
            throw {
                status: ToolChainErrorCode.notFound,
                message:
                    "vsrocq.useWasm is set: set vsrocq.web.root to the URL of a published opam root providing the language server compiled to WebAssembly.",
            } as ToolchainError;
        }
        if (!url.endsWith("/")) url += "/";
        Client.writeToVsrocqChannel("[Toolchain] Using the WebAssembly server of " + url);
        let manifest: WasmRoot["manifest"];
        try {
            const r = await fetch(url + "manifest.json");
            if (!r.ok) throw new Error("HTTP " + r.status);
            manifest = (await r.json()) as WasmRoot["manifest"];
        } catch (e) {
            throw {
                status: ToolChainErrorCode.notFound,
                message: `Cannot read ${url}manifest.json: ${e}`,
            } as ToolchainError;
        }
        this._wasm = { url, manifest };
        const p = manifest.packages;
        this._vsrocqtopPath = url + "  (WebAssembly)";
        this._rocqPath = url;
        this._rocqVersion = p["rocq-runtime"] ?? "unknown";
        this._versionFullOutput = `The Rocq Prover, version ${p["rocq-runtime"]} (WebAssembly, OCaml ${p["ocaml"]})`;
        Client.writeToVsrocqChannel(
            "[Toolchain] Rocq " + this._rocqVersion + ", language server " +
                p["vsrocq-language-server"],
        );
    }

    public getServerConfiguration(): ServerOptions {
        const args = getConfigurationOption("args") as string[];
        if (this._wasm && this._context) {
            const module = this._context.asAbsolutePath(path.join("web", "node-server.js"));
            const cache = path.join(this._context.globalStorageUri.fsPath, "wasm");
            const server = {
                module,
                args: [this._wasm.url, cache, ...args],
                transport: TransportKind.stdio,
                options: { cwd: workspace.rootPath },
            };
            return { run: server, debug: server };
        }
        const serverOptions: ServerOptions = {
            command: this._vsrocqtopPath,
            args,
            options: {
                cwd: workspace.rootPath,
                shell: true,
            },
        };
        return serverOptions;
    }

    public getVsRocqTopPath(): string {
        return this._vsrocqtopPath;
    }

    public getRocqPath(): string {
        return this._rocqPath;
    }

    public getRocqVersion(): string {
        return this._rocqVersion;
    }

    public getversionFullOutput(): string {
        return this._versionFullOutput;
    }

    private async vsrocqtopCmd(): Promise<string | undefined> {
        const vsrocqtopPath = getConfigurationOption("path");
        if (vsrocqtopPath) {
            Client.writeToVsrocqChannel(
                "[Toolchain] Path set in user settings",
            );
            return vsrocqtopPath;
        }
        const vsrocqtopWithOpam = await this.searchForVsrocqtopWithOpam();
        if (vsrocqtopWithOpam) {
            return vsrocqtopWithOpam;
        }
        return await this.searchForVsrocqtop();
    }

    private async searchForVsrocqtop(): Promise<string | undefined> {
        const vsrocqtopPath = await which("vsrocqtop", { nothrow: true });
        return vsrocqtopPath || undefined;
    }

    private async searchForVsrocqtopWithOpam(): Promise<string | undefined> {
        return new Promise<string | undefined>((resolve) => {
            exec(
                "opam exec -- vsrocqtop -v",
                { cwd: workspace.rootPath },
                (error) => resolve(error ? undefined : "opam exec -- vsrocqtop"),
            );
        });
    }

    // Launch the vsrocqtop -where command with the found exec and provided args
    private vsrocqtopWhere(): Promise<void> {
        const args = getConfigurationOption("args") as string[];
        const options = ["-without-project-file", "-where"].concat(args);
        const cmd = [this._vsrocqtopPath].concat(options).join(" ");
        // fallback for < 2.4.0
        const pre240options = ["-where"].concat(args);
        const pre240cmd = [this._vsrocqtopPath].concat(pre240options).join(" ");

        return new Promise(
            (resolve, reject: (reason: ToolchainError) => void) => {
                const onSuccess = (stdout: string) => {
                    this._rocqPath = stdout;
                    this.rocqVersion().then(
                        () => resolve(),
                        (err) =>
                            reject({
                                status: ToolChainErrorCode.launchError,
                                message: `${this._vsrocqtopPath} crashed with the following message: ${err}.
                        This could be due to a bad Rocq installation or an incompatible Rocq version`,
                            }),
                    );
                };

                const onError = (stderr: string) => {
                    reject({
                        status: ToolChainErrorCode.launchError,
                        message: `${this._vsrocqtopPath} crashed with the following message: ${stderr}
                    This could be due to a bad Rocq installation or an incompatible Rocq version.`,
                    });
                };

                exec(
                    cmd,
                    { cwd: workspace.rootPath },
                    (error, stdout, stderr1) => {
                        if (error) {
                            exec(
                                pre240cmd,
                                { cwd: workspace.rootPath },
                                (error, stdout, stderr2) => {
                                    if (error) {
                                        onError(
                                            `${cmd}\n${stderr1}\n\n${pre240cmd}\n${stderr2}\n`,
                                        );
                                    } else {
                                        onSuccess(stdout);
                                    }
                                },
                            );
                        } else {
                            onSuccess(stdout);
                        }
                    },
                );
            },
        );
    }

    private rocqVersion(): Promise<void> {
        const args = getConfigurationOption("args") as string[];
        const options = ["-v"].concat(args);
        const cmd = [this._vsrocqtopPath].concat(options).join(" ");

        return new Promise((resolve, reject: (reason: string) => void) => {
            exec(cmd, { cwd: workspace.rootPath }, (error, stdout, stderr) => {
                if (error) {
                    reject(stderr);
                } else {
                    this._versionFullOutput = stdout;
                    const version = parseRocqVersion(stdout);
                    if (version) {
                        this._rocqVersion = version;
                    } else {
                        Client.writeToVsrocqChannel(
                            "[Toolchain] Could not find the Rocq version in the output of " +
                                cmd +
                                ":\n" +
                                stdout,
                        );
                        this._rocqVersion = "unknown";
                    }
                    resolve();
                }
            });
        });
    }
}
