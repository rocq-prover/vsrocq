import { FunctionComponent, useState } from "react";

import {
    VSCodeBadge,
    VSCodeButton,
    VSCodePanels,
    VSCodePanelTab,
    VSCodePanelView,
    VSCodeTextField,
} from "@vscode/webview-ui-toolkit/react";

import { VscFilter, VscGear } from "react-icons/vsc";

import {
    HypothesesFilter,
    ProofViewGoals,
    ProofViewGoalsKey,
    ProofViewMessage,
} from "../../types";
import Accordion from "../atoms/Accordion";
import EmptyState from "../atoms/EmptyState";
import Message from "../atoms/Message";
import GoalSection from "../organisms/GoalSection";

import { VscPass, VscWarning } from "react-icons/vsc";
import classes from "./GoalPage.module.css";

type ProofViewPageProps = {
    goals: ProofViewGoals;
    messages: ProofViewMessage[];
    collapseGoalHandler: (id: string, key: ProofViewGoalsKey) => void;
    toggleContextHandler: (id: string, key: ProofViewGoalsKey) => void;
    displaySetting: string;
    maxDepth: number;
    settingsClickHandler: () => void;
    helpMessage: string;
    helpMessageHandler: (message: string) => void;
    hypothesesFilter: HypothesesFilter;
    hypothesesFilterClickHandler: () => void;
    hypothesesFilterRegexHandler: (regex: string) => void;
};

