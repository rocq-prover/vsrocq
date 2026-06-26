import { PpString, stringOfPpString } from "pp-display";

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

export const isVisibleWithHypothesesFilter = (
    hypothesis: Hypothesis,
    filterRegex: RegExp,
) => {
    // Legacy hypotheses have no universe metadata; match them through their type.
    return (
        filterRegex.test(hypothesis.universe) ||
        filterRegex.test(stringOfPpString(hypothesis._type))
    );
};
