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

(* One logger per source. [debug] lines print only when the source is
   selected with [-vsrocq-d] or [VSROCQ_ARGS], or before initialization
   when [init] is selected; [info] and [error] lines always print. Until
   the server answers initialize, printed lines are queued and written
   after the response, except [error] lines, which go to stderr at once. *)
type t = {
  debug : (unit -> string) -> unit;
  info : (unit -> string) -> unit;
  error : (unit -> string) -> unit;
}

val mk_log : string -> t
val logs : unit -> string list

type event = string
type events = event Sel.Event.t list

val lsp_initialization_done : unit -> events
val handle_event : event -> unit

val worker_initialization_begins : unit -> unit
val worker_initialization_done : fwd_event:(event -> unit) -> unit

(* debug messages coming from either the language server of Rocq *)
val debug : event Sel.Event.t

[%% if rocq = "8.18" || rocq = "8.19" || rocq = "8.20" ]
val feedback_add_feeder_on_Message : (Feedback.route_id -> Stateid.t -> Feedback.doc_id -> Feedback.level -> Loc.t option -> 'a list -> Pp.t -> unit) -> int
[%%else]
val feedback_add_feeder_on_Message : (Feedback.route_id -> Stateid.t  -> Feedback.doc_id -> Feedback.level -> Loc.t option -> Quickfix.t list -> Pp.t -> unit) -> int
[%%endif]
