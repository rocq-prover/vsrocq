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

open Types
open Document
open Lsp.Types

type settings = {
  block_on_first_error : bool;
  check_mode : Protocol.Settings.Mode.t;
  diff_mode : Protocol.Settings.Goals.Diff.Mode.t;
  pp_mode : Protocol.Settings.Goals.PrettyPrint.t;
  point_interp_mode:Protocol.Settings.PointInterpretationMode.t;
}

val set_options : settings -> unit

type event

val pp_event : Format.formatter -> event -> unit

type state

val init : feedback_pipe:feedback_pipe -> Vernacstate.t -> state
val reset : state -> Vernacstate.t -> feedback_pipe:feedback_pipe -> state

val reset_to_top : state -> state
(** [reset_to_top state] updates the state to make the observe_id Top *)

val interrupt_execution : state -> unit

val get_observe_id : state -> sentence_id option
val reset_overview : state -> document -> sentence_id option -> state
val overview : state -> exec_overview

val shift_overview :
  state -> before:document -> after:document -> start:int -> offset:int -> state

val executed_ranges :
  document -> state -> exec_overview

val observe_id_range : document -> state -> Range.t option
val interpret_to_end : unit -> event Sel.Event.t list
val interpret_to_next : unit -> event Sel.Event.t list
val interpret_to_previous : unit -> event Sel.Event.t list

val interpret_to_position :
  Position.t ->
  event Sel.Event.t list

val interpret_in_background :
  document ->
  state ->
  state * event Sel.Event.t list

val invalidate : state -> sentence_id -> state
val validate_document : document -> state -> state * event Sel.Event.t list
val vernac_state_of_sentence : document -> sentence_id -> Vernacstate.t option

val get_proof :
  document ->
  state ->
  sentence_id option ->
  Protocol.ProofState.t option

val get_messages :
  document ->
  sentence_id ->
  (DiagnosticSeverity.t * Protocol.Printing.pp) list

val handle_event :
  uri:Lsp.Uri.t ->
  document ->
  state ->
  event ->
  document_updates * (state, event) handled_event

module Internal : sig
  val is_remotely_executed : state -> sentence_id -> bool
end
