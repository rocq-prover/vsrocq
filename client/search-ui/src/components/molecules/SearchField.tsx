import { VSCodeTextField } from "@vscode/webview-ui-toolkit/react";
import {
    FunctionComponent,
    KeyboardEventHandler,
    useEffect,
    useRef,
    useState,
} from "react";
import { VscSearch } from "react-icons/vsc";

import classes from "./SearchField.module.css";

// Raise issue with microsoft team ?
// There seems to be an issue with the way the onInput handler is
// defined in VSCodeTextField...
// It is of type ((e: Event) => unkown) & FormEventHandler<HTMLInputElement>
// This does not let me type my handler function ChangeEventHandler<HTMLInputElement>
type SearchFieldProps = {
    value: string;
    placeholder?: string;
    // focus the field each time it changes
    focus?: string;
    onTextInput: (e: any) => void; //FormEventHandler<HTMLInputElement>
    onKeyDown: KeyboardEventHandler<HTMLInputElement>;
};

const searchField: FunctionComponent<SearchFieldProps> = (props) => {
    const { value, onTextInput, onKeyDown, focus } = props;
    const wrapper = useRef<HTMLSpanElement>(null);

    // The text field element is kept when the tab changes, so it is focused
    // explicitly rather than with its autofocus attribute
    useEffect(() => {
        if (!focus) {
            return;
        }
        const field =
            wrapper.current?.querySelector<HTMLElement>("vscode-text-field");
        if (!field) {
            return;
        }
        // VS Code may give the focus to the panel after this runs, the
        // field is then focused again when the panel gets it
        const onFocus = () => field.focus();
        const timer = setTimeout(() => {
            field.focus();
            if (!document.hasFocus()) {
                window.addEventListener("focus", onFocus, { once: true });
            }
        }, 0);
        return () => {
            clearTimeout(timer);
            window.removeEventListener("focus", onFocus);
        };
    }, [focus]);
    const label = props.placeholder ?? "Search";

    const [focused, setFocused] = useState(false);
    const placeholder = focused ? label + " (↑↓ for history)" : label;

    return (
        <span ref={wrapper} className={classes.Wrapper}>
            <VSCodeTextField
                className={classes.SearchField}
                placeholder={placeholder}
                value={value}
                onInput={onTextInput}
                onKeyDown={onKeyDown}
                onFocus={() => setFocused(true)}
                onBlur={() => setFocused(false)}
            >
                <span slot="start">
                    <VscSearch />
                </span>
            </VSCodeTextField>
        </span>
    );
};

export default searchField;
