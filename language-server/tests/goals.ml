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

let%test_unit "goals: encoding after replay from top" =
  let st = dm_init_and_parse_test_doc () ~text:"Lemma foo : forall x y, x + y = y + x." in
  let st, (_s1, ()) = dm_parse st (P O) in
  let exec_events = DocumentManager.interpret_to_next () in
  let todo = Sel.Todo.(add empty exec_events) in
  let st = handle_dm_events todo st in
  let exec_events = DocumentManager.interpret_to_previous () in
  let todo = Sel.Todo.(add empty exec_events) in
  let st = handle_dm_events todo st in
  let exec_events = DocumentManager.interpret_to_next () in
  let todo = Sel.Todo.(add empty exec_events) in
  let st = handle_dm_events todo st in
  let proof = Stdlib.Option.get (DocumentManager.Internal.get_proof st None) in
  let messages = DocumentManager.get_messages st (Option.value_exn @@ DocumentManager.Internal.observe_id st) in
  (*added bogus values for the other code path (getting everything as strings)*)
  let _json = Protocol.ExtProtocol.Notification.Server.ProofViewParams.yojson_of_t { proof = Some proof; messages; pp_proof = None; pp_messages = []; range = Range.top() } in
  ()

let%test_unit "goals: proof is available after error" =
  let st = dm_init_and_parse_test_doc () ~text:"Lemma foo : False. easy." in
  let st, (_s1, (_s2, ())) = dm_parse st (P (P O)) in
  let exec_events = DocumentManager.interpret_to_end () in
  let todo = Sel.Todo.(add empty exec_events) in
  let st = handle_dm_events todo st in
  let proof = DocumentManager.Internal.get_proof st None in
  [%test_eq: bool] true (Option.is_some proof)

let%test_unit "goals: hypotheses are listed oldest-first" =
  let open Stdlib.Option in
  let st = dm_init_and_parse_test_doc ()
    ~text:"Lemma foo (hyp_b: bool) (hyp_n: nat) : True." in
  let st, _ = dm_parse st (P O) in
  let exec_events = DocumentManager.interpret_to_end () in
  let todo = Sel.Todo.(add empty exec_events) in
  let st = handle_dm_events todo st in
  let doc = DocumentManager.Internal.document st in
  let sentence = get (Document.get_sentence doc (get (DocumentManager.Internal.observe_id st))) in
  let vstate = get (Utilities.get_vernac_state sentence.checked) in

  let pp_proof = get (Protocol.PpProofState.get_proof vstate) in
  let pp_names = let open Protocol.PpProofState in
    pp_proof.goals
    |> List.concat_map ~f:(fun g -> g.hypotheses)
    |> List.concat_map ~f:(fun h -> h.ids) in
  [%test_eq: string list] [ "hyp_b"; "hyp_n" ] pp_names;

  let proof = get (Protocol.ProofState.get_proof
                     ~previous:None Protocol.Settings.Goals.Diff.Mode.Off vstate) in
  let dump = Yojson.Safe.to_string (Protocol.ProofState.yojson_of_t proof) in
  let idx pattern = String.substr_index_exn dump ~pattern in
  [%test_eq: bool] true (idx "\"hyp_b\"" < idx "\"hyp_n\"")
