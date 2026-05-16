(**************************************************************************)
(*                                                                        *)
(*                                 VSRocq                                  *)
(*                                                                        *)
(*                   Copyright INRIA and contributors                     *)
(*       (see version control and README file for authors & dates)        *)
(*                                                                        *)
(**************************************************************************)
(*                                                                        *)
(*   This file is distributed under the terms of the MIT License.         *)
(*   See LICENSE file.                                                    *)
(*                                                                        *)
(**************************************************************************)

val check :
  doc_id:int ->
  vs:Vernacstate.t ->
  pattern:string ->
  (Protocol.Printing.pp, Types.error) result

val locate :
  doc_id:int ->
  vs:Vernacstate.t ->
  pattern:string ->
  (Protocol.Printing.pp, Types.error) result

val print :
  doc_id:int ->
  vs:Vernacstate.t ->
  pattern:string ->
  (Protocol.Printing.pp, Types.error) result

val about :
  doc_id:int ->
  vs:Vernacstate.t ->
  pattern:string ->
  (Protocol.Printing.pp, Types.error) result

val search :
  doc_id:int ->
  vs:Vernacstate.t ->
  id:string ->
  string ->
  Protocol.LspWrapper.notification Sel.Event.t list

val hover :
  Document.document ->
  Lsp.Types.Position.t ->
  Lsp.Types.MarkupContent.t option
(** this one is a bit special since it crawls the document *)

val jump_to_definition :
  doc_id:int ->
  vs:Vernacstate.t ->
  string option ->
  (Lsp.Types.Range.t * string) option

val get_completions :
  doc_id:int -> vs:Vernacstate.t -> CompletionItems.completion_item list
