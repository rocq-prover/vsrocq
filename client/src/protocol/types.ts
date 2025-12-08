import { integer, TextDocumentIdentifier, VersionedTextDocumentIdentifier } from "vscode-languageclient";
import { Position, Range, Uri } from "vscode";

type Nullable<T> = T | null;

export type PpTag = string;

export enum PpMode {
    horizontal = "Pp_hbox",
    vertical = "Pp_vbox",
    hvBox = "Pp_hvbox",
    hovBox = "Pp_hovbox"
}

export type BlockType =
  | [PpMode.horizontal]
  | [PpMode.vertical, integer]
  | [PpMode.hvBox, integer]
  | [PpMode.hovBox, integer];

export type PpString =
  | ["Ppcmd_empty"]
  | ["Ppcmd_string", string]
  | ["Ppcmd_glue", PpString[]]
  | ["Ppcmd_box", BlockType, PpString]
  | ["Ppcmd_tag", PpTag, PpString]
  | ["Ppcmd_print_break", integer, integer]
  | ["Ppcmd_force_newline"]
  | ["Ppcmd_comment", string[]];

export interface Goal {
    id: integer;
    name: Nullable<string>;
    goal: PpString;
    hypotheses: PpString[];
}

export interface ProofViewGoals {
    goals: Goal[];
    shelvedGoals: Goal[];
    givenUpGoals: Goal[];
    unfocusedGoals: Goal[];
}

export enum MessageSeverity {
    error = "Error",
    warning = "Warning", 
    info = "Information"
}

export type RocqMessage = [MessageSeverity, PpString];

export interface ProofViewNotification {
    proof: Nullable<ProofViewGoals>;
    messages: RocqMessage[];
}

export interface RocqLogMessage {
    message: string;
}

export interface UpdateHighlightsNotification {
    uri: Uri;
    preparedRange: Range[];
    processingRange: Range[];
    processedRange: Range[];
}

export interface MoveCursorNotification {
    uri: Uri; 
    range: Range; 
}

export interface ErrorAlertNotification {
    uri: Uri;
    range: Range;
}

export interface SearchRocqRequest {
    id: string;
    textDocument: VersionedTextDocumentIdentifier;
    pattern: string; 
    position: Position;
}

export interface SearchRocqHandshake {
    id: string;
}

export interface QueryError {
    code: integer; 
    message: string; 
}

export interface SearchRocqResult {
    id: string;
    name: PpString; 
    statement: PpString;
}

export interface AboutRocqRequest {
    textDocument: VersionedTextDocumentIdentifier;
    pattern: string; 
    position: Position;
    goalIndex?: number;
}

export type AboutRocqResponse = PpString;

export interface CheckRocqRequest {
    textDocument: VersionedTextDocumentIdentifier;
    pattern: string; 
    position: Position;
    goalIndex?: number;
};

export type CheckRocqResponse = PpString; 

export interface LocateRocqRequest {
    textDocument: VersionedTextDocumentIdentifier;
    pattern: string; 
    position: Position;
};

export type LocateRocqResponse = PpString; 

export interface PrintRocqRequest {
    textDocument: VersionedTextDocumentIdentifier;
    pattern: string; 
    position: Position;
};

export type PrintRocqResponse = PpString; 

export interface DocumentStateRequest {
    textDocument: TextDocumentIdentifier;
}

export interface DocumentStateResponse {
    document: string;
}

export interface ResetRocqRequest {
    textDocument: TextDocumentIdentifier;
}

export interface ResetRocqResponse {};

export interface DocumentProofsRequest {
    textDocument: TextDocumentIdentifier;
}

type ProofStatement = {
    range: Range;
    statement: string;
}

type ProofStep = {
    range: Range;
    tactic: string;
};

type ProofBlock = {
    statement: ProofStatement;
    range: Range;
    steps: ProofStep[];
};

export interface DocumentProofsResponse {
    proofs: ProofBlock[];
}
