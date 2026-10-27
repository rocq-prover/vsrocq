import {
    commands,
    QuickPickItem,
    TextEditor,
    ThemeIcon,
    ViewColumn,
    window,
} from "vscode";
import { RequestType, TextDocumentIdentifier } from "vscode-languageclient";

import Client from "./client";
import {
    PrintingOptionsRequest,
    PrintingOptionsResponse,
    ResetPrintingOptionsRequest,
    SetPrintingOptionRequest,
} from "./protocol/types";
import { makeVersionedDocumentId } from "./utilities/utils";
import { getRocqdocBaseUrl } from "./utilities/versioning";

const printingOptionsReq = new RequestType<
    PrintingOptionsRequest,
    PrintingOptionsResponse,
    void
>("prover/printingOptions");

const setPrintingOptionReq = new RequestType<
    SetPrintingOptionRequest,
    void,
    void
>("prover/setPrintingOption");

const resetPrintingOptionsReq = new RequestType<
    ResetPrintingOptionsRequest,
    void,
    void
>("prover/resetPrintingOptions");

// The links to the documentation of each flag in the option index of the
// manual at [baseUrl], by flag name. Only manuals using the rocq: anchors are
// supported, and an empty map is cached when the index cannot be fetched.
const flagDocCache = new Map<string, Promise<Map<string, string>>>();

const fetchFlagDocs = async (baseUrl: string) => {
    const docs = new Map<string, string>();
    try {
        const response = await fetch(baseUrl + "rocq-optindex.html", {
            signal: AbortSignal.timeout(3000),
        });
        if (!response.ok) {
            return docs;
        }
        const index = await response.text();
        for (const [, href, id] of index.matchAll(
            /href="([^"#]*#rocq:flag\.([^"]*))"/g,
        )) {
            docs.set(id.replace(/-/g, " "), baseUrl + href);
        }
    } catch {
        // Offline, or no such manual: no flag gets a link.
    }
    return docs;
};

const getFlagDocs = (rocqVersion: string) => {
    const baseUrl = getRocqdocBaseUrl(rocqVersion);
    let docs = flagDocCache.get(baseUrl);
    if (docs === undefined) {
        docs = fetchFlagDocs(baseUrl);
        flagDocCache.set(baseUrl, docs);
    }
    return docs;
};

interface FlagItem extends QuickPickItem {
    name: string;
    value: boolean;
    doc?: string;
}

const sendSet = (
    editor: TextEditor,
    client: Client,
    name: string,
    value: boolean,
) =>
    client.sendRequest(setPrintingOptionReq, {
        textDocument: TextDocumentIdentifier.create(
            editor.document.uri.toString(),
        ),
        name,
        value,
    });

// Toggles the Printing flag [name] from its value at the cursor, in the
// document of [editor].
export const sendTogglePrintingOption = async (
    editor: TextEditor,
    client: Client,
    name: string,
) => {
    try {
        const { options } = await client.sendRequest(printingOptionsReq, {
            textDocument: makeVersionedDocumentId(editor),
            position: editor.selection.active,
        });
        const option = options.find((option) => option.name === name);
        if (option === undefined) {
            window.showErrorMessage(`Unknown Printing flag: ${name}`);
            return;
        }
        await sendSet(editor, client, name, !option.value);
    } catch (err: any) {
        window.showErrorMessage(err?.message ?? String(err));
    }
};

// Lets the user check the Printing flags to set at the cursor, then sets or
// unsets the flags whose state they changed. The setting only applies to the
// document of [editor].
export const sendChoosePrintingOptions = async (
    editor: TextEditor,
    client: Client,
    rocqVersion: string,
) => {
    try {
        const [{ options }, docs] = await Promise.all([
            client.sendRequest(printingOptionsReq, {
                textDocument: makeVersionedDocumentId(editor),
                position: editor.selection.active,
            }),
            getFlagDocs(rocqVersion),
        ]);
        const docButton = {
            iconPath: new ThemeIcon("book"),
            tooltip: "Open the documentation of this flag",
        };
        const items: FlagItem[] = options.map((option) => {
            const doc = docs.get(option.name);
            return {
                // Every flag starts with "Printing", which the placeholder
                // already says, so only show the rest of the name.
                label: option.name.replace(/^Printing /, ""),
                name: option.name,
                value: option.value,
                doc,
                description: option.overridden ? "(set by user)" : undefined,
                buttons: doc ? [docButton] : [],
            };
        });

        const quickPick = window.createQuickPick<FlagItem>();
        quickPick.canSelectMany = true;
        quickPick.placeholder = "Printing flags to set";
        // Opening the documentation must not close the picker.
        quickPick.ignoreFocusOut = true;
        quickPick.items = items;
        quickPick.selectedItems = items.filter((item) => item.value);
        quickPick.onDidTriggerItemButton(({ item }) => {
            commands.executeCommand("simpleBrowser.show", item.doc, {
                viewColumn: ViewColumn.Beside,
                preserveFocus: true,
            });
        });
        const picks = await new Promise<readonly FlagItem[] | undefined>(
            (resolve) => {
                quickPick.onDidAccept(() => {
                    resolve(quickPick.selectedItems);
                    quickPick.hide();
                });
                quickPick.onDidHide(() => resolve(undefined));
                quickPick.show();
            },
        );
        quickPick.dispose();
        if (!picks) {
            return;
        }

        const checked = new Set(picks.map((pick) => pick.name));
        for (const item of items) {
            const value = checked.has(item.name);
            if (value !== item.value) {
                await sendSet(editor, client, item.name, value);
            }
        }
    } catch (err: any) {
        window.showErrorMessage(err?.message ?? String(err));
    }
};

export const sendResetPrintingOptions = async (
    editor: TextEditor,
    client: Client,
) => {
    const textDocument = TextDocumentIdentifier.create(
        editor.document.uri.toString(),
    );
    try {
        await client.sendRequest(resetPrintingOptionsReq, { textDocument });
    } catch (err: any) {
        window.showErrorMessage(err?.message ?? String(err));
    }
};
