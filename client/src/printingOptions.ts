import { TextEditor, window } from "vscode";
import { RequestType, TextDocumentIdentifier } from "vscode-languageclient";

import Client from "./client";
import {
    PrintingOptionsRequest,
    PrintingOptionsResponse,
    ResetPrintingOptionsRequest,
    SetPrintingOptionRequest,
} from "./protocol/types";
import { makeVersionedDocumentId } from "./utilities/utils";

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

// Sets the Printing flag [name] to [value], asking the user for a flag whose
// value at the cursor is not [value] when [name] is not given. The setting
// only applies to the document of [editor].
export const sendSetPrintingOption = async (
    editor: TextEditor,
    client: Client,
    value: boolean,
    name?: string,
) => {
    const textDocument = TextDocumentIdentifier.create(
        editor.document.uri.toString(),
    );
    try {
        if (name !== undefined) {
            await client.sendRequest(setPrintingOptionReq, {
                textDocument,
                name,
                value,
            });
            return;
        }
        const { options } = await client.sendRequest(printingOptionsReq, {
            textDocument: makeVersionedDocumentId(editor),
            position: editor.selection.active,
        });
        const items = options
            .filter((option) => option.value !== value)
            .map((option) => ({
                label: option.name,
                description: option.overridden ? "(set by user)" : undefined,
            }));
        if (items.length === 0) {
            window.showInformationMessage(
                `All printing flags are already ${value ? "set" : "unset"}.`,
            );
            return;
        }
        const pick = await window.showQuickPick(items, {
            placeHolder: `Printing flag to ${value ? "set" : "unset"}`,
        });
        if (!pick) {
            return;
        }
        await client.sendRequest(setPrintingOptionReq, {
            textDocument,
            name: pick.label,
            value,
        });
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
