import { FunctionComponent, KeyboardEventHandler } from "react";

import { printForm, printForms } from "../../printForms";
import Dropdown from "./Dropdown";
import SearchField from "./SearchField";

import classes from "./QueryBar.module.css";

type QueryBarProps = {
    tabInput: {
        pattern: string;
        type: string;
        printForm?: string;
    };
    focus?: string;
    queryTypeSelectHandler: (e: any) => void;
    printFormSelectHandler: (e: any) => void;
    onTextInput: (e: any) => void; //FormEventHandler<HTMLInputElement>
    searchFieldKeyPressHandler: KeyboardEventHandler<HTMLInputElement>;
};

const queryBar: FunctionComponent<QueryBarProps> = (props) => {
    const {
        tabInput,
        focus,
        queryTypeSelectHandler,
        printFormSelectHandler,
        onTextInput,
        searchFieldKeyPressHandler,
    } = props;

    const { pattern, type } = tabInput;
    const form = type === "print" ? printForm(tabInput.printForm) : null;

    return (
        <div className={classes.QueryBar}>
            <Dropdown
                classes={[classes.Dropdown]}
                selectedValue={type}
                options={["search", "check", "about", "locate", "print"]}
                optionLabels={["Search", "Check", "About", "Locate", "Print"]}
                onChange={queryTypeSelectHandler}
            />
            {form && (
                <Dropdown
                    classes={[classes.Dropdown]}
                    selectedValue={form.label}
                    options={printForms.map((f) => f.label)}
                    optionLabels={printForms.map((f) => f.label)}
                    onChange={printFormSelectHandler}
                />
            )}
            {form?.argument !== "none" && (
                <SearchField
                    value={pattern}
                    placeholder={form ? form.placeholder : undefined}
                    focus={focus}
                    onTextInput={onTextInput}
                    onKeyDown={searchFieldKeyPressHandler}
                />
            )}
        </div>
    );
};

export default queryBar;
