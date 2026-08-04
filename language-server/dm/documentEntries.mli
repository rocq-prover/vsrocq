open Lsp.Types
open Protocol

type entries

(** Computes the shared folding and document-symbol entry tree. *)
val entries : Document.document -> entries

(** Projects entries into LSP folding ranges. *)
val folding_ranges : entries -> FoldingRange.t list

(** Projects entries into LSP document symbols. *)
val document_symbols : entries -> DocumentSymbol.t list

(** Projects entries into document proof blocks. *)
val proof_blocks : Document.document -> entries -> ProofState.proof_block list
