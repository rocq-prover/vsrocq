import { glob } from "glob";
import Mocha from "mocha";
import * as path from "path";

export async function run(): Promise<void> {
    const mocha = new Mocha({
        ui: "tdd",
        color: true,
    });

    const files = await glob("**/*.test.js", { cwd: __dirname });

    files.forEach((f) => mocha.addFile(path.resolve(__dirname, f)));

    return new Promise((resolve, reject) => {
        mocha.run((failures) => {
            if (failures > 0) {
                reject(new Error(`${failures} tests failed.`));
            } else {
                resolve();
            }
        });
    });
}
