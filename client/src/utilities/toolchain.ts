import { exec } from "node:child_process";
import { workspace } from "vscode";
import { Disposable } from "vscode-languageclient";
import { ServerOptions } from "vscode-languageclient/node";
import which from "which";
import Client from "../client";
import { getConfigurationOption } from "../configuration";

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

export default class VsRocqToolchainManager implements Disposable {
    private _vsrocqtopPath: string = "";
    private _rocqVersion: string = "";
    private _versionFullOutput: string = "";
    private _rocqPath: string = "";

    public dispose(): void {}

    public intialize(): Promise<void> {
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

    public getServerConfiguration(): ServerOptions {
        const args = getConfigurationOption("args") as string[];
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
