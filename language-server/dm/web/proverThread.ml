(**************************************************************************)
(*                                                                        *)
(*                                 VSRoc                                  *)
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

(* No threads: the thunk runs in the main thread. Rocq polls for
   interruptions via Control.set_interrupt_poll; an interruption is either
   requested from the outside (e.g. a flag in a SharedArrayBuffer set by the
   UI thread) or caused by the timeout of try_run. *)

open Types

let log = Log.mk_log "proverThread"

let set_options ~preempt:_ = ()

let external_interrupt = ref (fun () -> false)
let set_external_interrupt f = external_interrupt := f

let deadline = ref infinity
let timed_out = ref false

let poll () =
  if !external_interrupt () then true
  else if Unix.gettimeofday () > !deadline then (timed_out := true; true)
  else false

let () = Control.set_interrupt_poll (Some poll)

(* The main loop cannot run while the thunk runs *)
let interrupt ~doc_id:_ = ()

let exec ~name ~timeout f =
  log.debug (fun () -> "job begins: " ^ name);
  let saved_deadline = !deadline in
  deadline := min saved_deadline (Unix.gettimeofday () +. timeout);
  timed_out := false;
  let res =
    match f () with
    | x -> Terminated x
    | exception Sys.Break ->
        if !timed_out then Aborted (Pp.str "Rocq timed out") else Interrupted
    | exception e ->
        let e, info = Exninfo.capture e in
        Aborted (CErrors.iprint (e, info)) in
  deadline := saved_deadline;
  log.debug (fun () -> "job ends: " ^ name);
  res

let try_run ~doc_id:_ ~name ~timeout f = exec ~name ~timeout f

let eventually_run ~doc_id:_ ~name f =
  let promise, r = Sel.Promise.make () in
  Sel.Promise.fulfill r (exec ~name ~timeout:infinity f);
  promise

let run ~doc_id:_ ~name f =
  match exec ~name ~timeout:infinity f with
  | Terminated x -> Result.Ok x
  | Aborted pp -> Result.Error pp
  | Interrupted -> Result.Error (Pp.str "The operation was interrupted")
