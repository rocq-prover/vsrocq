import { z } from "zod";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { sendInterpretToPoint, sendStepForward, sendStepBackward, sendInterpretToEnd } from '../manualChecking';
import { McpPromiseBox, ProofState } from "./MCPState";
import Client from "../client";
import { Position, Range, Selection, TextEditorRevealType, window, workspace } from "vscode";
import { stringOfPpString } from "../utilities/pputils";
import { ProofViewNotification } from "../protocol/types";

function awaitMcpPromiseBox(editor: any, mcpPromiseBox: McpPromiseBox, requestId: string | undefined): Promise<string> {
    mcpPromiseBox.currentDocumentURI = editor.document.uri.toString();
    mcpPromiseBox.pendingRequestId = requestId;
    mcpPromiseBox.promise = new Promise((resolve) => {
        mcpPromiseBox.setValue = resolve;
    });
    return mcpPromiseBox.promise;
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

export function getMCPServer(mcpPromiseBox: McpPromiseBox, proofState: ProofState, client: Client) {
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