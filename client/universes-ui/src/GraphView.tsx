import { useEffect, useMemo, useRef, useState } from "react";

import { Layout, LayoutNode, Point } from "./layout";
import { Range } from "./types";

interface Transform {
    x: number;
    y: number;
    k: number;
}

interface Props {
    layout: Layout;
    // the nodes whose label contains it are highlighted
    filter: string;
    onReveal: (range: Range) => void;
}

const margin = 20;

const path = (points: Point[]) =>
    points.map((p, i) => (i === 0 ? "M" : "L") + p.x + " " + p.y).join(" ");

// The transform showing the whole layout in a view of the given size
const fit = (layout: Layout, width: number, height: number): Transform => {
    const k = Math.min(
        (width - 2 * margin) / Math.max(layout.width, 1),
        (height - 2 * margin) / Math.max(layout.height, 1),
        1.5,
    );
    return {
        k,
        x: (width - layout.width * k) / 2,
        y: (height - layout.height * k) / 2,
    };
};

const graphView = ({ layout, filter, onReveal }: Props) => {
    const svg = useRef<SVGSVGElement>(null);
    const [transform, setTransform] = useState<Transform>({ x: 0, y: 0, k: 1 });
    const [selected, setSelected] = useState<string | null>(null);
    const drag = useRef<{ start: Point; transform: Transform } | null>(null);

    const fitToView = () => {
        const rect = svg.current?.getBoundingClientRect();
        if (rect) {
            setTransform(fit(layout, rect.width, rect.height));
        }
    };

    useEffect(() => {
        fitToView();
        setSelected((s) => (layout.nodes.some((n) => n.id === s) ? s : null));
    }, [layout]);

    // The selected node and its neighbours
    const neighbours = useMemo(() => {
        if (!selected) {
            return null;
        }
        const ids = new Set([selected]);
        for (const e of layout.edges) {
            if (e.source === selected) {
                ids.add(e.target);
            }
            if (e.target === selected) {
                ids.add(e.source);
            }
        }
        return ids;
    }, [selected, layout]);

    const matches = (node: LayoutNode) =>
        filter !== "" &&
        node.label.toLowerCase().includes(filter.toLowerCase());

    const onWheel = (e: React.WheelEvent) => {
        const rect = svg.current?.getBoundingClientRect();
        if (!rect) {
            return;
        }
        const px = e.clientX - rect.left;
        const py = e.clientY - rect.top;
        setTransform((t) => {
            const k = Math.min(
                Math.max(t.k * Math.exp(-e.deltaY / 500), 0.05),
                5,
            );
            return {
                k,
                x: px - ((px - t.x) * k) / t.k,
                y: py - ((py - t.y) * k) / t.k,
            };
        });
    };

    const onMouseDown = (e: React.MouseEvent) => {
        drag.current = { start: { x: e.clientX, y: e.clientY }, transform };
    };

    const onMouseMove = (e: React.MouseEvent) => {
        const d = drag.current;
        if (d) {
            setTransform({
                ...d.transform,
                x: d.transform.x + e.clientX - d.start.x,
                y: d.transform.y + e.clientY - d.start.y,
            });
        }
    };

    const onMouseUp = (e: React.MouseEvent) => {
        const d = drag.current;
        drag.current = null;
        // a click on the background clears the selection
        if (d && d.start.x === e.clientX && d.start.y === e.clientY) {
            setSelected(null);
        }
    };

    const dimmed = (...ids: string[]) =>
        neighbours !== null && !ids.every((id) => neighbours.has(id));

    return (
        <div className="graph">
            <svg
                ref={svg}
                className="graph-canvas"
                onWheel={onWheel}
                onMouseDown={onMouseDown}
                onMouseMove={onMouseMove}
                onMouseUp={onMouseUp}
                onMouseLeave={() => (drag.current = null)}
            >
                <defs>
                    <marker
                        id="arrow"
                        viewBox="0 0 10 10"
                        refX="10"
                        refY="5"
                        markerWidth="7"
                        markerHeight="7"
                        orient="auto-start-reverse"
                    >
                        <path d="M 0 0 L 10 5 L 0 10 z" className="arrow" />
                    </marker>
                </defs>
                <g
                    transform={`translate(${transform.x} ${transform.y}) scale(${transform.k})`}
                >
                    {layout.edges.map((e) => (
                        <path
                            key={e.id}
                            d={path(e.points)}
                            className={
                                "edge" +
                                (e.strict ? "" : " edge-large") +
                                (dimmed(e.source, e.target) ? " dimmed" : "")
                            }
                            markerEnd="url(#arrow)"
                        />
                    ))}
                    {layout.nodes.map((n) => (
                        <g
                            key={n.id}
                            transform={`translate(${n.x} ${n.y})`}
                            className={
                                "node" +
                                (n.flexible ? " node-flexible" : "") +
                                (n.algebraic ? " node-algebraic" : "") +
                                (n.range ? " node-located" : "") +
                                (n.id === selected ? " node-selected" : "") +
                                (matches(n) ? " node-match" : "") +
                                (dimmed(n.id) ? " dimmed" : "")
                            }
                            onMouseDown={(e) => e.stopPropagation()}
                            onMouseUp={(e) => e.stopPropagation()}
                            onClick={() => {
                                setSelected(n.id === selected ? null : n.id);
                                if (n.range) {
                                    onReveal(n.range);
                                }
                            }}
                        >
                            <title>
                                {n.levels
                                    .map(
                                        (l) =>
                                            l.name +
                                            (l.name !== l.id
                                                ? ` (${l.id})`
                                                : "") +
                                            (l.flexible ? ", flexible" : "") +
                                            (l.algebraic ? ", algebraic" : ""),
                                    )
                                    .join("\n")}
                            </title>
                            <rect width={n.width} height={n.height} rx="4" />
                            <text x={n.width / 2} y={n.height / 2}>
                                {n.label}
                            </text>
                        </g>
                    ))}
                </g>
            </svg>
            <div className="graph-controls">
                <button
                    title="Zoom in"
                    onClick={() =>
                        setTransform((t) => ({
                            ...t,
                            k: Math.min(t.k * 1.25, 5),
                        }))
                    }
                >
                    +
                </button>
                <button
                    title="Zoom out"
                    onClick={() =>
                        setTransform((t) => ({
                            ...t,
                            k: Math.max(t.k / 1.25, 0.05),
                        }))
                    }
                >
                    −
                </button>
                <button title="Fit to view" onClick={fitToView}>
                    ⤢
                </button>
            </div>
        </div>
    );
};

export default graphView;
