import { FunctionComponent } from "react";

import { VscEye, VscEyeClosed } from "react-icons/vsc";

import { CollapsibleGoal, HypothesesFilter } from "../../types";
import Accordion from "../atoms/Accordion";
import GoalBlock from "./GoalBlock";

type CollapsibleGoalBlockProps = {
    goal: CollapsibleGoal;
    collapseHandler: (id: string) => void;
    toggleContextHandler: (id: string) => void;
    goalIndex: number;
    goalIndicator: string;
    maxDepth: number;
    helpMessageHandler: (message: string) => void;
    hypothesesFilter: HypothesesFilter;
};

const collapsibleGoalBlock: FunctionComponent<CollapsibleGoalBlockProps> = (
    props,
) => {
    const {
        goal,
        goalIndex,
        goalIndicator,
        collapseHandler,
        toggleContextHandler,
        maxDepth,
        helpMessageHandler,
        hypothesesFilter,
    } = props;

    const secondaryActionIcon = goal.isContextHidden ? (
        <VscEye />
    ) : (
        <VscEyeClosed />
    );
    const secondaryActionHandler =
        toggleContextHandler !== undefined
            ? () => toggleContextHandler(goal.id)
            : undefined;

    return (
        <Accordion
            title={"Goal " + goalIndex + (goal.name ? `: ${goal.name}` : "")}
            collapsed={!goal.isOpen}
            collapseHandler={() => collapseHandler(goal.id)}
            seconaryActionHandler={secondaryActionHandler}
            seconaryActionIcon={secondaryActionIcon}
        >
            <GoalBlock
                goal={goal}
                goalIndicator={goalIndicator}
                maxDepth={maxDepth}
                helpMessageHandler={helpMessageHandler}
                displayHyps={!goal.isContextHidden}
                hypothesesFilter={hypothesesFilter}
            />
        </Accordion>
    );
};

export default collapsibleGoalBlock;
