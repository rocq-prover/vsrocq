import { ProofViewNotification } from "../protocol/types";

export type McpPromiseBox = {
    promise: Promise<string> | undefined,
    setValue: ((value: string) => void) | undefined,
    currentDocumentURI: string | undefined,
    pendingRequestId: string | undefined
};

export let mcpPromiseBox: McpPromiseBox = {
    promise: undefined,
    setValue: undefined,
    currentDocumentURI: undefined,
    pendingRequestId: undefined
};

export type ProofState = {
    lastProofViewNotification: ProofViewNotification | undefined
};

export let proofState: ProofState = {
    lastProofViewNotification: undefined
};
