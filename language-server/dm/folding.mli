open Lsp.Types

(** Computes LSP folding ranges for the parsed Rocq document. *)
val folding_ranges : Document.document -> FoldingRange.t list
