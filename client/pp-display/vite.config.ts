import react from "@vitejs/plugin-react";
import { resolve } from "path";
import dts from "unplugin-dts/vite";
import { defineConfig } from "vite";

// https://vite.dev/config/
export default defineConfig({
    plugins: [react(), dts({})],
    build: {
        lib: {
            entry: resolve(import.meta.dirname, "src/main.tsx"),
            formats: ["es"],
        },
        rolldownOptions: {
            external: ["react"],
            output: {
                globals: {
                    react: "React",
                },
            },
        },
    },
});
