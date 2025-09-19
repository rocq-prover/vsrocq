import { ExtensionContext, window, workspace, Position, Selection, TextEditorRevealType, Range } from 'vscode';
import { sendInterpretToPoint, sendStepForward, sendStepBackward, sendInterpretToEnd } from './manualChecking';
import Client from './client';
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import * as express from "express";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { z } from "zod";
import * as fs from 'fs';
import * as path from 'path';
import { stringOfPpString } from './utilities/pputils';
import { ProofViewNotification } from './protocol/types';

export type McpPromiseBox = {
    promise: Promise<string> | undefined,
    setValue: ((value: string) => void) | undefined,
    currentDocumentURI: string | undefined,
    pendingRequestId: string | undefined
};

export let mcpPromiseBox: McpPromiseBox = {
    promise: undefined,
    setValue: undefined,
    currentDocumentURI: undefined,
    pendingRequestId: undefined
};

export type ProofState = {
    lastProofViewNotification: ProofViewNotification | undefined
};

export let proofState: ProofState = {
    lastProofViewNotification: undefined
};

function awaitMcpPromiseBox(editor: any, mcpPromiseBox: McpPromiseBox, requestId: string | undefined): Promise<string> {
    mcpPromiseBox.currentDocumentURI = editor.document.uri.toString();
    mcpPromiseBox.pendingRequestId = requestId;
    console.log("requestId:");
    console.log(requestId);
    mcpPromiseBox.promise = new Promise((resolve) => {
        mcpPromiseBox.setValue = resolve;
    });
    return mcpPromiseBox.promise;
}

function getServer(mcpPromiseBox: McpPromiseBox, proofState: ProofState, client: Client) {
    const server = new McpServer({
        name: "VsRocq MCP Server",
        version: "1.0.0"
    });

    server.tool(
        "interpretToPoint",
        "Interpret to the given point (or current cursor) in the active Rocq editor.",
        {
            line: z.number().optional(),
            character: z.number().optional()
        },
        async ({ line, character }) => {
            const mode = workspace.getConfiguration('vsrocq.proof').get<number>('mode');
            if (mode !== 0) {
                return { content: [{ type: 'text', text: 'Proof mode must be manual to use this tool.' }] };
            }
            let editor = window.activeTextEditor;
            if (editor && line !== undefined && character !== undefined) {
                const pos = new Position(line, character);
                const range = new Range(pos, pos);
                editor.selections = [new Selection(range.start, range.end)];
                editor.revealRange(range, TextEditorRevealType.Default);
            }
            if (editor) {
                const requestId = await sendInterpretToPoint(editor, client);
                const res = await awaitMcpPromiseBox(editor, mcpPromiseBox, requestId);
                return { content: [{ type: "text", text: res }] };
            } else {
                return { content: [{ type: "text", text: "No active editor" }] };
            }
        }
    );

    server.tool(
        "stepForward",
        "Step forward one command in the active Rocq editor.",
        {},
        async () => {
            const mode = workspace.getConfiguration('vsrocq.proof').get<number>('mode');
            if (mode !== 0) {
                return { content: [{ type: 'text', text: 'Proof mode must be manual to use this tool.' }] };
            }
            const editor = window.activeTextEditor;
            if (editor) {
                const requestId = await sendStepForward(editor, client);
                const res = await awaitMcpPromiseBox(editor, mcpPromiseBox, requestId);
                return { content: [{ type: "text", text: res }] };
            } else {
                return { content: [{ type: "text", text: "No active editor" }] };
            }
        }
    );

    server.tool(
        "stepBackward",
        "Step backward one command in the active Rocq editor.",
        {},
        async () => {
            const mode = workspace.getConfiguration('vsrocq.proof').get<number>('mode');
            if (mode !== 0) {
                return { content: [{ type: 'text', text: 'Proof mode must be manual to use this tool.' }] };
            }
            const editor = window.activeTextEditor;
            if (editor) {
                const requestId = await sendStepBackward(editor, client);
                const res = await awaitMcpPromiseBox(editor, mcpPromiseBox, requestId);
                return { content: [{ type: "text", text: res }] };
            } else {
                return { content: [{ type: "text", text: "No active editor" }] };
            }
        }
    );

    server.tool(
        "interpretToEnd",
        "Interpret to the end of the active Rocq editor.",
        {},
        async () => {
            const mode = workspace.getConfiguration('vsrocq.proof').get<number>('mode');
            if (mode !== 0) {
                return { content: [{ type: 'text', text: 'Proof mode must be manual to use this tool.' }] };
            }
            const editor = window.activeTextEditor;
            if (editor) {
                const requestId = await sendInterpretToEnd(editor, client);
                console.log(requestId);
                const res = await awaitMcpPromiseBox(editor, mcpPromiseBox, requestId);
                return { content: [{ type: "text", text: res }] };
            } else {
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

function vsRocqConfig(port: number) {
    return {
        type: "http",
        url: `http://localhost:${port}/mcp`
    };
}

function serversOfVsRocq(port: number) {
    return {
        servers: {
            "vsRocq": vsRocqConfig(port)
        }
    };
}

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
        const portConfig = workspace.getConfiguration('vsrocq.mcp').get<number>('port');
        const port = portConfig ?? 2138;
        if (fs.existsSync(mcpConfigPath)) {
            try {
                const raw = fs.readFileSync(mcpConfigPath, 'utf8');
                config = JSON.parse(raw);
                if (!config.servers) { config.servers = {}; }
                if (!config.servers["VsRocq"]) {
                    config.servers["VsRocq"] = vsRocqConfig(port);
                    shouldWrite = true;
                }
            } catch (e) {
                // If file is corrupt, overwrite it
                config = serversOfVsRocq(port);
                shouldWrite = true;
            }
        } else {
            config = serversOfVsRocq(port);
            shouldWrite = true;
        }
        if (shouldWrite) {
            fs.writeFileSync(mcpConfigPath, JSON.stringify(config, null, 2));
        } else {
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
        try {
            const server = getServer(mcpPromiseBox, proofState, client);
            const transport: StreamableHTTPServerTransport = new StreamableHTTPServerTransport({
                sessionIdGenerator: undefined,
            });
            res.on('close', () => {
                transport.close();
                server.close();
            });
            await server.connect(transport);
            await transport.handleRequest(req, res, req.body);
        } catch (error) {
            if (!res.headersSent) {
                sendHttpError(res, 500, -32603, 'Internal server error');
            }
        }
    });

    function sendHttpError(res: express.Response, httpStatus: number, errorCode: number, message: string) {
        res.status(httpStatus).json({
            jsonrpc: "2.0",
            error: {
                code: errorCode,
                message: message
            },
            id: null
        });
    }

    app.get('/mcp', async (req: express.Request, res: express.Response) => {
        sendHttpError(res, 405, -32000, "Method not allowed.");
    });

    app.delete('/mcp', async (req: express.Request, res: express.Response) => {
        sendHttpError(res, 405, -32000, "Method not allowed.");
    });

    const portConfig = workspace.getConfiguration('vsrocq.mcp').get<number>('port');
    const PORT = portConfig ?? 2138;
    app.listen(PORT);
}
