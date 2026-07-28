open Lsp.Types

type entries

(** Computes the shared folding and document-symbol entry tree. *)
val entries : Document.document -> entries

(** Projects entries into LSP folding ranges. *)
val folding_ranges : entries -> FoldingRange.t list

(** Projects entries into LSP document symbols. *)
val document_symbols : entries -> DocumentSymbol.t list
