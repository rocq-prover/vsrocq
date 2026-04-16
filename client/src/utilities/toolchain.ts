import { workspace } from 'vscode';
import { Disposable } from "vscode-languageclient";
import { exec } from 'child_process';
import { ServerOptions } from 'vscode-languageclient/node';
import Client from '../client';
import * as which from 'which';

export enum ToolChainErrorCode {
    notFound = 1, 
    launchError = 2
}

export interface ToolchainError {
    status: ToolChainErrorCode; 
    message: string; 
}

export default class VsRocqToolchainManager implements Disposable {

    private _vsrocqtopPath: string = "";
    private _rocqVersion: string = "";
    private _versionFullOutput: string = "";
    private _rocqPath: string = "";

    public dispose(): void {
        
    }

    public intialize() : Promise<void> {
        Client.writeToVsrocqChannel("[Toolchain] Searching for vsrocqtop");
        return new Promise((resolve, reject: ((reason: ToolchainError) => void)) => {
            this.vsrocqtopPath().then(vsrocqtopPath => {
                if(vsrocqtopPath) {
                    Client.writeToVsrocqChannel("[Toolchain] Found path: " + vsrocqtopPath);
                    this._vsrocqtopPath = vsrocqtopPath;
                    this.vsrocqtopWhere().then(
                        () => {
                            resolve();
                        }, 
                        (err: ToolchainError) => {
                            reject(err);
                        }
                    );

                } else {
                    Client.writeToVsrocqChannel("[Toolchain] Did not find vsrocqtop path");
                    reject({
                        status: ToolChainErrorCode.notFound, 
                        message: "VsRocq couldn't launch because no language server was found. You can install the language server (requires Rocq 8.18 or higher) or use VsRocq Legacy."
                    });
                }
            });
        });
        
    };

    public getServerConfiguration() : ServerOptions {

        const config = workspace.getConfiguration('vsrocq');
        const serverOptions : ServerOptions = {
            command: this._vsrocqtopPath, 
            args: config.args,
            options: {
                cwd: workspace.rootPath,
                shell: true,
            },
        };
        return serverOptions;
    };

    public getVsRocqTopPath() : string {
        return this._vsrocqtopPath;
    }

    public getRocqPath() : string {
        return this._rocqPath;
    }

    public getRocqVersion() : string {
        return this._rocqVersion;
    };

    public getversionFullOutput() : string {
        return this._versionFullOutput;
    }

    private async vsrocqtopPath () : Promise<string> {
        const vsrocqtopPath = workspace.getConfiguration('vsrocq').get('path') as string;
        if(vsrocqtopPath) {
            Client.writeToVsrocqChannel("[Toolchain] Path set in user settings");
            return vsrocqtopPath; 
        }
        else {
            return await this.searchForVsrocqtopInPath();
        }
    }

    private async searchForVsrocqtopInPath () : Promise<string> {        
        return await which("vsrocqtop", { nothrow: true }) ?? "";
    }

    // Launch the vsrocqtop -where command with the found exec and provided args
    private vsrocqtopWhere() : Promise<void> {
        
        const config = workspace.getConfiguration('vsrocq').get('args') as string[];
        const options = ["-without-project-file", "-where"].concat(config);
        const cmd = [this._vsrocqtopPath].concat(options).join(' ');
        // fallback for < 2.4.0
        const pre240options = ["-where"].concat(config);
        const pre240cmd = [this._vsrocqtopPath].concat(pre240options).join(' ');

        return new Promise((resolve, reject: ((reason: ToolchainError) => void)) => {

            const onSuccess = (stdout: string) => {
                this._rocqPath = stdout;
                this.rocqVersion().then(
                    () => resolve(),
                    (err) => reject({
                        status: ToolChainErrorCode.launchError,
                        message: `${this._vsrocqtopPath} crashed with the following message: ${err}.
                        This could be due to a bad Rocq installation or an incompatible Rocq version`
                    })
                );
            };

            const onError = (stderr: string) => {
                reject({
                    status: ToolChainErrorCode.launchError,
                    message: `${this._vsrocqtopPath} crashed with the following message: ${stderr}
                    This could be due to a bad Rocq installation or an incompatible Rocq version.`
                });
            };

            exec(cmd, {cwd: workspace.rootPath}, (error, stdout, stderr1) => {
                if(error) {
                    exec(pre240cmd, {cwd: workspace.rootPath}, (error, stdout, stderr2) => {
                        if(error) {
                            onError(`${cmd}\n${stderr1}\n\n${pre240cmd}\n${stderr2}\n`);
                        } else {
                            onSuccess(stdout);
                        }
                    });
                } else {
                    onSuccess(stdout);
                }
            });
        });
    };

    private rocqVersion() : Promise<void> {

        const config = workspace.getConfiguration('vsrocq').get('args') as string[];
        const options = ["-v"].concat(config);
        const cmd = [this._vsrocqtopPath].concat(options).join(' ');

        return new Promise((resolve, reject: (reason: string) => void) => {
            exec(cmd, {cwd: workspace.rootPath}, (error, stdout, stderr) => {
                if(error) {
                    reject(stderr);
                } else {
                    const versionRegexp = /\b\d\.\d+(\.\d|\+rc\d|\.dev|\+alpha|\+beta)\b/g;
                    this._versionFullOutput = stdout;
                    const matchArray = stdout.match(versionRegexp);
                    if(matchArray) {
                        this._rocqVersion = matchArray[0];
                    }
                    resolve();
                }
            });
        });
    };

}