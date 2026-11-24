// The forms of the Print command offered by the query panel, by label: the
// words that follow Print, and whether they take an argument
export type PrintArgument = "none" | "optional" | "required";

export interface PrintForm {
    form: string;
    label: string;
    argument: PrintArgument;
    placeholder?: string;
}

export const printForms: PrintForm[] = [
    { form: "", label: "Name", argument: "required", placeholder: "Name" },
    { form: "Options", label: "Options", argument: "none" },
    { form: "Tables", label: "Tables", argument: "none" },
    { form: "Universes", label: "Universes", argument: "none" },
    {
        form: "Assumptions",
        label: "Assumptions",
        argument: "required",
        placeholder: "Term",
    },
    { form: "Typing Flags", label: "Typing Flags", argument: "none" },
    { form: "Libraries", label: "Libraries", argument: "none" },
    { form: "LoadPath", label: "LoadPath", argument: "none" },
    { form: "Scopes", label: "Scopes", argument: "none" },
    { form: "Coercions", label: "Coercions", argument: "none" },
    { form: "Classes", label: "Classes", argument: "none" },
    { form: "Typeclasses", label: "Typeclasses", argument: "none" },
    {
        form: "Instances",
        label: "Instances",
        argument: "required",
        placeholder: "Typeclass",
    },
    {
        form: "Implicit",
        label: "Implicit",
        argument: "required",
        placeholder: "Term",
    },
    {
        form: "Hint",
        label: "Hint",
        argument: "optional",
        placeholder: "Term (empty for the current goal)",
    },
    {
        form: "HintDb",
        label: "HintDb",
        argument: "required",
        placeholder: "Hint database",
    },
];

export const printForm = (label: string | undefined) =>
    printForms.find((f) => f.label === label) ?? printForms[0];

// The rest of the Print command, e.g. "Assumptions foo"
export const printPattern = (label: string | undefined, argument: string) =>
    [printForm(label).form, argument.trim()].filter((s) => s !== "").join(" ");
