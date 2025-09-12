import * as vscode from 'vscode';

import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
} from 'vscode-languageclient/node';

import {decorationsManual, decorationsContinuous, decorationsErrorAnimation} from './Decorations';

export default class Client extends LanguageClient {

	private static _channel: any = vscode.window.createOutputChannel('VsRocq');
    private static _rocqLog: any = vscode.window.createOutputChannel('Rocq Log');
    private _decorationsPrepared: Map<String, vscode.Range[]> = new Map<String, vscode.Range[]>();
    private _decorationsProcessed: Map<String, vscode.Range[]> = new Map<String, vscode.Range[]>();
    private _decorationsProcessing: Map<String, vscode.Range[]> = new Map<String, vscode.Range[]>();

	constructor(
        serverOptions: ServerOptions,
        clientOptions: LanguageClientOptions,
	) {
        super(
		    'vsrocq-language-server',
		    'Rocq Language Server',
		    serverOptions,
		    clientOptions
        );
		Client._channel.appendLine("VsRocq initialised");
	}


    public static writeToVsrocqChannel(message: string) {
        Client._channel.appendLine(message);
    }

    public static writeRocqMessageLog(message: string) {
        Client._rocqLog.appendLine(message);
    }

    public static showLog() {
        Client._channel.show(true);
    };

    public saveHighlights(uri: String, preparedRange: vscode.Range[], processingRange: vscode.Range[], processedRange: vscode.Range[]) {
        this._decorationsPrepared.set(uri, preparedRange);
        this._decorationsProcessing.set(uri, processingRange);
        this._decorationsProcessed.set(uri, processedRange);
    }

    public updateHightlights() {
        for(let entry of this._decorationsPrepared.entries()) {
            this.updateDocumentEditors(entry[0], entry[1], "prepared");
        }
        for(let entry of this._decorationsProcessing.entries()) {
            this.updateDocumentEditors(entry[0], entry[1], "processing");
        }
        for(let entry of this._decorationsProcessed.entries()) {
            this.updateDocumentEditors(entry[0], entry[1]);
        }
    };

    public resetHighlights() {
        for(let entry of this._decorationsProcessed.entries()) {
            this.resetDocumentEditors(entry[0]);
        }
    }

    public getHighlights(uri: String) {
        return this._decorationsProcessed.get(uri);
    }

    public createErrorAnimation(uri: String, ranges: vscode.Range[]) {
        const timing = 50;
        const editors = this.getDocumentEditors(uri);
        //Create a flash animation by gradually increasing opacities
        //Then decreasing them and then removing them completely
        editors.map(editor => {
            decorationsErrorAnimation.map((decoration, i) => {
                setTimeout(() => {
                    editor.setDecorations(decoration, ranges);
                    setTimeout(() => {
                        editor.setDecorations(decoration, []);
                    }, timing);
                }, i * timing);
            });
            // setTimeout(() => {
            //     decorationsErrorAnimation.map(decoration => editor.setDecorations(decoration, []));
            // }, decorationsErrorAnimation.length * timing);
        });
    }

    private getDocumentEditors(uri: String) {
        return vscode.window.visibleTextEditors.filter(editor => {
            return editor.document.uri.toString() === uri;
        });
    }

    private resetDocumentEditors(uri: String) {
        const editors = this.getDocumentEditors(uri);
        editors.map(editor => {
            editor.setDecorations(decorationsManual.prepared, []);
            editor.setDecorations(decorationsContinuous.prepared, []);
            editor.setDecorations(decorationsManual.processing, []);
            editor.setDecorations(decorationsContinuous.processing, []);
            editor.setDecorations(decorationsManual.processed, []);
            editor.setDecorations(decorationsContinuous.processed, []);
        });
    }

    private updateDocumentEditors(uri: String, ranges: vscode.Range[], type: String = "processed") {
        const config = vscode.workspace.getConfiguration('vsrocq.proof');
        const editors = this.getDocumentEditors(uri);
        editors.map(editor => {
            if(config.mode === 0) {
                if(type === "prepared") {
                    editor.setDecorations(decorationsManual.prepared, ranges);
                }
                if(type === "processing") {
                    editor.setDecorations(decorationsManual.processing, ranges);
                }
                if (type === "processed") {
                    editor.setDecorations(decorationsManual.processed, ranges);
                }
            } else {
                if(type === "prepared") {
                    editor.setDecorations(decorationsContinuous.prepared, ranges);
                }
                if(type === "processing") {
                    editor.setDecorations(decorationsContinuous.processing, ranges);
                }
                if (type === "processed") {
                    editor.setDecorations(decorationsContinuous.processed, ranges);
                }
            }
        });
    }

}
