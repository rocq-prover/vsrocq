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
open Bm
open Utils

let%test_unit "goals: encoding after replay from top" =
  let st = dm_init_and_parse_test_doc ~text:"Lemma foo : forall x y, x + y = y + x." in
  let st, (_s1, ()) = dm_parse st (P O) in
  let st, exec_events = Bridge.interpret_to_next st Host.Settings.Mode.Manual in
  let todo = Sel.Todo.(add empty exec_events) in
  let st = handle_dm_events todo st in
  let st, exec_events = Bridge.interpret_to_previous st Host.Settings.Mode.Manual in
  let todo = Sel.Todo.(add empty exec_events) in
  let st = handle_dm_events todo st in
  let st, exec_events = Bridge.interpret_to_next st Host.Settings.Mode.Manual in
  let todo = Sel.Todo.(add empty exec_events) in
  let st = handle_dm_events todo st in
  let proof = Stdlib.Option.get (Bridge.get_proof st Host.Settings.Goals.Diff.Mode.Off None) in
  let messages = Bridge.get_messages st (Option.value_exn @@ Bridge.Internal.observe_id st) in
  let _json = Protocol.ExtProtocol.Notification.Server.ProofViewParams.yojson_of_t { proof = Some proof; messages } in
  ()

let%test_unit "goals: proof is available after error" =
  let st = dm_init_and_parse_test_doc ~text:"Lemma foo : False. easy." in
  let st, (_s1, (_s2, ())) = dm_parse st (P (P O)) in
  let st, exec_events = Bridge.interpret_to_end st Host.Settings.Mode.Manual in
  let todo = Sel.Todo.(add empty exec_events) in
  let st = handle_dm_events todo st in
  let proof = Bridge.get_proof st Host.Settings.Goals.Diff.Mode.Off None in
  [%test_eq: bool] true (Option.is_some proof)