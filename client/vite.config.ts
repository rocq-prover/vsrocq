import { resolve } from "node:path";
import { defineConfig } from "vite";

export default defineConfig(({ mode }) => ({
    resolve: {
        mainFields: ["module", "main"],
        conditions: ["node"],
    },
    build: {
        target: "node22",
        outDir: "dist",
        sourcemap: mode === "development",
        lib: {
            entry: resolve(import.meta.dirname, "src/extension.ts"),
            formats: ["cjs"],
            fileName: "extension",
        },
        rolldownOptions: {
            external: [
                "vscode",
                /^node:.*/,
                "path",
                "fs",
                "child_process",
                "net",
                "crypto",
                "os",
                "util",
            ],
            output: {
                sourcemapExcludeSources: true,
            },
        },
    },
}));
