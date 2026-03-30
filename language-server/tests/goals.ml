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

open Base
open Dm
open Common
open Protocol
open LspWrapper
open Yojson.Safe.Util

let%test_unit "goals: encoding after replay from top" =
  let st = dm_init_and_parse_test_doc () ~text:"Lemma foo : forall x y, x + y = y + x." in
  let st, (_s1, ()) = dm_parse st (P O) in
  let exec_events = DocumentManager.interpret_to_next Settings.Mode.Manual in
  let todo = Sel.Todo.(add empty exec_events) in
  let st = handle_dm_events todo st in
  let exec_events = DocumentManager.interpret_to_previous Settings.Mode.Manual in
  let todo = Sel.Todo.(add empty exec_events) in
  let st = handle_dm_events todo st in
  let exec_events = DocumentManager.interpret_to_next Settings.Mode.Manual in
  let todo = Sel.Todo.(add empty exec_events) in
  let st = handle_dm_events todo st in
  let proof = Stdlib.Option.get (DocumentManager.get_proof st Protocol.Settings.Goals.Diff.Mode.Off None ~showOnlyPropHypotheses:false) in
  let messages = DocumentManager.get_messages st (Option.value_exn @@ DocumentManager.Internal.observe_id st) in
  (*added bogus values for the other code path (getting everything as strings)*)
  let _json = Protocol.ExtProtocol.Notification.Server.ProofViewParams.yojson_of_t { proof = Some proof; messages; pp_proof = None; pp_messages = []; range = Range.top() } in
  ()

let%test_unit "goals: proof is available after error" =
  let st = dm_init_and_parse_test_doc () ~text:"Lemma foo : False. easy." in
  let st, (_s1, (_s2, ())) = dm_parse st (P (P O)) in
  let exec_events = DocumentManager.interpret_to_end Settings.Mode.Manual in
  let todo = Sel.Todo.(add empty exec_events) in
  let st = handle_dm_events todo st in
  let proof = DocumentManager.get_proof st Protocol.Settings.Goals.Diff.Mode.Off None ~showOnlyPropHypotheses:false in
  [%test_eq: bool] true (Option.is_some proof)

let%test_unit "goals: prop filtering excludes non-prop hypotheses" =
  (* n : nat has sort Set; H : n = 0 has sort Prop *)
  let st = dm_init_and_parse_test_doc () ~text:"Lemma foo (n : nat) (H : n = 0) : n = 0." in
  let st, (_s1, ()) = dm_parse st (P O) in
  let exec_events = DocumentManager.interpret_to_next Settings.Mode.Manual in
  let todo = Sel.Todo.(add empty exec_events) in
  let st = handle_dm_events todo st in
  let proof_all =
    Stdlib.Option.get
      (DocumentManager.get_proof st Protocol.Settings.Goals.Diff.Mode.Off None
         ~showOnlyPropHypotheses:false) in
  let all_hyps_count =
    proof_all |> Protocol.ProofState.yojson_of_t |> member "goals" |> to_list
      |> List.hd_exn|> member "hypotheses" |> to_list |> List.length in
  let proof_filtered =
    Stdlib.Option.get
      (DocumentManager.get_proof st Protocol.Settings.Goals.Diff.Mode.Off None
         ~showOnlyPropHypotheses:true) in
  let filtered_hyps_count =
    proof_filtered |> Protocol.ProofState.yojson_of_t |> member "goals" |> to_list
      |> List.hd_exn|> member "hypotheses" |> to_list |> List.length in
  [%test_eq: int] 2 all_hyps_count;
  [%test_eq: int] 1 filtered_hyps_count
