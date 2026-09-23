import { expect } from "expect";
import * as vscode from "vscode";

// runTest.ts starts this suite with vsrocq.path pointing to a file that does
// not exist, so the extension activates without a language server.
suite("Without a language server", function () {
    this.timeout(30000);

    suiteSetup(async () => {
        await vscode.extensions.getExtension("rocq-prover.vsrocq")!.activate();
    });

    for (const command of [
        "extension.rocq.walkthrough",
        "extension.rocq.showSetup",
        "extension.rocq.showLog",
    ]) {
        test(`${command} is registered`, async () => {
            const registered = await vscode.commands.getCommands(true);
            expect(registered).toContain(command);
            await vscode.commands.executeCommand(command);
        });
    }
});
