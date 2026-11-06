import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

// https://vite.dev/config/
export default defineConfig(({ mode }) => ({
    plugins: [react()],
    build: {
        outDir: "build",
        // elkjs, the layout engine, is most of the bundle
        chunkSizeWarningLimit: 2000,
        sourcemap: mode === "development",
        rolldownOptions: {
            output: {
                entryFileNames: `assets/[name].js`,
                chunkFileNames: `assets/[name].js`,
                assetFileNames: `assets/[name].[ext]`,
            },
        },
    },
}));
