import * as vscode from "vscode";
import { LanguageClient } from "vscode-languageclient/node";

export function sendConfiguration(client: LanguageClient) {
    const config = vscode.workspace.getConfiguration("vsrocq");
    client.sendNotification("workspace/didChangeConfiguration", {
        settings: config,
    });
}

export function updateServerOnConfigurationChange(
    event: vscode.ConfigurationChangeEvent,
    client: LanguageClient,
) {
    if (event.affectsConfiguration("vsrocq")) {
        sendConfiguration(client);
    }
}
