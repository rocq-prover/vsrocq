import { ExtensionContext, workspace } from 'vscode';
import Client from '../client';
import * as express from "express";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { McpPromiseBox, ProofState } from './MCPState';
import { getMCPServer } from './MCPServer';
import { writeMCPConfigToWorkspace } from './MCPConfig';

export async function startMCPServer(context: ExtensionContext, mcpPromiseBox: McpPromiseBox, proofState: ProofState, client: Client) {

    writeMCPConfigToWorkspace();

    const app = express();
    app.use(express.json());

    app.post('/mcp', async (req: express.Request, res: express.Response) => {
        try {
            const server = getMCPServer(mcpPromiseBox, proofState, client);
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
