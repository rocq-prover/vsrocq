import { createContext, useContext } from "react";

import { HypothesesFilter } from "../types";

export const defaultHypothesesFilter: HypothesesFilter = {
    enabled: false,
    regex: "^(Prop|SProp)$",
};

export const HypothesesFilterContext = createContext<HypothesesFilter>(
    defaultHypothesesFilter,
);

export const useHypothesesFilter = () => useContext(HypothesesFilterContext);
