import {
    TextEditor
} from 'vscode';

import Client from './client';
import { makeVersionedDocumentId } from './utilities/utils';
import { WithRequestId } from './protocol/types';

export const sendInterpretToPoint = async (editor: TextEditor, client: Client) => {
    const textDocument = makeVersionedDocumentId(editor);
    const position = editor.selection.active;
    const response = await client.sendRequest<WithRequestId>("prover/interpretToPoint", {textDocument: textDocument, position: position });
    return response.request_id;
};

export const sendInterpretToEnd = async (editor: TextEditor,  client: Client) => {
    const textDocument = makeVersionedDocumentId(editor);
    const response = await client.sendRequest<WithRequestId>("prover/interpretToEnd", {textDocument: textDocument});
    return response.request_id;
};

export const sendStepForward = async (editor: TextEditor,  client: Client) => {
    const textDocument = makeVersionedDocumentId(editor);
    const response = await client.sendRequest<WithRequestId>("prover/stepForward", {textDocument: textDocument});
    return response.request_id;
};

export const sendStepBackward = async (editor: TextEditor,  client: Client) => {
    const textDocument = makeVersionedDocumentId(editor);
    const response = await client.sendRequest<WithRequestId>("prover/stepBackward", {textDocument: textDocument});
    return response.request_id;
};

