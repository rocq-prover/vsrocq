// The web build of the extension (the "browser" entry of package.json), for
// VS Code for the web: the modules using node are substituted by the ones
// in src/web, and web/bootstrap.js (the script of the server's Web Worker)
// is copied to dist/web.
import { resolve } from "node:path";
import { defineConfig } from "vite";

const src = (f: string) => resolve(import.meta.dirname, "src", f);

export default defineConfig(({ mode }) => ({
    resolve: {
        mainFields: ["browser", "module", "main"],
        conditions: ["browser"],
        alias: [
            { find: /^vscode-languageclient\/node$/, replacement: src("web/languageclient.ts") },
            { find: /^(\.\.?\/)+utilities\/toolchain$/, replacement: src("web/toolchain.ts") },
        ],
    },
    publicDir: resolve(import.meta.dirname, "web"),
    build: {
        target: "es2022",
        outDir: "dist/web",
        sourcemap: mode === "development",
        lib: {
            entry: src("extension.ts"),
            formats: ["cjs"],
            fileName: "extension",
        },
        rolldownOptions: {
            external: ["vscode"],
            output: {
                sourcemapExcludeSources: true,
            },
        },
    },
}));
