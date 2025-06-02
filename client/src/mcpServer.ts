import { ExtensionContext, window, workspace, Position, Selection, TextEditorRevealType, Range } from 'vscode';
import { sendInterpretToPoint, sendStepForward, sendStepBackward, sendInterpretToEnd } from './manualChecking';
import { McpPromiseBox, ProofState } from './extension';
import Client from './client';
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import * as express from "express";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { z } from "zod";
import * as fs from 'fs';
import * as path from 'path';
import { stringOfPpString } from './utilities/pputils';
import { ProofViewNotification } from './protocol/types';

function getServer(mcpPromiseBox: McpPromiseBox, proofState: ProofState, client: Client) {
    const server = new McpServer({
        name: "VsRocq MCP Server",
        version: "1.0.0"
    });

    server.tool(
        "interpretToPoint",
        "Interpret to the given point (or current cursor) in the active Coq editor.",
        {
            line: z.number().optional(),
            character: z.number().optional()
        },
        async ({ line, character }) => {
            let editor = window.activeTextEditor;
            console.log('[MCP] interpretToPoint called', { line, character, editorExists: !!editor });
            if (editor && line !== undefined && character !== undefined) {
                const pos = new Position(line, character);
                const range = new Range(pos, pos);
                editor.selections = [new Selection(range.start, range.end)];
                editor.revealRange(range, TextEditorRevealType.Default);
                console.log('[MCP] Cursor moved to', pos);
            }
            if (editor) {
                await sendInterpretToPoint(editor, client);
                console.log('[MCP] sendInterpretToPoint finished');
                mcpPromiseBox.currentDocumentURI = editor.document.uri.toString();
                mcpPromiseBox.promise = new Promise((resolve) => {
                  mcpPromiseBox.setValue = resolve;
                });
                const res = await mcpPromiseBox.promise;
                console.log('[MCP] interpretToPoint resolved with', res);
                return { content: [{ type: "text", text: res }] };
            } else {
                console.log('[MCP] No active editor for interpretToPoint');
                return { content: [{ type: "text", text: "No active editor" }] };
            }
        }
    );

    server.tool(
        "stepForward",
        "Step forward one command in the active Coq editor.",
        {},
        async () => {
            const editor = window.activeTextEditor;
            console.log('[MCP] stepForward called', { editorExists: !!editor });
            if (editor) {
                await sendStepForward(editor, client);
                console.log('[MCP] sendStepForward finished');
                mcpPromiseBox.currentDocumentURI = editor.document.uri.toString();
                mcpPromiseBox.promise = new Promise((resolve) => {
                  mcpPromiseBox.setValue = resolve;
                });
                const res = await mcpPromiseBox.promise;
                console.log('[MCP] stepForward resolved with', res);
                return { content: [{ type: "text", text: res }] };
            } else {
                console.log('[MCP] No active editor for stepForward');
                return { content: [{ type: "text", text: "No active editor" }] };
            }
        }
    );

    server.tool(
        "stepBackward",
        "Step backward one command in the active Coq editor.",
        {},
        async () => {
            const editor = window.activeTextEditor;
            console.log('[MCP] stepBackward called', { editorExists: !!editor });
            if (editor) {
                await sendStepBackward(editor, client);
                console.log('[MCP] sendStepBackward finished');
                mcpPromiseBox.currentDocumentURI = editor.document.uri.toString();
                mcpPromiseBox.promise = new Promise((resolve) => {
                  mcpPromiseBox.setValue = resolve;
                });
                const res = await mcpPromiseBox.promise;
                console.log('[MCP] stepBackward resolved with', res);
                return { content: [{ type: "text", text: res }] };
            } else {
                console.log('[MCP] No active editor for stepBackward');
                return { content: [{ type: "text", text: "No active editor" }] };
            }
        }
    );

    server.tool(
        "interpretToEnd",
        "Interpret to the end of the active Coq editor.",
        {},
        async () => {
            const editor = window.activeTextEditor;
            console.log('[MCP] interpretToEnd called', { editorExists: !!editor });
            if (editor) {
                await sendInterpretToEnd(editor, client);
                mcpPromiseBox.currentDocumentURI = editor.document.uri.toString();
                mcpPromiseBox.promise = new Promise((resolve) => {
                    mcpPromiseBox.setValue = resolve;
                });
                const res = await mcpPromiseBox.promise;
                console.log('[MCP] interpretToEnd resolved with', res);
                return { content: [{ type: "text", text: res }] };
            } else {
                console.log('[MCP] No active editor for interpretToEnd');
                return { content: [{ type: "text", text: "No active editor" }] };
            }
        }
    );

    server.tool(
        "proofView",
        "Get the current proof view and the current interpretation point.",
        {},
        async () => {
            const editor = window.activeTextEditor;
            const currentDocumentURI = editor?.document.uri.toString();
            const result = getPrettifiedProofView(client, proofState.lastProofViewNotification, currentDocumentURI);
            return { content: [{ type: "text", text: result }] };
        }
    );

    return server;
}

