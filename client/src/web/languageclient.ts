// vscode-languageclient/node for the web build of the extension (see
// vite.config.web.ts, which substitutes this module): the server runs in a
// Web Worker, which takes the place of the ServerOptions.
import {
    LanguageClient as BrowserLanguageClient,
    LanguageClientOptions,
} from "vscode-languageclient/browser";

export * from "vscode-languageclient/browser";

export type ServerOptions = Worker;

export class LanguageClient extends BrowserLanguageClient {
    constructor(
        id: string,
        name: string,
        serverOptions: ServerOptions,
        clientOptions: LanguageClientOptions,
    ) {
        super(id, name, clientOptions, serverOptions);
    }
}
