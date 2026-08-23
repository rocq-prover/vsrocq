import * as path from "node:path";

// You can import and use all API from the 'vscode' module
// as well as import your extension to test it
import * as vscode from "vscode";
// import * as myExtension from '../../extension';

export async function openTextFile(file: string): Promise<vscode.Uri> {
    const docUri = vscode.Uri.file(
        path.resolve(__dirname, "../../../testFixture", file),
    );
    const doc = await vscode.workspace.openTextDocument(docUri);
    await vscode.window.showTextDocument(doc, { preview: false });
    return docUri;
}

/**
 * Waits until the diagnostics published for `uri` satisfy `predicate`, and
 * returns them. Rejects after `timeoutMs` instead of continuing with whatever
 * happens to be there.
 *
 * The wait condition and the assertion must be two different statements. The
 * wait is only a synchronisation point — "the server has said something about
 * this document" — and the assertion is what the test is actually about
 * (count, severity, message). A predicate that repeats the assertion makes the
 * test vacuous: it can only be reached by already being true.
 *
 * Known limitation: this cannot establish the *absence* of diagnostics. An
 * empty array is also the state before the server has published anything, so
 * `(d) => d.length === 0` holds from the first instant and asserts nothing.
 * Distinguishing "checked, no errors" from "not checked yet" needs the
 * progress ranges carried by `prover/updateHighlights`, which the extension
 * consumes for its decorations and does not expose through the `vscode` API.
 */
export function waitForDiagnostics(
    uri: vscode.Uri,
    predicate: (diagnostics: readonly vscode.Diagnostic[]) => boolean,
    timeoutMs = 10000,
): Promise<readonly vscode.Diagnostic[]> {
    return new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
            subscription.dispose();
            reject(
                new Error(
                    `Timed out after ${timeoutMs}ms waiting on diagnostics for ` +
                        `${path.basename(uri.fsPath)}; last seen: ` +
                        `${JSON.stringify(vscode.languages.getDiagnostics(uri))}`,
                ),
            );
        }, timeoutMs);

        const check = () => {
            const diagnostics = vscode.languages.getDiagnostics(uri);
            if (!predicate(diagnostics)) {
                return;
            }
            clearTimeout(timer);
            subscription.dispose();
            resolve(diagnostics);
        };

        const subscription = vscode.languages.onDidChangeDiagnostics((e) => {
            if (
                e.uris.some((changed) => changed.toString() === uri.toString())
            ) {
                check();
            }
        });

        // The document may already be checked by the time we subscribe.
        check();
    });
}

/**
 * At least one diagnostic has been published.
 *
 * Only sound as a wait condition for a fixture whose diagnostics can all come
 * from the same sentence. The server publishes the diagnostics of the whole
 * document after every executed sentence, so for a fixture that fails in more
 * than one place this predicate is satisfied by a mid-check reading and the
 * test goes on to assert against a partial document. Use `diagnosticOnLine`
 * there instead.
 */
export function anyDiagnostic(
    diagnostics: readonly vscode.Diagnostic[],
): boolean {
    return diagnostics.length > 0;
}

/**
 * At least one diagnostic starts on `line` (zero-based).
 *
 * Point this at the last sentence of the fixture to get a terminal condition:
 * a diagnostic reported there means checking has reached the end of the
 * document, so the reading that follows is the final one rather than one of
 * the intermediate publications.
 *
 * This stays a synchronisation point and not the assertion: it fixes *where*
 * the server must have spoken, while the test still asserts *what* it said.
 */
export function diagnosticOnLine(
    line: number,
): (diagnostics: readonly vscode.Diagnostic[]) => boolean {
    return (diagnostics) =>
        diagnostics.some((d) => d.range.start.line === line);
}