const vsCoqConfig = {
    type: "http",
    url: "http://localhost:2137/mcp"
};
const serversOfVsCoq = {
    servers: {
        "VsCoq": vsCoqConfig
    }
};

function writeMCPConfigToWorkspace() {
    try {
        // Use the first workspace folder as the root
        const workspaceRoot = workspace.workspaceFolders && workspace.workspaceFolders.length > 0
            ? workspace.workspaceFolders[0].uri.fsPath
            : process.cwd();
        const vscodeDir = path.join(workspaceRoot, '.vscode');
        const mcpConfigPath = path.join(vscodeDir, 'mcp.json');
        let shouldWrite = false;
        let config: any = { servers: {} };
        if (!fs.existsSync(vscodeDir)) {
            fs.mkdirSync(vscodeDir);
        }
        if (fs.existsSync(mcpConfigPath)) {
            try {
                const raw = fs.readFileSync(mcpConfigPath, 'utf8');
                config = JSON.parse(raw);
                if (!config.servers) { config.servers = {}; }
                if (!config.servers["VsCoq"]) {
                    config.servers["VsCoq"] = vsCoqConfig;
                    shouldWrite = true;
                }
            } catch (e) {
                // If file is corrupt, overwrite it
                config = serversOfVsCoq;
                shouldWrite = true;
            }
        } else {
            config = serversOfVsCoq;
            shouldWrite = true;
        }
        if (shouldWrite) {
            fs.writeFileSync(mcpConfigPath, JSON.stringify(config, null, 2));
            console.log('[MCP] Wrote .vscode/mcp.json with VsCoq server entry');
        } else {
            console.log('[MCP] .vscode/mcp.json already contains VsCoq server entry');
        }
    } catch (err) {
        console.error('[MCP] Error ensuring .vscode/mcp.json:', err);
    }
}

// Returns a prettified proof view message for MCP clients
export function getPrettifiedProofView(client: Client, proofView: ProofViewNotification | undefined, textDocumentURI: string | undefined): string {
    if (!proofView) {
        return JSON.stringify({
            message: "No proof view available.",
            interpretedUpTo: null,
            goal: null
        });
    }
    // Prettify messages
    const msgStr = proofView.messages.map((msg: any) => {
        return stringOfPpString(msg[1]);
    }).toString();
    // Prettify goals
    const goalStr = proofView.proof?.goals?.map((goal: any) => {
        const hypsStr = goal.hypotheses.map((h: any) => {
            return stringOfPpString(h);
        }).toString();
        const gStr = stringOfPpString(goal.goal);
        return [hypsStr, gStr].toString();
    });
    // Get highlight end position (last interpreted point)
    const highlightEnds = client.getHighlights(textDocumentURI ? String(textDocumentURI) : "");
    let highlightEnd = null;
    if (highlightEnds && highlightEnds[0] && highlightEnds[0].end) {
        // +1 to match the user positions
        highlightEnd = {
            line: highlightEnds[0].end.line + 1,
            character: highlightEnds[0].end.character + 1
        };
    }
    return JSON.stringify({
        message: msgStr,
        interpretedUpTo: highlightEnd,
        goal: goalStr
    });
}

export async function startMCPServer(context: ExtensionContext, mcpPromiseBox: McpPromiseBox, proofState: ProofState, client: Client) {

    writeMCPConfigToWorkspace();

    const app = express();
    app.use(express.json());

    app.post('/mcp', async (req: express.Request, res: express.Response) => {
        console.log('[MCP] POST /mcp called', { body: req.body });
        try {
            const server = getServer(mcpPromiseBox, proofState, client);
            const transport: StreamableHTTPServerTransport = new StreamableHTTPServerTransport({
                sessionIdGenerator: undefined,
            });
            res.on('close', () => {
                console.log('[MCP] Request closed');
                transport.close();
                server.close();
            });
            await server.connect(transport);
            await transport.handleRequest(req, res, req.body);
            console.log('[MCP] transport.handleRequest finished');
        } catch (error) {
            console.error('[MCP] Error handling MCP request:', error);
            if (!res.headersSent) {
                res.status(500).json({
                    jsonrpc: '2.0',
                    error: {
                        code: -32603,
                        message: 'Internal server error',
                    },
                    id: null,
                });
            }
        }
    });

    app.get('/mcp', async (req: express.Request, res: express.Response) => {
        console.log('[MCP] Received GET MCP request');
        res.writeHead(405).end(JSON.stringify({
            jsonrpc: "2.0",
            error: {
                code: -32000,
                message: "Method not allowed."
            },
            id: null
        }));
    });

    app.delete('/mcp', async (req: express.Request, res: express.Response) => {
        console.log('[MCP] Received DELETE MCP request');
        res.writeHead(405).end(JSON.stringify({
            jsonrpc: "2.0",
            error: {
                code: -32000,
                message: "Method not allowed."
            },
            id: null
        }));
    });

    // Start the server
    const PORT = 2137;
    app.listen(PORT, () => {
        console.log(`[MCP] Stateless Streamable HTTP Server listening on port ${PORT}`);
    });
}
