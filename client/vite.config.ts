import { resolve } from "node:path";
import { defineConfig } from "vite";

export default defineConfig(({ mode }) => ({
    build: {
        target: "node22",
        outDir: "dist",
        sourcemap: mode === "production" ? false : "inline",
        lib: {
            entry: resolve(import.meta.dirname, "src/extension.ts"),
            formats: ["cjs"],
            fileName: "extension",
        },
        rolldownOptions: {
            external: [
                "vscode",
                /^node:.*/,
                "path", // the `which` package does not use the `node:` prefix
            ],
            output: {
                sourcemapExcludeSources: true,
            },
        },
    },
}));
