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

(**

  The thunks passed to the API below must install a Rocq state with
  Vernacstate.* and then perform their work. In other words they should be
  real closures, independent from the Rocq context they are fired in.

*)

val eventually_run :
  doc_id:Types.document_id ->
  (unit -> 'a) ->
  'a Types.interruptible_result Sel.Promise.t
(** [eventually_run ~doc_id thunk] puts the [thunk] in the and promises to execute
    it eventually *)

val run :
  doc_id:Types.document_id ->
  timeout:float ->
  (unit -> 'a) ->
  'a Types.interruptible_result
(** [run ~doc_id ~timeout thunk] interrupts any running thunk, then runs [thunk] with
    [timeout]. The interrupted thunk, if any, will eventually be re-run *)

(* val try_run :
  doc_id:Types.document_id ->
  timeout:float ->
  (unit -> 'a) ->
  'a Types.interruptible_result
 [try_run ~doc_id ~timeout thunk] runs [thunk] with [timeout] if no other thunk
    is running. *)

val interrupt : doc_id:Types.document_id -> unit
(** [interrupt ~doc_id] interrupts the runnign thunk only if it runs for [~doc_id] *)

