import { workspace } from "vscode";
import * as fs from 'fs';
import * as path from 'path';

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

export function writeMCPConfigToWorkspace() {
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