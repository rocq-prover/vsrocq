import { FunctionComponent } from "react";

import Hypothesis from "../atoms/Hypothesis";

import { useHypothesesFilter } from "../../contexts/HypothesesFilterContext";
import { Hypothesis as HypothesisType } from "../../types";
import { isVisibleWithHypothesesFilter } from "../../utilities/proofViewCompat";
import classes from "./HypothesesBlock.module.css";

type HypothesesBlockProps = {
    hypotheses: HypothesisType[];
    maxDepth: number;
};

const hypothesesBlock: FunctionComponent<HypothesesBlockProps> = (props) => {
    const { hypotheses, maxDepth } = props;
    const hypothesesFilter = useHypothesesFilter();
    let filterRegex: RegExp | null = null;
    let hasInvalidRegex = false;

    if (hypothesesFilter.enabled) {
        try {
            filterRegex = new RegExp(hypothesesFilter.regex);
        } catch (_) {
            hasInvalidRegex = true;
        }
    }

    const visibleHypotheses =
        filterRegex === null
            ? hypotheses
            : hypotheses.filter((hyp) =>
                  isVisibleWithHypothesesFilter(hyp, filterRegex),
              );
    const hiddenCount = hypotheses.length - visibleHypotheses.length;

    const hypothesesComponents = visibleHypotheses.map((hyp, index) => {
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
    const hiddenMessage = hasInvalidRegex ? (
        <li className={classes.FilterMessage}>
            Invalid hypothesis universe name filter regex; showing all
            hypotheses.
        </li>
    ) : hiddenCount > 0 ? (
        <li className={classes.FilterMessage}>
            {hiddenCount}{" "}
            {hiddenCount === 1 ? "hypothesis is" : "hypotheses are"} hidden by
            universe name filter.
        </li>
    ) : null;

    return (
        <ul className={classes.Block}>
            {hiddenMessage}
            {hypothesesComponents}
        </ul>
    );
};

export default hypothesesBlock;
