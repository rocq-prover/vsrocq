import { FunctionComponent } from "react";

import Hypothesis from "../atoms/Hypothesis";

import { Hypothesis as HypothesisType } from "../../types";
import classes from "./HypothesesBlock.module.css";

type HypothesesBlockProps = {
    hypotheses: HypothesisType[];
    maxDepth: number;
    showOnlyPropHypotheses: boolean;
};

const hypothesesBlock: FunctionComponent<HypothesesBlockProps> = (props) => {
    const { hypotheses, maxDepth, showOnlyPropHypotheses } = props;

    const hypothesesComponents = hypotheses
        .filter((hyp) => !showOnlyPropHypotheses || hyp.universe === "Prop")
        .map((hyp, index) => {
            return (
                <Hypothesis
                    key={index}
                    ids={hyp.ids}
                    body={hyp.body}
                    type={hyp._type}
                    maxDepth={maxDepth}
                />
            );
        });

    return <ul className={classes.Block}>{hypothesesComponents}</ul>;
};

export default hypothesesBlock;
