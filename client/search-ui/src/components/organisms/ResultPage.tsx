import { FunctionComponent, KeyboardEventHandler } from "react";

import { QueryTab } from "../../types";

import Error from "../atoms/Error";
import QueryBar from "../molecules/QueryBar";
import ResultSection from "./ResultSection";

type ResultPageProps = {
    tab: QueryTab;
    queryTypeSelectHandler: (e: any) => void;
    printFormSelectHandler: (e: any) => void;
    onTextInput: (e: any) => void; //FormEventHandler<HTMLInputElement>
    searchFieldKeyPressHandler: KeyboardEventHandler<HTMLInputElement>;
    toggleCollapsedHandler: (index: number) => void;
    deleteSearchResultHandler: (index: number) => void;
    copyNameHandler: (name: string) => void;
};

const page: FunctionComponent<ResultPageProps> = (props) => {
    const {
        tab,
        queryTypeSelectHandler,
        printFormSelectHandler,
        onTextInput,
        searchFieldKeyPressHandler,
        toggleCollapsedHandler,
        deleteSearchResultHandler,
        copyNameHandler,
    } = props;

    const { pattern, error, result, type, printForm, focus } = tab;

    const errorSection = error ? <Error error={error} /> : null;

    return (
        <div>
            <QueryBar
                tabInput={{
                    pattern,
                    type,
                    printForm,
                }}
                focus={focus}
                queryTypeSelectHandler={queryTypeSelectHandler}
                printFormSelectHandler={printFormSelectHandler}
                onTextInput={onTextInput}
                searchFieldKeyPressHandler={searchFieldKeyPressHandler}
            />
            {errorSection}
            <ResultSection
                result={result}
                toggleCollapsedHandler={toggleCollapsedHandler}
                deleteSearchResultHandler={deleteSearchResultHandler}
                copyNameHandler={copyNameHandler}
            />
        </div>
    );
};

export default page;
