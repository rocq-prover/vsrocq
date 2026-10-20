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

open Dm

(* Regression test: a job that allocates past [memory_limit] must be aborted
   with an error rather than growing without bound (see vsrocq.memory.limit).
   The limit is expressed in kiB by [ProverThread.set_options]. *)

let baseline_kib () =
  let { Gc.heap_words; _ } = Gc.stat () in
  Sys.word_size * heap_words / 1024

let%test_unit "proverThread: memory limit aborts a job" =
  let margin_kib = 100 * 1024 (* 100 MiB *) in
  ProverThread.set_options ~preempt:false ~memory_limit:(baseline_kib () + margin_kib);
  let outcome =
    ProverThread.run ~doc_id:0 ~name:"memory-limit-test" (fun () ->
        (* ~200 MiB on 64-bit, comfortably above the margin. *)
        let big = Array.make 25_000_000 0 in
        Array.length big)
  in
  (* Restore the default (disabled) limit so other tests are unaffected. *)
  ProverThread.set_options ~preempt:false ~memory_limit:(-1);
  match outcome with
  | Ok _ -> failwith "expected the job to be aborted by the memory limit"
  | Error _ -> ()
