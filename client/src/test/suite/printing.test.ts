import { expect } from "expect";
import * as vscode from "vscode";
import * as common from "./common";

/** The text of the hovers at [position], joined. */
async function hoverText(
    uri: vscode.Uri,
    position: vscode.Position,
): Promise<string> {
    const hovers = await vscode.commands.executeCommand<vscode.Hover[]>(
        "vscode.executeHoverProvider",
        uri,
        position,
    );
    return hovers
        .flatMap((h) => h.contents)
        .map((c) => (typeof c === "string" ? c : c.value))
        .join("\n");
}

/**
 * Polls the hover at [position] until it satisfies [predicate], and returns
 * it. Hovers are empty until the sentence before [position] is checked, and
 * text editor commands are not awaited by `executeCommand`, so a hover read
 * right after setting a flag may still be the old one.
 */
async function waitForHover(
    uri: vscode.Uri,
    position: vscode.Position,
    predicate: (text: string) => boolean,
    timeoutMs = 10000,
): Promise<string> {
    const deadline = Date.now() + timeoutMs;
    let text = "";
    while (Date.now() < deadline) {
        text = await hoverText(uri, position);
        if (predicate(text)) {
            return text;
        }
        await new Promise((resolve) => setTimeout(resolve, 100));
    }
    throw new Error(
        `Timed out after ${timeoutMs}ms waiting on the hover; last seen: ${JSON.stringify(text)}`,
    );
}

suite("Printing flags", function () {
    this.timeout(30000);

    let t: common.TestContext;
    setup(() => {
        t = new common.TestContext();
    });
    // Flags are set per document, and every test opens fresh copies.
    teardown(() => t.dispose());

    test("Printing All applies to hovers on checked sentences", async () => {
        const ext = vscode.extensions.getExtension("rocq-prover.vsrocq")!;
        await ext.activate();
        await t.configure(["proof", "mode"], 1);

        const doc = await t.openFixture("printing.v");
        // [two] in "Check two."
        const position = new vscode.Position(2, 7);

        const before = await waitForHover(doc, position, (s) =>
            s.includes("two"),
        );
        expect(before).toContain("1 + 1 = 2");

        await vscode.commands.executeCommand(
            "extension.rocq.printing.set",
            "Printing All",
        );
        const all = await waitForHover(doc, position, (s) =>
            s.includes("@eq"),
        );
        expect(all).not.toContain("1 + 1 = 2");

        await vscode.commands.executeCommand("extension.rocq.printing.reset");
        await waitForHover(doc, position, (s) => s.includes("1 + 1 = 2"));
    });

    test("Rocq: Reset checks the document with the flags set", async () => {
        const ext = vscode.extensions.getExtension("rocq-prover.vsrocq")!;
        await ext.activate();
        await t.configure(["proof", "mode"], 1);

        const doc = await t.openFixture("printing.v");
        // The output of "Check two." is reported as a diagnostic.
        const checkOutput = (pattern: string) =>
            common.waitForDiagnostics(doc, (ds) =>
                ds.some((d) => d.message.includes(pattern)),
            );
        await checkOutput("1 + 1 = 2");

        await vscode.commands.executeCommand(
            "extension.rocq.printing.set",
            "Printing All",
        );
        // Wait for the server to have the flag before resetting.
        await waitForHover(doc, new vscode.Position(2, 7), (s) =>
            s.includes("@eq"),
        );
        await vscode.commands.executeCommand("extension.rocq.reset");
        await checkOutput("@eq nat");

        // The document now runs with the flag, as if it set it itself, so
        // going back to its own flags takes another reset.
        await vscode.commands.executeCommand("extension.rocq.printing.reset");
        await vscode.commands.executeCommand("extension.rocq.reset");
        await checkOutput("1 + 1 = 2");
        await waitForHover(doc, new vscode.Position(2, 7), (s) =>
            s.includes("1 + 1 = 2"),
        );
    });

    test("Flags are set per document", async () => {
        const ext = vscode.extensions.getExtension("rocq-prover.vsrocq")!;
        await ext.activate();
        await t.configure(["proof", "mode"], 1);

        const other = await t.openFixture("printing.v");
        // Opened last, so it is the active editor the command applies to.
        const doc = await t.openFixture("printing.v");
        const position = new vscode.Position(2, 7);
        await waitForHover(other, position, (s) => s.includes("1 + 1 = 2"));
        await waitForHover(doc, position, (s) => s.includes("1 + 1 = 2"));

        await vscode.commands.executeCommand(
            "extension.rocq.printing.set",
            "Printing All",
        );
        await waitForHover(doc, position, (s) => s.includes("@eq"));
        expect(await hoverText(other, position)).toContain("1 + 1 = 2");
    });

    test("Rejects an unknown flag", async () => {
        const ext = vscode.extensions.getExtension("rocq-prover.vsrocq")!;
        await ext.activate();
        await t.configure(["proof", "mode"], 1);

        const doc = await t.openFixture("printing.v");
        const position = new vscode.Position(2, 7);
        await waitForHover(doc, position, (s) => s.includes("1 + 1 = 2"));

        await vscode.commands.executeCommand(
            "extension.rocq.printing.set",
            "Printing Nonsense",
        );
        // Give a wrongly accepted flag time to reach the server.
        await new Promise((resolve) => setTimeout(resolve, 500));
        expect(await hoverText(doc, position)).toContain("1 + 1 = 2");
    });
});
