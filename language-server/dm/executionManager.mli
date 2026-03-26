(**************************************************************************)
(*                                                                        *)
(*                                 VSRocq                                 *)
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
open Protocol

(** The event manager is in charge of the actual event of tasks (as
    defined by the scheduler), caching event states and invalidating
    them. It can delegate to worker processes via DelegationManager *)

type delegation_mode =
  | CheckProofsInMaster
  | SkipProofs
  | DelegateProofsToWorkers of { number_of_workers : int }

type options = {
  delegation_mode : delegation_mode;
  completion_options : Settings.Completion.t;
  enableDiagnostics : bool;
}

val is_diagnostics_enabled: unit -> bool

(** Execution state, includes the cache *)
type state
type event
type events = event Sel.Event.t list
type errored_sentence = (sentence_id * Loc.t option) option

val pr_event : event -> Pp.t
val init : Vernacstate.t -> feedback_pipe:feedback_pipe -> state
val destroy : state -> unit

val get_options : unit -> options
val set_options : options -> unit
val set_default_options : unit -> unit
val invalidate : state -> sentence_id -> state

(* val error : state -> sentence_id -> (Loc.t option * Pp.t) option
val all_errors : state -> (sentence_id * (Loc.t option * Pp.t * Quickfix.t list option)) list *)

(* val reset_overview : state -> Document.document -> state
val shift_overview : state -> before:RawDocument.t -> after:RawDocument.t -> start:int -> offset:int -> state *)
(* val shift_diagnostics_locs : state -> start:int -> offset:int -> state *)
(* val executed_ids : state -> sentence_id list *)

(** we know if it worked but we do not have the state in this process *)
val is_remotely_executed : state -> sentence_id -> bool

val get_initial_vernac_state : state -> Vernacstate.t

(* * Returns the vernac state after the sentence
val get_vernac_state : state -> sentence_id -> Vernacstate.t option *)

(** Events for the main loop *)
val handle_event : Document.document -> event -> state -> sentence_id option * (sentence_id * sentence_checking_result) option * state option * events

(** Execution happens in two steps. In particular the event one takes only
    one task at a time to ease checking for interruption *)
type prepared_task
val get_id_of_executed_task : prepared_task -> sentence_id
val build_tasks_for : Document.document -> Scheduler.schedule -> state -> sentence_id -> Vernacstate.t * prepared_task list * state * errored_sentence
val execute : state -> Document.document -> Vernacstate.t * events * bool -> prepared_task -> 
  ((sentence_id * sentence_checking_result) list * state * Vernacstate.t * events * errored_sentence) Sel.Promise.t
val interrupt_rocq_interpreter : unit -> unit

val view_task : prepared_task -> [
  `Local of sentence_id |
  `Remote of sentence_id * sentence_id * sentence_id * sentence_id
]

(** Rocq toplevels for delegation without fork *)
module ProofWorkerProcess : sig
  type options
[%%if rocq = "8.18" || rocq = "8.19" || rocq = "8.20"]
   val parse_options : string list -> options * string list
[%%else]
   val parse_options : Coqargs.t -> string list -> options * string list
[%%endif]
  val main : st:Vernacstate.t -> options -> unit
  val log : ?force:bool -> (unit -> string) -> unit
end
