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

(** if [~preempt] is [false] the [run] and [try_run] APIs enqueue the job rather
    than forcibly interrupting any running job *)
val set_options : preempt:bool -> unit

(**

  The thunks passed to the API below must install a Rocq state with
  Vernacstate.* and then perform their work. In other words they should be
  real closures, independent from the Rocq context they are fired in.

*)

val eventually_run :
  doc_id:Types.document_id ->
  name:string ->
  (unit -> 'a) ->
  'a Types.interruptible_result Sel.Promise.t
(** [eventually_run ~doc_id thunk] puts the [thunk] in the and promises
    to execute it eventually *)

val try_run :
  doc_id:Types.document_id ->
  name:string ->
  timeout:float ->
  (unit -> 'a) ->
  'a Types.interruptible_result
(** [run ~doc_id ~timeout thunk] runs [thunk] and waits
    [timeout] seconds. *)

val run :
  doc_id:Types.document_id ->
  name:string ->
  (unit -> 'a) ->
  ('a,Pp.t) Result.t
(** [run ~doc_id thunk] runs [thunk] and waits for its completion. *)

val interrupt : doc_id:Types.document_id -> unit
(** [interrupt ~doc_id] interrupts the runnign thunk only if it runs for [~doc_id] *)

