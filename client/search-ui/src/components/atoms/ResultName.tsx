import { FunctionComponent } from "react";

import { PpDisplay, PpString } from "pp-display";

import classes from "./ResultName.module.css";

type ResultNameProps = {
    name: PpString;
};

const resultName: FunctionComponent<ResultNameProps> = (props) => {
    const { name } = props;

    return <PpDisplay pp={name} rocqCss={classes} maxDepth={17} />;
};

export default resultName;
