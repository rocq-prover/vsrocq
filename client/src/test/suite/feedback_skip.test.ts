import { expect } from "expect";
// You can import and use all API from the 'vscode' module
// as well as import your extension to test it
import * as vscode from "vscode";
import * as common from "./common";

/** Zero-based line of `Check x.`, the last sentence of delegate_proof.v. */
const CHECK_LINE = 6;

suite("Should get diagnostics in the appropriate tab", function () {
    this.timeout(20000);

    let t: common.TestContext;
    setup(() => {
        t = new common.TestContext();
    });
    teardown(() => t.dispose());

    test("Skipping proofs", async () => {
        const ext = vscode.extensions.getExtension("rocq-prover.vsrocq")!;
        await ext.activate();

        await t.configure(["proof", "delegation"], "Skip");
        await t.configure(["proof", "mode"], 1);

        const doc1 = await t.openFixture("delegate_proof.v");

        const doc2 = await t.openFixture("warn.v");

        const [diagnostics1, diagnostics2] = await Promise.all([
            common.waitForDiagnostics(
                doc1,
                common.diagnosticOnLine(CHECK_LINE),
            ),
            common.waitForDiagnostics(doc2, common.anyDiagnostic),
        ]);

        expect(diagnostics1.length).toBe(1);
        expect(diagnostics1[0].message).toMatch(/x\s*:\s*True/);
        expect(diagnostics1[0].severity).toBe(
            vscode.DiagnosticSeverity.Information,
        );

        expect(diagnostics2.length).toBe(1);
        expect(diagnostics2[0].message).toMatch(
            /.*There is no flag or option.*/,
        );
        expect(diagnostics2[0].severity).toBe(
            vscode.DiagnosticSeverity.Warning,
        );
    });
});
