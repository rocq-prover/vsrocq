import type {
    Range,
    Scope,
    UniverseGraph,
    UniversesMessage,
    UniversesWebviewMessage,
} from "universes-ui/src/types";
import {
    Disposable,
    OverviewRulerLane,
    Position,
    TextEditor,
    TextEditorRevealType,
    Uri,
    ViewColumn,
    Range as VsRange,
    Webview,
    WebviewPanel,
    window,
} from "vscode";
import {
    RequestType,
    VersionedTextDocumentIdentifier,
} from "vscode-languageclient";
import Client from "../client";
import { getNonce } from "../utilities/getNonce";
import { getUri } from "../utilities/getUri";
import { makeVersionedDocumentId } from "../utilities/utils";
import GoalPanel from "./GoalPanel";

interface UniversesRequest {
    textDocument: VersionedTextDocumentIdentifier;
    position: Position;
    global: boolean;
    subgraph?: string[];
}

const universesReq = new RequestType<UniversesRequest, UniverseGraph, void>(
    "prover/universes",
);

// The source of a universe, shown briefly when its node is clicked
const revealDecoration = window.createTextEditorDecorationType({
    backgroundColor: { id: "editor.findMatchHighlightBackground" },
    overviewRulerColor: { id: "editor.findMatchHighlightBackground" },
    overviewRulerLane: OverviewRulerLane.Center,
});

/**
 * The universe graph view: the universes of the proof at the cursor, as
 * Show Universes, or the global ones, as Print Universes. It follows the
 * cursor of the last active Rocq editor, refreshing with the proof view.
 */
export default class UniversesPanel {
    public static currentPanel: UniversesPanel | undefined;
    private readonly _panel: WebviewPanel;
    private readonly _client: Client;
    private _disposables: Disposable[] = [];
    private _editor: TextEditor;
    private _scope: Scope;
    private _subgraph: string[] = [];
    // to drop the responses of outdated requests
    private _request = 0;

    private constructor(
        panel: WebviewPanel,
        extensionUri: Uri,
        client: Client,
        editor: TextEditor,
        scope: Scope,
    ) {
        this._panel = panel;
        this._client = client;
        this._editor = editor;
        this._scope = scope;
        this._panel.onDidDispose(() => this.dispose(), null, this._disposables);
        this._panel.webview.html = this._getWebviewContent(
            this._panel.webview,
            extensionUri,
        );
        this._panel.webview.onDidReceiveMessage(
            (message: UniversesWebviewMessage) => this._onMessage(message),
            undefined,
            this._disposables,
        );
        window.onDidChangeActiveTextEditor(
            (e) => {
                if (e && e.document.languageId === "rocq") {
                    this._editor = e;
                }
            },
            undefined,
            this._disposables,
        );
        this._disposables.push(
            GoalPanel.onProofStateChanged(() => this._refresh()),
        );
    }

    public static render(
        extensionUri: Uri,
        client: Client,
        editor: TextEditor,
        scope: Scope,
    ) {
        const current = UniversesPanel.currentPanel;
        if (current) {
            current._editor = editor;
            current._scope = scope;
            current._panel.reveal(undefined, true);
            current._refresh();
            return;
        }
        const column =
            editor.viewColumn !== undefined
                ? Math.min(editor.viewColumn + 1, ViewColumn.Three)
                : ViewColumn.Two;
        const panel = window.createWebviewPanel(
            "rocq.universes",
            "Rocq Universes",
            { preserveFocus: true, viewColumn: column },
            {
                enableScripts: true,
                localResourceRoots: [
                    Uri.joinPath(extensionUri, "universes-ui/build"),
                ],
                retainContextWhenHidden: true,
            },
        );
        UniversesPanel.currentPanel = new UniversesPanel(
            panel,
            extensionUri,
            client,
            editor,
            scope,
        );
    }

    public dispose() {
        UniversesPanel.currentPanel = undefined;
        this._panel.dispose();
        while (this._disposables.length) {
            this._disposables.pop()?.dispose();
        }
    }

    private _postMessage(message: UniversesMessage) {
        this._panel.webview.postMessage(message);
    }

    private _onMessage(message: UniversesWebviewMessage) {
        switch (message.command) {
            case "ready":
                this._refresh();
                break;
            case "reveal":
                this._reveal(message.range);
                break;
            case "setScope":
                this._scope = message.scope;
                this._refresh();
                break;
            case "setSubgraph":
                this._subgraph = message.subgraph;
                this._refresh();
                break;
        }
    }

    private _refresh() {
        const editor = this._editor;
        if (editor.document.isClosed) {
            return;
        }
        const scope = this._scope;
        const subgraph = this._subgraph;
        const request = ++this._request;
        this._postMessage({ command: "loading", scope, subgraph });
        const params: UniversesRequest = {
            textDocument: makeVersionedDocumentId(editor),
            position: editor.selection.active,
            global: scope === "global",
            subgraph: scope === "global" ? subgraph : undefined,
        };
        this._client.sendRequest(universesReq, params).then(
            (data) => {
                if (request === this._request) {
                    this._postMessage({
                        command: "render",
                        scope,
                        subgraph,
                        data,
                    });
                }
            },
            (err) => {
                if (request === this._request) {
                    this._postMessage({
                        command: "error",
                        scope,
                        subgraph,
                        message: err?.message ?? String(err),
                    });
                }
            },
        );
    }

    // Shows the range in the editor without moving the cursor, which would
    // change the universes shown
    private _reveal(range: Range) {
        const editor = window.visibleTextEditors.find(
            (e) =>
                e.document.uri.toString() ===
                this._editor.document.uri.toString(),
        );
        if (!editor) {
            return;
        }
        const r = new VsRange(
            range.start.line,
            range.start.character,
            range.end.line,
            range.end.character,
        );
        editor.revealRange(r, TextEditorRevealType.InCenterIfOutsideViewport);
        editor.setDecorations(revealDecoration, [r]);
        setTimeout(() => editor.setDecorations(revealDecoration, []), 2000);
    }

    private _getWebviewContent(webview: Webview, extensionUri: Uri) {
        const stylesUri = getUri(webview, extensionUri, [
            "universes-ui",
            "build",
            "assets",
            "index.css",
        ]);
        const scriptUri = getUri(webview, extensionUri, [
            "universes-ui",
            "build",
            "assets",
            "index.js",
        ]);
        const nonce = getNonce();
        return /*html*/ `
      <!DOCTYPE html>
      <html lang="en">
        <head>
          <meta charset="UTF-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1.0" />
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src ${webview.cspSource}; script-src 'nonce-${nonce}';">
          <link rel="stylesheet" type="text/css" nonce="${nonce}" href="${stylesUri}">
          <title>Universes</title>
        </head>
        <body>
          <div id="root"></div>
          <script type="module" nonce="${nonce}" src="${scriptUri}"></script>
        </body>
      </html>
    `;
    }
}
