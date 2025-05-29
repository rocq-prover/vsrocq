import {workspace, window, commands, languages, ExtensionContext, env,
  TextEditorSelectionChangeEvent,
  TextEditor,
  ViewColumn,
  TextEditorRevealType,
  Selection,
  Uri,
  StatusBarItem,
  extensions,
  StatusBarAlignment,
  MarkdownString,
  WorkspaceEdit,
  version
} from 'vscode';

import * as os from 'node:os';

import {
  LanguageClientOptions,
  RequestType,
  ServerOptions,
  TextDocumentIdentifier,
} from 'vscode-languageclient/node';

import Client from './client';
import { updateServerOnConfigurationChange } from './configuration';
import { checkVersion, getRocqdocUrl } from './utilities/versioning';
import {initializeDecorations} from './Decorations';
import GoalPanel from './panels/GoalPanel';
import SearchViewProvider from './panels/SearchViewProvider';
import {
    RocqLogMessage,
    DocumentProofsRequest,
    DocumentProofsResponse,
    ErrorAlertNotification,
    MoveCursorNotification, 
    ProofViewNotification, 
    ResetRocqRequest, 
    ResetRocqResponse, 
    SearchRocqResult
} from './protocol/types';
import { 
    sendInterpretToPoint,
    sendInterpretToEnd,
    sendStepForward,
    sendStepBackward
} from './manualChecking';
import { DocumentStateViewProvider } from './panels/DocumentStateViewProvider';
import VsRocqToolchainManager, {ToolchainError, ToolChainErrorCode} from './utilities/toolchain';
import { QUICKFIX_COMMAND, RocqWarningQuickFix } from './QuickFixProvider';
import { startMCPServer } from './mcpServer';
import { stringOfPpString } from './utilities/pputils';

let client: Client;

export type McpPromiseBox = {
    promise: Promise<string> | undefined,
    setValue: ((value: string) => void) | undefined
};

let mcpPromiseBox: McpPromiseBox = {
    promise: undefined,
    setValue: undefined
};

