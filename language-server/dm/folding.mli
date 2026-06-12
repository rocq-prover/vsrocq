open Lsp.Types

(** Computes LSP folding ranges for the parsed Rocq document. *)
val folding_ranges : Document.document -> FoldingRange.t list

(** Computes LSP document symbols using the same internal entry tree as folding
    ranges.  This is not wired into DocumentManager yet. *)
val document_symbols : Document.document -> DocumentSymbol.t list
