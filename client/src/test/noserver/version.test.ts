import { expect } from "expect";
import { parseRocqVersion } from "../../utilities/toolchain";
import { getRocqdocUrl } from "../../utilities/versioning";

suite("Rocq version", function () {
    test("parses a two-part version", () => {
        const output =
            "The Rocq Prover, version 9.2\ncompiled with OCaml 4.14.2\n";
        expect(parseRocqVersion(output)).toBe("9.2");
    });

    test("parses a three-part version", () => {
        const output =
            "The Rocq Prover, version 9.1.0\ncompiled with OCaml 4.14.0\n";
        expect(parseRocqVersion(output)).toBe("9.1.0");
    });

    test("parses a Coq version", () => {
        const output =
            "The Coq Proof Assistant, version 8.19.0\ncompiled with OCaml 4.14.2\n";
        expect(parseRocqVersion(output)).toBe("8.19.0");
    });

    test("parses development and pre-release versions", () => {
        for (const version of ["9.3+alpha", "9.1+rc1", "8.10+beta1"]) {
            const output = `The Rocq Prover, version ${version}\ncompiled with OCaml 4.14.2\n`;
            expect(parseRocqVersion(output)).toBe(version);
        }
    });

    test("finds no version in unexpected output", () => {
        expect(parseRocqVersion("compiled with OCaml 4.14.2\n")).toBe(
            undefined,
        );
    });

    test("maps versions to their reference manual", () => {
        const doc = (dir: string) =>
            `https://rocq-prover.org/doc/${dir}/refman/index.html`;
        expect(getRocqdocUrl("9.2")).toBe(doc("V9.2.0"));
        expect(getRocqdocUrl("9.1.0")).toBe(doc("V9.1.0"));
        expect(getRocqdocUrl("9.3+alpha")).toBe(doc("master"));
        expect(getRocqdocUrl("9.0.dev")).toBe(doc("master"));
        expect(getRocqdocUrl("9.1+rc1")).toBe(doc("V9.1+rc1"));
        expect(getRocqdocUrl("8.10+beta1")).toBe(doc("V8.10+beta1"));
        expect(getRocqdocUrl("")).toBe(doc("master"));
    });
});
