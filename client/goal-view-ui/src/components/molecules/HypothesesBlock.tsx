import { FunctionComponent } from "react";

import Hypothesis from "../atoms/Hypothesis";

import { Hypothesis as HypothesisType } from "../../types";
import { isVisibleWithPropFilter } from "../../utilities/proofViewCompat";
import classes from "./HypothesesBlock.module.css";

type HypothesesBlockProps = {
    hypotheses: HypothesisType[];
    maxDepth: number;
    showOnlyPropHypotheses: boolean;
};

const hypothesesBlock: FunctionComponent<HypothesesBlockProps> = (props) => {
    const { hypotheses, maxDepth, showOnlyPropHypotheses } = props;

    const hypothesesComponents = hypotheses
        .filter(
            (hyp) =>
                !showOnlyPropHypotheses || isVisibleWithPropFilter(hyp),
        )
        .map((hyp, index) => {
            return (
                <Hypothesis
                    key={index}
                    ids={hyp.ids}
                    body={hyp.body}
                    type={hyp._type}
                    universe={hyp.universe}
                    maxDepth={maxDepth}
                />
            );
        });

    return <ul className={classes.Block}>{hypothesesComponents}</ul>;
};

export default hypothesesBlock;
