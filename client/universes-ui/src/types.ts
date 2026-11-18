// The universe graphs of the prover/universes request, see
// language-server/protocol/universeGraph.ml

export interface Position {
    line: number;
    character: number;
}

export interface Range {
    start: Position;
    end: Position;
}

export interface Level {
    id: string;
    name: string;
    flexible: boolean;
    algebraic: boolean;
    range?: Range;
}

export type ConstraintKind = "<" | "<=" | "=";

export interface UnivConstraint {
    source: string;
    kind: ConstraintKind;
    target: string;
}

export interface Graph {
    levels: Level[];
    constraints: UnivConstraint[];
}

export interface Elimination {
    from_quality: string;
    to_quality: string;
}

export interface QualityGraph {
    qualities: string[];
    eliminations: Elimination[];
}

export interface UniverseGraph {
    graph: Graph;
    normalized?: Graph;
    qualities?: QualityGraph;
}

// The universes of the proof at the cursor (Show Universes), or the global
// ones (Print Universes)
export type Scope = "proof" | "global";

// From the extension to the webview
export type UniversesMessage =
    | { command: "loading"; scope: Scope; subgraph: string[] }
    | {
          command: "render";
          scope: Scope;
          subgraph: string[];
          data: UniverseGraph;
      }
    | { command: "error"; scope: Scope; subgraph: string[]; message: string };

// From the webview to the extension
export type UniversesWebviewMessage =
    | { command: "ready" }
    | { command: "reveal"; range: Range }
    | { command: "setScope"; scope: Scope }
    | { command: "setSubgraph"; subgraph: string[] };
