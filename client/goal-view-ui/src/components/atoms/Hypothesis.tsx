import { FunctionComponent } from "react";

import { PpDisplay, PpString } from "pp-display";
import classes from "./PpString.module.css";

type HypothesisProps = {
    ids: string[];
    body?: PpString | null;
    type: PpString;
    universe: string;
    maxDepth: number;
};

const hypothesis: FunctionComponent<HypothesisProps> = (props) => {
    const { ids, body, type, universe, maxDepth } = props;
    const universeClass = (() => {
        switch (universe) {
            case "SProp":
                return classes.IdentifierSProp;
            case "Prop":
                return classes.IdentifierProp;
            case "Set":
                return classes.IdentifierSet;
            default:
                return classes.IdentifierType;
        }
    })();
    const identifierClass = [
        classes.Identifier,
        universeClass,
    ]
        .filter(Boolean)
        .join(" ");
    const names = ids.map((id, index) => (
        <span className={identifierClass} key={id} title={universe}>
            {index === 0 ? id : `, ${id}`}
        </span>
    ));

    return (
        <div className={classes.Hypothesis}>
            {ids.length > 0 ? (
                <span className={classes.IdentifierBlock}>{names}</span>
            ) : null}
            {body ? (
                <>
                    <span className={classes.Separator}>{":="}</span>
                    <span className={classes.Content}>
                        <PpDisplay pp={body} rocqCss={classes} maxDepth={maxDepth} />
                    </span>
                </>
            ) : null}
            {ids.length > 0 || body ? (
                <span className={classes.Separator}>{":"}</span>
            ) : null}
            <span className={classes.Content}>
                <PpDisplay pp={type} rocqCss={classes} maxDepth={maxDepth} />
            </span>
        </div>
    );
};

export default hypothesis;
