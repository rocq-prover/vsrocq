import { PpString } from "pp-display";

import { Goal, Hypothesis } from "../types";

type LegacyHypothesis = PpString;
type BackCompatHypothesis = Hypothesis | LegacyHypothesis;

type BackCompatGoal = Omit<Goal, "hypotheses"> & {
    hypotheses: BackCompatHypothesis[];
};

type BackCompatProofPayload = {
    goals: BackCompatGoal[];
    shelvedGoals: BackCompatGoal[];
    givenUpGoals: BackCompatGoal[];
    unfocusedGoals: BackCompatGoal[];
};

type ProofPayload = {
    goals: Goal[];
    shelvedGoals: Goal[];
    givenUpGoals: Goal[];
    unfocusedGoals: Goal[];
};

const isStructuredHypothesis = (
    hypothesis: BackCompatHypothesis,
): hypothesis is Hypothesis => {
    return !Array.isArray(hypothesis) && "_type" in hypothesis;
};

const normalizeHypothesis = (hypothesis: BackCompatHypothesis): Hypothesis => {
    if (isStructuredHypothesis(hypothesis)) {
        return hypothesis;
    }

    return {
        ids: [],
        body: null,
        _type: hypothesis,
        universe: "",
    };
};

const normalizeGoal = (goal: BackCompatGoal): Goal => {
    return {
        ...goal,
        hypotheses: goal.hypotheses.map(normalizeHypothesis),
    };
};

export const normalizeProofPayload = (
    proof: BackCompatProofPayload | null,
): ProofPayload | null => {
    if (proof === null) {
        return null;
    }

    return {
        goals: proof.goals.map(normalizeGoal),
        shelvedGoals: proof.shelvedGoals.map(normalizeGoal),
        givenUpGoals: proof.givenUpGoals.map(normalizeGoal),
        unfocusedGoals: proof.unfocusedGoals.map(normalizeGoal),
    };
};

export const isVisibleWithPropFilter = (hypothesis: Hypothesis) => {
    // Legacy hypotheses have no universe metadata; keep them visible under the filter.
    return (
        hypothesis.universe === "" ||
        hypothesis.universe === "Prop" ||
        hypothesis.universe === "SProp"
    );
};
