import * as vscode from "vscode";
import { LanguageClient } from "vscode-languageclient/node";
import { NestedScopedConfigs } from "./package-json";

// Indexes into O with the path of keys in P. If the path is invalid, returns never.
type GetDotAccess<O, P extends any[]> = P extends [infer Head, ...infer Tail]
    ? Head extends keyof O
        ? Tail extends []
            ? O[Head]
            : GetDotAccess<O[Head], Tail>
        : never
    : O;

// The type of all valid paths into an object O.
type AllPaths<O> = {
    [K in keyof O & string]:
        | [K]
        | (AllPaths<O[K]> extends infer P
              ? P extends any[]
                  ? [K, ...P]
                  : never
              : never);
}[keyof O & string];

// A type-safe access to configuration options. The passed path is a variadic list of keys into the configuration object.
// The error messages for invalid keys might be hard to read, but they essentially point out which key in the path is invalid.
export function getConfigurationOption<
    P extends AllPaths<NestedScopedConfigs> | [],
>(...path: [...P]): GetDotAccess<NestedScopedConfigs, P> {
    const key = ["vsrocq", ...path].join(".");
    return vscode.workspace.getConfiguration(key) as any;
}

export function sendConfiguration(client: LanguageClient) {
    const config = getConfigurationOption();
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
