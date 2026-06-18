import { FunctionComponent } from "react";

import GoalComponent from "../atoms/Goal";
import Separator from "../atoms/Separator";
import HypothesesBlock from "./HypothesesBlock";

import { Goal } from "../../types";
import classes from "./GoalBlock.module.css";

type GoalBlockProps = {
    goal: Goal;
    goalIndicator?: string;
    maxDepth: number;
    helpMessageHandler: (message: string) => void;
    displayHyps: boolean;
    showOnlyPropHypotheses: boolean;
};

const goalBlock: FunctionComponent<GoalBlockProps> = (props) => {
    const {
        goal,
        goalIndicator,
        maxDepth,
        displayHyps,
        helpMessageHandler,
        showOnlyPropHypotheses,
    } = props;
    const indicator = goalIndicator ? (
        <span className={classes.GoalIndex}>({goalIndicator})</span>
    ) : null;
    const hyps = displayHyps ? (
        <HypothesesBlock
            hypotheses={goal.hypotheses}
            maxDepth={maxDepth}
            showOnlyPropHypotheses={showOnlyPropHypotheses}
        />
    ) : null;

    return (
        <div className={classes.Block}>
            {hyps}
            <div className={classes.SeparatorZone}>
                {indicator}
                <Separator />
            </div>
            <GoalComponent
                goal={goal.goal}
                maxDepth={maxDepth}
                setHelpMessage={helpMessageHandler}
            />
        </div>
    );
};

export default goalBlock;
