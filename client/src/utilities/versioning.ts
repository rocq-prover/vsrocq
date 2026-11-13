import { compareVersions } from "compare-versions";
import { ExtensionContext, window } from "vscode";
import Client from "../client";
import requirements from "./versionRequirements.json";

// The directory of the reference manual of [rocqVersion]. Releases X.Y are
// published as VX.Y.0, and development versions, or an unknown version, are
// documented in master.
const getRocqdocDir = (rocqVersion: string) => {
    if (/^\d+\.\d+$/.test(rocqVersion)) {
        return `V${rocqVersion}.0`;
    }
    if (/^\d+\.\d+(\.\d+)?(\+rc\d+|\+beta\d*)?$/.test(rocqVersion)) {
        return `V${rocqVersion}`;
    }
    return "master";
};

// The reference manual of [rocqVersion].
export const getRocqdocBaseUrl = (rocqVersion: string) => {
    return `https://rocq-prover.org/doc/${getRocqdocDir(rocqVersion)}/refman/`;
};

export const getRocqdocUrl = (rocqVersion: string) => {
    return getRocqdocBaseUrl(rocqVersion) + "index.html";
};

export const checkVersion = (client: Client, context: ExtensionContext) => {
    const extensionVersion = context.extension.packageJSON.version;
    const initializeResult = client.initializeResult;
    if (initializeResult !== undefined) {
        const serverInfo = client.initializeResult?.serverInfo;
        if (serverInfo !== undefined) {
            const { name, version } = serverInfo;
            Client.writeToVsrocqChannel(
                "[Versioning] Intialized server " + name + " [" + version + "]",
            );
            if (!checkCompat(extensionVersion, version)) {
                window.showErrorMessage(
                    "This version of VsRocq requires version " +
                        versionRequirements[extensionVersion] +
                        " of " +
                        name +
                        ". Found version: " +
                        version +
                        ". Please upgrade the language server.",
                );
            }
        } else {
            Client.writeToVsrocqChannel(
                "Could not run compatibility tests: failed to get serverInfo",
            );
        }
    } else {
        Client.writeToVsrocqChannel(
            "Could not run compatibility tests: failed to receive initializeResult",
        );
    }
};

type VersionReq = {
    [index: string]: string;
};

/*  Version requirements for the client, read from versionRequirements.json.
    Each entry maps a client version to the minimum server version it accepts.
    docs/compatibility.md is generated from the JSON file, so run
    `npm run gen-compat-doc` after changing it. */
const versionRequirements: VersionReq = requirements;

//We will add version ranges as we start releasing
const checkCompat = (
    clientVersion: string,
    serverVersion: string | undefined,
) => {
    if (serverVersion !== undefined) {
        return (
            compareVersions(
                serverVersion,
                versionRequirements[clientVersion],
            ) >= 0
        );
    }
    return false;
};
