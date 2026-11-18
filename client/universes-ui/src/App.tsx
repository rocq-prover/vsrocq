import { useCallback, useEffect, useState } from "react";

import "./App.css";
import GraphView from "./GraphView";
import { Layout, layout, qualityGraph, universeGraph } from "./layout";
import {
    Range,
    Scope,
    UniverseGraph,
    UniversesMessage,
    UniversesWebviewMessage,
} from "./types";
import { vscode } from "./utilities/vscode";

type View = "universes" | "normalized" | "qualities";

const post = (message: UniversesWebviewMessage) => vscode.postMessage(message);

const app = () => {
    const [scope, setScope] = useState<Scope>("proof");
    const [subgraph, setSubgraph] = useState("");
    const [data, setData] = useState<UniverseGraph | null>(null);
    const [error, setError] = useState<string | null>(null);
    const [loading, setLoading] = useState(false);
    const [view, setView] = useState<View>("universes");
    const [graphLayout, setGraphLayout] = useState<Layout | null>(null);
    const [filter, setFilter] = useState("");

    const handleMessage = useCallback((msg: MessageEvent<UniversesMessage>) => {
        const message = msg.data;
        setScope(message.scope);
        setSubgraph(message.subgraph.join(" "));
        switch (message.command) {
            case "loading":
                setLoading(true);
                break;
            case "render":
                setLoading(false);
                setError(null);
                setData(message.data);
                break;
            case "error":
                setLoading(false);
                setError(message.message);
                setData(null);
                break;
        }
    }, []);

    useEffect(() => {
        window.addEventListener("message", handleMessage);
        post({ command: "ready" });
        return () => window.removeEventListener("message", handleMessage);
    }, [handleMessage]);

    // The views the data has, falling back to the universes
    const views: View[] = data
        ? [
              "universes",
              ...(data.normalized ? ["normalized" as View] : []),
              ...(data.qualities ? ["qualities" as View] : []),
          ]
        : [];
    const currentView = views.includes(view) ? view : "universes";

    useEffect(() => {
        if (!data) {
            setGraphLayout(null);
            return;
        }
        let cancelled = false;
        const graph =
            currentView === "qualities" && data.qualities
                ? layout(qualityGraph(data.qualities), "DOWN")
                : layout(
                      universeGraph(
                          currentView === "normalized" && data.normalized
                              ? data.normalized
                              : data.graph,
                      ),
                      "UP",
                  );
        graph.then(
            (l) => !cancelled && setGraphLayout(l),
            (e) => !cancelled && setError(String(e)),
        );
        return () => {
            cancelled = true;
        };
    }, [data, currentView]);

    const reveal = (range: Range) => post({ command: "reveal", range });

    const viewNames: Record<View, string> = {
        universes: scope === "proof" ? "Constraints" : "Universes",
        normalized: "Normalized",
        qualities: "Sort qualities",
    };

    return (
        <div className="app">
            <div className="toolbar">
                <select
                    value={scope}
                    title="Which universes to show"
                    onChange={(e) =>
                        post({
                            command: "setScope",
                            scope: e.target.value as Scope,
                        })
                    }
                >
                    <option value="proof">Proof (Show Universes)</option>
                    <option value="global">Global (Print Universes)</option>
                </select>
                {views.length > 1 &&
                    views.map((v) => (
                        <button
                            key={v}
                            className={v === currentView ? "selected" : ""}
                            onClick={() => setView(v)}
                        >
                            {viewNames[v]}
                        </button>
                    ))}
                {scope === "global" && (
                    <form
                        className="subgraph"
                        onSubmit={(e) => {
                            e.preventDefault();
                            post({
                                command: "setSubgraph",
                                subgraph: subgraph
                                    .split(/\s+/)
                                    .filter((s) => s !== ""),
                            });
                        }}
                    >
                        <input
                            value={subgraph}
                            placeholder="Subgraph: universes, e.g. Foo.u0 Top.12 (empty for all)"
                            onChange={(e) => setSubgraph(e.target.value)}
                        />
                    </form>
                )}
                <input
                    className="filter"
                    value={filter}
                    placeholder="Highlight"
                    onChange={(e) => setFilter(e.target.value)}
                />
                {graphLayout && (
                    <span className="count">
                        {graphLayout.nodes.length} nodes
                    </span>
                )}
                {loading && <span className="count">Loading…</span>}
            </div>
            {error ? (
                <div className="message">{error}</div>
            ) : graphLayout ? (
                graphLayout.nodes.length === 0 ? (
                    <div className="message">No universes.</div>
                ) : (
                    <GraphView
                        layout={graphLayout}
                        filter={filter}
                        onReveal={reveal}
                    />
                )
            ) : (
                <div className="message">Laying out the graph…</div>
            )}
            {currentView !== "qualities" && (
                <div className="legend">
                    <span>→ &lt;</span>
                    <span className="legend-large">⇢ ≤</span>
                    <span>a = b: equal</span>
                    <span className="legend-flexible">flexible</span>
                    <span className="legend-algebraic">algebraic</span>
                    <span className="legend-located">click: show source</span>
                </div>
            )}
        </div>
    );
};

export default app;
