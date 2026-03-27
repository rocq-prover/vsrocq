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
val interrupt_rocq_interpreter : unit -> unit

(* TODO: REMOVE *)
val run_rocq_thread :
  (Memprof_limits.Token.t -> 'a) -> 'a Sel.Promise.handler -> unit


val run_rocq : (unit -> 'a) -> 'a Types.interruptible_result Sel.Promise.t
