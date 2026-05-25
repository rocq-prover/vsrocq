import { FunctionComponent } from "react";

import { PpDisplay, PpString } from "pp-display";
import classes from "./PpString.module.css";

type HypothesisProps = {
    content: PpString;
    maxDepth: number;
};

const hypothesis: FunctionComponent<HypothesisProps> = (props) => {
    const { content, maxDepth } = props;

    return (
        <div className={classes.Hypothesis}>
            <PpDisplay pp={content} rocqCss={classes} maxDepth={maxDepth} />
        </div>
    );
};

export default hypothesis;
