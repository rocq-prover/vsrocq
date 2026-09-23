import * as fs from "node:fs/promises";
import * as path from "path";
import * as tmp from "tmp-promise";

import { runTests } from "@vscode/test-electron";

async function runSuite(suite: string, vsrocqPath: string) {
    // The folder containing the Extension Manifest package.json
    // Passed to `--extensionDevelopmentPath`
    const extensionDevelopmentPath = path.resolve(__dirname, "../../");

    // The path to test runner
    // Passed to --extensionTestsPath
    const extensionTestsPath = path.resolve(__dirname, suite);

    const storagePath = await tmp.dir();
    const userDataDir = path.join(storagePath.path, "settings");
    const userSettingsPath = path.join(userDataDir, "User");

    const vsrocqArgs = process.env.VSROCQARGS?.split(" ");

    const userSettings = {
        "vsrocq.path": vsrocqPath,
        "vsrocq.args": vsrocqArgs,
        "vsrocq.proof.mode": 1,
        "vsrocq.proof.block": false,
    };

    await fs.mkdir(userSettingsPath, { recursive: true });
    await fs.writeFile(
        path.join(userSettingsPath, "settings.json"),
        JSON.stringify(userSettings),
        "utf-8",
    );

    const launchArgs = [
        path.resolve(__dirname, "../../testFixture"),
        "--disable-extensions",
        "--user-data-dir=" + userDataDir,
    ];

    await runTests({
        extensionDevelopmentPath,
        extensionTestsPath,
        launchArgs,
    });
}

async function main() {
    try {
        const vsrocqPath =
            process.env.VSROCQPATH ||
            path.resolve(
                __dirname,
                "../../../language-server/_build/install/default/bin/vsrocqtop",
            );
        await runSuite("./suite/index", vsrocqPath);

        // A vsrocq.path that does not exist, so the extension activates
        // without a language server.
        const missing = path.join((await tmp.dir()).path, "vsrocqtop");
        await runSuite("./noserver/index", missing);
    } catch (err) {
        console.error("Failed to run tests");
        process.exit(1);
    }
}

main();
