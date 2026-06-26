import { PpString } from "pp-display";
type Nullable<T> = T | null;

export interface Goal {
    id: string;
    name?: Nullable<string>;
    goal: PpString;
    hypotheses: Hypothesis[];
}

export interface Hypothesis {
    ids: string[];
    body?: Nullable<PpString>;
    _type: PpString;
    universe: string;
}

export type HypothesesFilter = {
    enabled: boolean;
    regex: string;
};

export interface CollapsibleGoal extends Goal {
    isOpen: boolean;
    isContextHidden: boolean;
}

export type ProofViewGoalsType = {
    main: CollapsibleGoal[];
    shelved: CollapsibleGoal[];
    givenUp: CollapsibleGoal[];
    unfocused: CollapsibleGoal[];
};

export enum ProofViewGoalsKey {
    main = "main",
    shelved = "shelved",
    givenUp = "givenUp",
    unfocused = "unfocused",
}

export enum MessageSeverity {
    error = 1,
    warning,
    information,
    hint,
}

export type ProofViewMessage = [MessageSeverity, PpString];

export type GoalArray = Goal[];

export type GoalArrayOrNull = Nullable<Goal[]>;

export type ProofViewGoals = Nullable<ProofViewGoalsType>;

export type VSCodeMessage =
    | {
          command: "openGoalSettings";
      }
    | {
          command: "toggleHypothesesFilter";
      }
    | {
          command: "updateHypothesesFilterRegex";
          regex: string;
      }
    | {
          command: "pollGoals";
      };