export function activate(context: ExtensionContext) {
    const getDocumentProofs = (uri: Uri) => {
        const textDocument = TextDocumentIdentifier.create(uri.toString());
        const params: DocumentProofsRequest = {textDocument};
        const req = new RequestType<DocumentProofsRequest, DocumentProofsResponse, void>("prover/documentProofs");
        Client.writeToVsrocqChannel("Getting proofs for: " + uri.toString());
        return client.sendRequest(req, params);
    };

    const rocqTM = new VsRocqToolchainManager();
    rocqTM.intialize().then(
        () => {
            const serverOptions = rocqTM.getServerConfiguration(); 
            intializeExtension(serverOptions);
        }, 
        (err: ToolchainError) => {
            switch(err.status) {

                case ToolChainErrorCode.notFound: 
                    window.showErrorMessage("No language server found", {modal: true, detail: err.message}, {title: "Install the VsRocq language server (Recommended for Rocq >= 8.18)", id: 0}, {title: "Install VsRocq Legacy (Required for Rocq <= 8.17)", id: 1})
                    .then(act => {
                        if(act?.id === 0) {
                            commands.executeCommand("vscode.open", Uri.parse('https://github.com/rocq-prover/vscoq?tab=readme-ov-file#installing-the-language-server'));
                        }
                        if (act?.id === 1) {
                            commands.executeCommand("extension.open", "coq-community.vscoq1");
                        }
                    });
                    break;

                case ToolChainErrorCode.launchError: 
                    window.showErrorMessage("Could not launch language server" + err.message, {modal: true, detail: err.message}, {title: "Get Rocq", id: 0}, {title: "Install VsRocq Legacy (Required for Rocq <= 8.17)", id: 1})
                    .then(act => {
                        if(act?.id === 0) {
                            commands.executeCommand("vscode.open", Uri.parse('https://rocq.inria.fr/download'));
                        }
                        if (act?.id === 1) {
                            commands.executeCommand("extension.open", "rocq-community.vsrocq1");
                        }
                        
                    });
                    
            }
        }
    );
    
    // Detect if vsrocq1 is installed and active
    const vsrocq1 = extensions.getExtension("rocq-community.vsrocq1");
    if (vsrocq1) {
        if (vsrocq1.isActive) {
            const message = "VsRocq2 is incompatible with VsRocq1. it is recommended that you disable one of them.";
            window.showErrorMessage(message, { title: "Disable VsRocq1", id: 0 }, { title: "Disable VsRocq2", id: 1 })
                .then(act => {
                    if (act?.id === 0) {
                        commands.executeCommand("extension.open", "rocq-community.vsrocq1");
                    }
                    if (act?.id === 1) {
                        commands.executeCommand("extension.open", "rocq-prover.vsrocq");
                    }

                });
        }
    }

    const getConfigString = (serverInfo : any) => {
      const clean_strings = (str: string) => {
        // Properly escape backticks and pipes in the string, replace newlines with spaces
        return str.replace(/`/g, '\\`').replace(/\|/g, '\\|').replace(/\n/g, ' ');
      };
        return (
`| Debug Information | Value |
| ----------------- | -------------------------------- |
| Rocq Installation | ${clean_strings(rocqTM.getversionFullOutput())} |
| Rocq Path         | \`${clean_strings(rocqTM.getRocqPath())}\` |
| VsRocq Extension Version   | ${clean_strings(extensions.getExtension('rocq-prover.vsrocq')?.packageJSON.version)} |
| VsRocqTop Version | ${clean_strings(serverInfo?.version)} |
| VsRocqTop Path  | \`${clean_strings(rocqTM.getVsRocqTopPath())}\` |
| OS               | ${process.arch} ${process.platform} |
| VSCode Version | ${version} |
`
        );

    };

    function registerVsrocqTextCommand(command: string, callback: (textEditor: TextEditor, ...args: any[]) => void) {
        context.subscriptions.push(commands.registerTextEditorCommand('extension.rocq.' + command, callback));
    };
    
    function intializeExtension(serverOptions: ServerOptions) {
        const config = workspace.getConfiguration('vsrocq');

        let clientOptions: LanguageClientOptions = {
            documentSelector: [{ scheme: 'file', language: 'rocq' }],
            initializationOptions: config
        };

        // Create the language client and start the client.
        client = new Client(
            serverOptions,
            clientOptions
        );

        //register the search view provider 
        const searchProvider = new SearchViewProvider(context.extensionUri, client);
        context.subscriptions.push(window.registerWebviewViewProvider(SearchViewProvider.viewType, searchProvider));

        if (workspace.getConfiguration('vscoq.mcp.use')) {
            // Start MCP server
            startMCPServer(context, mcpPromiseBox, client);
        }

        const documentStateProvider = new DocumentStateViewProvider(client); 
        context.subscriptions.push(workspace.registerTextDocumentContentProvider("vsrocq-document-state", documentStateProvider));

        //status bar item for showing rocq version and language server version
        const statusBar: StatusBarItem = window.createStatusBarItem(StatusBarAlignment.Right, 1000);
        context.subscriptions.push(statusBar);

        const launchQuery = (editor: TextEditor, type: string)=> {
            const selection = editor.selection;
            const {end, start} = selection; 
            if(end.line !== start.line) {return;} //don't allow for multiline selections
            //either use the user selection or if no selection than infer the word under the cursor
            const wordAtCurorRange = (end.character !== start.character) ? selection : editor.document.getWordRangeAtPosition(end);
            //focus on the query panel
            commands.executeCommand('vsrocq.search.focus');
            //open a prompt with the given word as default
            window.showInputBox({
                prompt: type.charAt(0).toUpperCase() + type.slice(1),
                value: wordAtCurorRange ? editor.document.getText(wordAtCurorRange) : undefined
            }).then(queryText => {
                //launch the query
                if(queryText) {
                    searchProvider.launchQuery(queryText, type);
                }
            });
        };

        registerVsrocqTextCommand('reset', (editor) => {
            const uri = editor.document.uri;
            const textDocument = TextDocumentIdentifier.create(uri.toString());
            const params: ResetRocqRequest = {textDocument};
            const req = new RequestType<ResetRocqRequest, ResetRocqResponse, void>("prover/resetRocq");
            Client.writeToVsrocqChannel(uri.toString());
            client.sendRequest(req, params).then(
                (res) => {
                    GoalPanel.resetGoalPanel();
                }, 
                (err) => {
                    window.showErrorMessage(err);
                }
            );
        });
        registerVsrocqTextCommand('query.search', (editor) => launchQuery(editor, "search"));
        registerVsrocqTextCommand('query.about', (editor) => launchQuery(editor, "about"));
        registerVsrocqTextCommand('query.check', (editor) => launchQuery(editor, "check"));
        registerVsrocqTextCommand('query.locate', (editor) => launchQuery(editor, "locate"));
        registerVsrocqTextCommand('query.print', (editor) => launchQuery(editor, "print"));
        registerVsrocqTextCommand('addQueryTab', () => searchProvider.addTab());
        registerVsrocqTextCommand('collapseAllQueries', () => searchProvider.collapseAll());
        registerVsrocqTextCommand('expandAllQueries', () => searchProvider.expandAll());
        registerVsrocqTextCommand('interpretToPoint', (editor) => sendInterpretToPoint(editor, client));
        registerVsrocqTextCommand('interpretToEnd', (editor) => sendInterpretToEnd(editor, client));
        registerVsrocqTextCommand('stepForward', (editor) => sendStepForward(editor, client));
        registerVsrocqTextCommand('stepBackward', (editor) => sendStepBackward(editor, client));
        registerVsrocqTextCommand('documentState', async (editor) => {
                
            documentStateProvider.setDocumentUri(editor.document.uri);

            const document = await workspace.openTextDocument(documentStateProvider.uri);

            documentStateProvider.fire();

            await window.showTextDocument(document, {
                viewColumn: ViewColumn.Two,
                preserveFocus: true,
            }); 
            
        });
        registerVsrocqTextCommand('showLog', () => {
            Client.showLog();
        });
        registerVsrocqTextCommand('showSetup', () => {
            const serverInfo = client.initializeResult!.serverInfo;
            const configString = getConfigString(serverInfo);
            window.showInformationMessage(configString, {modal: true}, { title: "Copy to clipboard", id: 0 })
                .then(act => {
                    if (act?.id === 0) {
                        env.clipboard.writeText(configString);
                    }
                });
        });
        registerVsrocqTextCommand('walkthrough', () => {
            commands.executeCommand('workbench.action.openWalkthrough', 'rocq-prover.vsrocq#rocq.welcome', false); 
        });
        registerVsrocqTextCommand('showManual', () => {
            const url = getRocqdocUrl(rocqTM.getRocqVersion());
            commands.executeCommand('simpleBrowser.show', url); 
        });
        registerVsrocqTextCommand('displayProofView', () => {
            const editor = window.activeTextEditor ? window.activeTextEditor : window.visibleTextEditors[0];
            GoalPanel.displayProofView(context.extensionUri, editor);
        });
            
        client.onNotification("prover/updateHighlights", (notification) => {
        
            client.saveHighlights(
                notification.uri,
                notification.preparedRange,
                notification.processingRange,
                notification.processedRange
            );
        
            client.updateHightlights();
        });

        client.onNotification("prover/moveCursor", (notification: MoveCursorNotification) => {
            const {uri, range} = notification;
            const editors = window.visibleTextEditors.filter(editor => {
                return editor.document.uri.toString() === uri.toString();
            });
            if(workspace.getConfiguration('vsrocq.proof.cursor').sticky === true ||
            workspace.getConfiguration('vsrocq.proof').mode === 1) {
                editors.map(editor => {
                    editor.selections = [new Selection(range.end, range.end)];
                    editor.revealRange(range, TextEditorRevealType.Default);
                });
            }
        });

        client.onNotification("prover/searchResult", (searchResult: SearchRocqResult) => {
            searchProvider.renderSearchResult(searchResult);
        });

        client.onNotification("prover/proofView", (proofView: ProofViewNotification) => {
            const editor = window.activeTextEditor ? window.activeTextEditor : window.visibleTextEditors[0];
            const autoDisplay = workspace.getConfiguration('vsrocq.goals').auto;
            GoalPanel.proofViewNotification(context.extensionUri, editor, proofView, autoDisplay);
            if (mcpPromiseBox.setValue) {
                const msgStr = proofView.messages.map((msg) => {
                    return stringOfPpString(msg[1]);
                }).toString();
                const goalStr = proofView.proof?.goals?.map((goal) => {
                    const hypsStr = goal.hypotheses.map((h) => {
                        return stringOfPpString(h);
                    }).toString();
                    const gStr = stringOfPpString(goal.goal);
                    return [hypsStr, gStr].toString();
                });
                const str = JSON.stringify({ message: msgStr, goal: goalStr });
                mcpPromiseBox.setValue(str);
            }
        });

        client.onNotification("prover/blockOnError", (notification: ErrorAlertNotification) => {
            const {uri, range} = notification;
            client.createErrorAnimation(uri.toString(), [range]);
        });

        client.onNotification("prover/debugMessage", (rocqMessage: RocqLogMessage) => {
            const {message} = rocqMessage;
            const messageString = `${message}`;
            Client.writeRocqMessageLog(messageString);
        });

        context.subscriptions.push(commands.registerCommand(QUICKFIX_COMMAND, (data) => {
            const {text, range, document} = data;
            const edit = new WorkspaceEdit();
            edit.replace(document.uri, range, text);
            workspace.applyEdit(edit);
        }));
        languages.registerCodeActionsProvider('rocq', new RocqWarningQuickFix(), {
            providedCodeActionKinds: RocqWarningQuickFix.providedCodeActionKinds
        });

        client.start()
        .then(() => {
            
            checkVersion(client, context);
            const serverInfo = client.initializeResult!.serverInfo;
            const configString = new MarkdownString(
                
`**Rocq Installation**

${rocqTM.getversionFullOutput()}

Path: \`${rocqTM.getRocqPath()}\`
---

**vsrocqtop** ${serverInfo?.version}

Path: \`${rocqTM.getVsRocqTopPath()}\`
`
                            );
            statusBar.text = `${serverInfo?.name} ${serverInfo?.version}, rocq ${rocqTM.getRocqVersion()}`;
            statusBar.tooltip = configString;
            statusBar.show();

            initializeDecorations(context);
            
            // I think vscode should handle this automatically, TODO: try again after implemeting client capabilities
            context.subscriptions.push(workspace.onDidChangeConfiguration(event => {
                updateServerOnConfigurationChange(event, context, client);

                if(event.affectsConfiguration('vsrocq.proof.mode')) {
                    client.resetHighlights();
                    client.updateHightlights();
                }

                if(event.affectsConfiguration('vsrocq.goals.display')) {
                    GoalPanel.toggleGoalDisplaySettings();
                }

                if(event.affectsConfiguration('vsrocq.goals.maxDepth')) {
                    GoalPanel.changeGoalDisplayDepth();
                }
            }));

            let goalsHook = window.onDidChangeTextEditorSelection(
                (evt: TextEditorSelectionChangeEvent) => {                    
                    if (evt.textEditor.document.languageId === "rocq"
                        && workspace.getConfiguration('vsrocq.proof').mode === 1)
                    {
                        sendInterpretToPoint(evt.textEditor, client);
                    }
                }
            );

            window.onDidChangeActiveTextEditor(editor => {
                client.updateHightlights();
            });

        });

        context.subscriptions.push(client);
    }

    const externalApi = {
        getDocumentProofs
    };

    return externalApi;

}

// This method is called when your extension is deactivated
export function deactivate() {
}
