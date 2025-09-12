import {
    TextEditor
} from 'vscode';

import Client from './client';
import { makeVersionedDocumentId } from './utilities/utils';

export const sendInterpretToPoint = (editor: TextEditor, client: Client) => {
    const textDocument = makeVersionedDocumentId(editor);
    const position = editor.selection.active;
    client.sendNotification("prover/interpretToPoint", {textDocument: textDocument, position: position });
};

export const sendInterpretToEnd = (editor: TextEditor,  client: Client) => {
    const textDocument = makeVersionedDocumentId(editor);
    client.sendNotification("prover/interpretToEnd", {textDocument: textDocument});
};

export const sendStepForward = (editor: TextEditor,  client: Client) => {
    const textDocument = makeVersionedDocumentId(editor);
    client.sendNotification("prover/stepForward", {textDocument: textDocument});
};

export const sendStepBackward = (editor: TextEditor,  client: Client) => {
    const textDocument = makeVersionedDocumentId(editor);
    client.sendNotification("prover/stepBackward", {textDocument: textDocument});
};