const proofViewPage: FunctionComponent<ProofViewPageProps> = (props) => {
    const {
        goals,
        messages,
        displaySetting,
        collapseGoalHandler,
        maxDepth,
        settingsClickHandler,
        helpMessage,
        helpMessageHandler,
        toggleContextHandler,
        hypothesesFilter,
        hypothesesFilterClickHandler,
        hypothesesFilterRegexHandler,
    } = props;
    const [isFilterRegexVisible, setIsFilterRegexVisible] = useState(false);

    const renderGoals = () => {
        const goalBadge = <VSCodeBadge>{goals!.main.length}</VSCodeBadge>;
        const shelvedBadge = <VSCodeBadge>{goals!.shelved.length}</VSCodeBadge>;
        const givenUpBadge = <VSCodeBadge>{goals!.givenUp.length}</VSCodeBadge>;

        const tabs = [
            <VSCodePanelTab>Main {goalBadge}</VSCodePanelTab>,
            <VSCodePanelTab>Shelved {shelvedBadge}</VSCodePanelTab>,
            <VSCodePanelTab>Given up {givenUpBadge}</VSCodePanelTab>,
        ];

        const views = [
            <VSCodePanelView className={classes.View}>
                <GoalSection
                    key={"goals"}
                    goals={goals!.main}
                    unfocusedGoals={goals!.unfocused}
                    collapseGoalHandler={(id) =>
                        collapseGoalHandler(
                            id,
                            goals!.main.length
                                ? ProofViewGoalsKey.main
                                : ProofViewGoalsKey.unfocused,
                        )
                    }
                    toggleContextHandler={(id) =>
                        toggleContextHandler(
                            id,
                            goals!.main.length
                                ? ProofViewGoalsKey.main
                                : ProofViewGoalsKey.unfocused,
                        )
                    }
                    displaySetting={displaySetting}
                    emptyMessage={
                        goals!.shelved.length
                            ? "There are shelved goals. Try using `Unshelve.`"
                            : goals!.givenUp.length
                              ? "There are some goals you gave up. Go back and solve them, or use `Admitted.`"
                              : goals!.unfocused.length
                                ? "The subproof is complete."
                                : "There are no more subgoals"
                    }
                    emptyIcon={
                        goals!.shelved.length === 0 &&
                        goals!.givenUp.length === 0 ? (
                            <VscPass />
                        ) : (
                            <VscWarning />
                        )
                    }
                    maxDepth={maxDepth}
                    helpMessageHandler={helpMessageHandler}
                    hypothesesFilter={hypothesesFilter}
                />
            </VSCodePanelView>,
            <VSCodePanelView className={classes.View}>
                <GoalSection
                    key="shelved"
                    goals={goals!.shelved}
                    collapseGoalHandler={(id) =>
                        collapseGoalHandler(id, ProofViewGoalsKey.shelved)
                    }
                    toggleContextHandler={(id) =>
                        toggleContextHandler(id, ProofViewGoalsKey.shelved)
                    }
                    displaySetting={displaySetting}
                    emptyMessage="There are no shelved goals"
                    maxDepth={maxDepth}
                    helpMessageHandler={helpMessageHandler}
                    hypothesesFilter={hypothesesFilter}
                />
            </VSCodePanelView>,
            <VSCodePanelView className={classes.View}>
                <GoalSection
                    key="givenup"
                    goals={goals!.givenUp}
                    collapseGoalHandler={(id) =>
                        collapseGoalHandler(id, ProofViewGoalsKey.givenUp)
                    }
                    toggleContextHandler={(id) =>
                        toggleContextHandler(id, ProofViewGoalsKey.givenUp)
                    }
                    displaySetting={displaySetting}
                    emptyMessage="There are no given up goals"
                    maxDepth={maxDepth}
                    helpMessageHandler={helpMessageHandler}
                    hypothesesFilter={hypothesesFilter}
                />
            </VSCodePanelView>,
        ];

        return (
            <VSCodePanels className={classes.View}>
                {tabs}
                {views}
            </VSCodePanels>
        );
    };

    const displayMessages = messages.map((m) => {
        return <Message message={m[1]} severity={m[0]} maxDepth={maxDepth} />;
    });

    const collapsibleGoalsDisplay =
        goals === null ? (
            <EmptyState message="Not in proof mode" />
        ) : (
            renderGoals()
        );

    return (
        <div className={classes.Page}>
            <div className={classes.ButtonContainer}>
                <div className={classes.HelpMessage}>{helpMessage}</div>
                <div className={classes.ButtonGroup}>
                    <VSCodeButton
                        appearance={"icon"}
                        onClick={hypothesesFilterClickHandler}
                        onMouseOver={() => {
                            helpMessageHandler(
                                hypothesesFilter.enabled
                                    ? "Disable universe name filter and show all hypotheses."
                                    : "Filter hypotheses by universe name regex.",
                            );
                        }}
                        onMouseOut={() => {
                            helpMessageHandler("");
                        }}
                        aria-label="Toggle hypotheses filter by universe name"
                    >
                        <span
                            className={
                                hypothesesFilter.enabled
                                    ? classes.filterActive
                                    : undefined
                            }
                        >
                            <VscFilter />
                        </span>
                    </VSCodeButton>
                    <VSCodeButton
                        appearance={"icon"}
                        onClick={() =>
                            setIsFilterRegexVisible(!isFilterRegexVisible)
                        }
                        onMouseOver={() => {
                            helpMessageHandler(
                                "Show or hide the hypothesis universe name filter regex.",
                            );
                        }}
                        onMouseOut={() => {
                            helpMessageHandler("");
                        }}
                        aria-label="Configure hypotheses universe name filter regex"
                    >
                        <span className={classes.RegexButton}>.*</span>
                    </VSCodeButton>
                    {isFilterRegexVisible ? (
                        <VSCodeTextField
                            className={classes.RegexInput}
                            value={hypothesesFilter.regex}
                            placeholder="Hypothesis universe name filter regex"
                            onInput={(event: any) =>
                                hypothesesFilterRegexHandler(event.target.value)
                            }
                        />
                    ) : null}
                    <VSCodeButton
                        appearance={"icon"}
                        onClick={settingsClickHandler}
                        onMouseOver={() => {
                            helpMessageHandler(
                                "Open proof view panel settings.",
                            );
                        }}
                        onMouseOut={() => {
                            helpMessageHandler("");
                        }}
                        aria-label="Settings"
                    >
                        <VscGear />
                    </VSCodeButton>
                </div>
            </div>
            <Accordion title={"Proof"} collapsed={false}>
                {collapsibleGoalsDisplay}
            </Accordion>
            <Accordion title="Messages" collapsed={false}>
                <div className={classes.Panel}>{displayMessages}</div>
            </Accordion>
        </div>
    );
};

export default proofViewPage;
