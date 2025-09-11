import { window, ExtensionContext } from "vscode";
import { compareVersions } from "compare-versions";
import Client from "../client";

export const getRocqdocUrl = (rocqVersion: string) => {
    if(compareVersions(rocqVersion, "8.18.0") >= 0 && compareVersions(rocqVersion, "9.0.0") < 0) {
        return (`https://rocq.inria.fr/doc/V${rocqVersion}/refman/index.html`);
    }
    return "https://rocq.inria.fr/doc/master/refman/index.html";
};

export const checkVersion = (client: Client, context: ExtensionContext) => {
    const extensionVersion = context.extension.packageJSON.version;
    const initializeResult = client.initializeResult;
    if(initializeResult !== undefined) {
        const serverInfo = client.initializeResult?.serverInfo;
        if(serverInfo !== undefined) {
            const {name, version} = serverInfo;
            Client.writeToVsrocqChannel("[Versioning] Intialized server " + name + " [" + version + "]");
            if(!checkCompat(extensionVersion, version)) {
                window.showErrorMessage('This version of VsRocq requires version ' + versionRequirements[extensionVersion] + ' of ' + name + '. Found version: ' + version + '. Please upgrade the language server.');
            }
        } else {
            Client.writeToVsrocqChannel("Could not run compatibility tests: failed to get serverInfo");
        }  
    } else {
        Client.writeToVsrocqChannel("Could not run compatibility tests: failed to receive initializeResult");
    }

};

type VersionReq = {
    [index: string]: string
};

/*  Version requirements for the client. Syntax is client version : minimum server version */
const versionRequirements : VersionReq = {
    '2.0.0': '2.0.0', 
    '2.0.1': '2.0.0', 
    '2.0.2': '2.0.0', 
    '2.0.3': '2.0.3',
    '2.1.0': '2.0.3',
    '2.1.1': '2.1.1',
    '2.1.2': '2.1.2',
    '2.1.3': '2.1.3',
    '2.1.5': '2.1.5',
    '2.1.6': '2.1.5',
    '2.1.7': '2.1.7',
    '2.2.0': '2.1.7',
    '2.2.1': '2.2.1',
    '2.2.2': '2.2.2',
    '2.2.3': '2.2.2',
    '2.2.4': '2.2.4',
    '2.2.5': '2.2.5',
    '2.2.6': '2.2.6',
    '2.3.0': '2.3.0'
};

//We will add version ranges as we start releasing
const checkCompat = (clientVersion: string, serverVersion: string|undefined) => {
    if(serverVersion !== undefined) {
        return compareVersions(serverVersion, versionRequirements[clientVersion]) >= 0;
    }
    return false;
};