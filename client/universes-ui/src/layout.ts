import ELK, { ElkNode } from "elkjs/lib/elk.bundled.js";

import { Graph, Level, QualityGraph, Range } from "./types";

const elk = new ELK();

export interface Point {
    x: number;
    y: number;
}

export interface LayoutNode {
    id: string;
    label: string;
    // the levels of the node, several when they are equal
    levels: Level[];
    flexible: boolean;
    algebraic: boolean;
    range?: Range;
    x: number;
    y: number;
    width: number;
    height: number;
}

export interface LayoutEdge {
    id: string;
    source: string;
    target: string;
    strict: boolean;
    points: Point[];
}

export interface Layout {
    nodes: LayoutNode[];
    edges: LayoutEdge[];
    width: number;
    height: number;
}

interface Node {
    id: string;
    label: string;
    levels: Level[];
}

interface Edge {
    source: string;
    target: string;
    strict: boolean;
}

const nodeHeight = 26;
const nodePadding = 12;

let canvas: HTMLCanvasElement | undefined;

const textWidth = (text: string) => {
    canvas = canvas ?? document.createElement("canvas");
    const context = canvas.getContext("2d");
    if (!context) {
        return text.length * 8;
    }
    context.font = getComputedStyle(document.body).font;
    return context.measureText(text).width;
};

// Equal levels are shown as one node: the classes of the equalities
const equalityClasses = (graph: Graph) => {
    const parent = new Map<string, string>();
    const find = (id: string): string => {
        const p = parent.get(id);
        if (p === undefined || p === id) {
            return id;
        }
        const root = find(p);
        parent.set(id, root);
        return root;
    };
    for (const c of graph.constraints) {
        if (c.kind === "=") {
            parent.set(find(c.source), find(c.target));
        }
    }
    return find;
};

// The nodes and edges of a universe graph: < and <= edges between the
// classes of equal levels, a < hiding a <= between the same classes
export const universeGraph = (graph: Graph) => {
    const find = equalityClasses(graph);
    const levels = new Map<string, Level>();
    for (const l of graph.levels) {
        levels.set(l.id, l);
    }
    const nodes = new Map<string, Node>();
    const level = (id: string): Level =>
        levels.get(id) ?? {
            id,
            name: id,
            flexible: false,
            algebraic: false,
        };
    const ids = new Set<string>(levels.keys());
    for (const c of graph.constraints) {
        ids.add(c.source);
        ids.add(c.target);
    }
    for (const id of ids) {
        const root = find(id);
        const node = nodes.get(root) ?? { id: root, label: "", levels: [] };
        node.levels.push(level(id));
        nodes.set(root, node);
    }
    for (const node of nodes.values()) {
        node.label = node.levels.map((l) => l.name).join(" = ");
    }
    const edges = new Map<string, Edge>();
    for (const c of graph.constraints) {
        if (c.kind === "=") {
            continue;
        }
        const source = find(c.source);
        const target = find(c.target);
        if (source === target) {
            continue;
        }
        const key = source + "\u0000" + target;
        const strict = c.kind === "<" || (edges.get(key)?.strict ?? false);
        edges.set(key, { source, target, strict });
    }
    return { nodes: [...nodes.values()], edges: [...edges.values()] };
};

// The nodes and edges of a quality graph, without the eliminations that
// follow from others
export const qualityGraph = (graph: QualityGraph) => {
    const eliminates = new Map<string, Set<string>>();
    for (const q of graph.qualities) {
        eliminates.set(q, new Set());
    }
    for (const e of graph.eliminations) {
        eliminates.get(e.from_quality)?.add(e.to_quality);
    }
    const edges: Edge[] = [];
    for (const e of graph.eliminations) {
        const implied = graph.qualities.some(
            (q) =>
                q !== e.from_quality &&
                q !== e.to_quality &&
                eliminates.get(e.from_quality)?.has(q) &&
                eliminates.get(q)?.has(e.to_quality),
        );
        if (!implied) {
            edges.push({
                source: e.from_quality,
                target: e.to_quality,
                strict: true,
            });
        }
    }
    const nodes = graph.qualities.map((q) => ({
        id: q,
        label: q,
        levels: [],
    }));
    return { nodes, edges };
};

// A layered layout of the graph, edges going up (or down)
export const layout = async (
    graph: { nodes: Node[]; edges: Edge[] },
    direction: "UP" | "DOWN",
): Promise<Layout> => {
    const root: ElkNode = {
        id: "root",
        layoutOptions: {
            "elk.algorithm": "layered",
            "elk.direction": direction,
            "elk.edgeRouting": "POLYLINE",
            "elk.layered.spacing.nodeNodeBetweenLayers": "40",
            "elk.spacing.nodeNode": "20",
        },
        children: graph.nodes.map((n) => ({
            id: n.id,
            width: textWidth(n.label) + 2 * nodePadding,
            height: nodeHeight,
        })),
        edges: graph.edges.map((e, i) => ({
            id: "e" + i,
            sources: [e.source],
            targets: [e.target],
        })),
    };
    const result = await elk.layout(root);
    const positions = new Map<string, ElkNode>();
    for (const n of result.children ?? []) {
        positions.set(n.id, n);
    }
    const nodes = graph.nodes.map((n) => {
        const p = positions.get(n.id);
        return {
            ...n,
            flexible: n.levels.some((l) => l.flexible),
            algebraic: n.levels.some((l) => l.algebraic),
            range: n.levels.find((l) => l.range)?.range,
            x: p?.x ?? 0,
            y: p?.y ?? 0,
            width: p?.width ?? 0,
            height: p?.height ?? 0,
        };
    });
    const edges = (result.edges ?? []).map((e, i) => {
        const points = (e.sections ?? []).flatMap((s) => [
            s.startPoint,
            ...(s.bendPoints ?? []),
            s.endPoint,
        ]);
        return { ...graph.edges[i], id: e.id, points };
    });
    return {
        nodes,
        edges,
        width: result.width ?? 0,
        height: result.height ?? 0,
    };
};
