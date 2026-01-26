(**************************************************************************)
(*                                                                        *)
(*                                 VSRocq                                  *)
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

[@@@warning "-27"]

(* ============== McpPrinting Tests ============== *)

let%test_unit "mcp.printing.format_interp_result.no_proof" =
  let st, init_events = em_init_test_doc ~text:"Definition x := 1." in
  let events = DocumentManager.interpret_to_end Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  let result = Mcpserver.McpPrinting.format_interp_result st in
  (* Should contain position info and no proof *)
  [%test_pred: string] (String.is_substring ~substring:"Position:") result;
  [%test_pred: string] (String.is_substring ~substring:"No proof in progress") result

let%test_unit "mcp.printing.format_interp_result.with_proof" =
  let st, init_events = em_init_test_doc ~text:"Lemma foo : 1 = 1. Proof." in
  let st, (s1, (s2, ())) = dm_parse st (P(P O)) in
  let events = DocumentManager.interpret_to_end Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  let result = Mcpserver.McpPrinting.format_interp_result st in
  (* Should contain position info and a goal *)
  [%test_pred: string] (String.is_substring ~substring:"Position:") result;
  [%test_pred: string] (String.is_substring ~substring:"goal") result;
  [%test_pred: string] (String.is_substring ~substring:"1 = 1") result

let%test_unit "mcp.printing.format_interp_result.with_hypotheses" =
  let st, init_events = em_init_test_doc ~text:"Lemma foo : forall n : nat, n = n. Proof. intros n." in
  let events = DocumentManager.interpret_to_end Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  let result = Mcpserver.McpPrinting.format_interp_result st in
  (* Should contain hypothesis n : nat *)
  [%test_pred: string] (String.is_substring ~substring:"n") result;
  [%test_pred: string] (String.is_substring ~substring:"nat") result

let%test_unit "mcp.printing.format_interp_result.with_error" =
  let st, init_events = em_init_test_doc ~text:"Definition x := y." in
  let events = DocumentManager.interpret_to_end Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  let result = Mcpserver.McpPrinting.format_interp_result st in
  (* Should contain error about y not found *)
  [%test_pred: string] (String.is_substring ~substring:"Error") result

let%test_unit "mcp.printing.format_interp_result.document_start" =
  let st, _init_events = em_init_test_doc ~text:"Definition x := 1." in
  (* Don't execute anything, stay at document start *)
  let result = Mcpserver.McpPrinting.format_interp_result st in
  [%test_pred: string] (String.is_substring ~substring:"document start") result

let%test_unit "mcp.printing.get_proof_state.no_execution" =
  let st, _init_events = em_init_test_doc ~text:"Lemma foo : 1 = 1." in
  (* Don't execute, should report no proof state available *)
  let result = Mcpserver.McpPrinting.get_proof_state st in
  [%test_pred: string] (String.is_substring ~substring:"No proof state available") result

let%test_unit "mcp.printing.get_proof_state.after_execution" =
  let st, init_events = em_init_test_doc ~text:"Lemma foo : 1 = 1. Proof." in
  let events = DocumentManager.interpret_to_end Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  let result = Mcpserver.McpPrinting.get_proof_state st in
  (* Should show the goal *)
  [%test_pred: string] (String.is_substring ~substring:"1 = 1") result

let%test_unit "mcp.printing.get_messages.at_start" =
  let st, _init_events = em_init_test_doc ~text:"Definition x := 1." in
  let result = Mcpserver.McpPrinting.get_messages st in
  [%test_pred: string] (String.is_substring ~substring:"document start") result

let%test_unit "mcp.printing.get_errors.no_errors" =
  let st, init_events = em_init_test_doc ~text:"Definition x := 1." in
  let events = DocumentManager.interpret_to_end Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  let result = Mcpserver.McpPrinting.get_errors st in
  [%test_pred: string] (String.is_substring ~substring:"No errors") result

let%test_unit "mcp.printing.get_errors.with_errors" =
  let st, init_events = em_init_test_doc ~text:"Definition x := undefined_var." in
  let events = DocumentManager.interpret_to_end Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  let result = Mcpserver.McpPrinting.get_errors st in
  [%test_pred: string] (String.is_substring ~substring:"Error") result

(* ============== MCP Document Operations Tests ============== *)
(* These tests verify the MCP operations work correctly through the DocumentManager layer *)

let%test_unit "mcp.operations.step_forward" =
  let st, init_events = em_init_test_doc ~text:"Definition x := 1. Definition y := 2." in
  let st, (s1, (s2, ())) = dm_parse st (P(P O)) in
  let events = DocumentManager.interpret_to_next Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  (* After stepping forward once, observe_id should be s1 *)
  [%test_pred: sentence_id option] (Option.equal Stateid.equal (Some s1.id)) (DocumentManager.Internal.observe_id st);
  (* The formatted result should show position info *)
  let result = Mcpserver.McpPrinting.format_interp_result st in
  [%test_pred: string] (String.is_substring ~substring:"Position:") result

let%test_unit "mcp.operations.step_backward" =
  let st, init_events = em_init_test_doc ~text:"Definition x := 1. Definition y := 2." in
  let st, (s1, (s2, ())) = dm_parse st (P(P O)) in
  (* First step forward twice *)
  let events = DocumentManager.interpret_to_next Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  let events = DocumentManager.interpret_to_next Settings.Mode.Manual in
  let todo = Sel.Todo.(add todo events) in
  let st = handle_dm_events todo st in
  [%test_pred: sentence_id option] (Option.equal Stateid.equal (Some s2.id)) (DocumentManager.Internal.observe_id st);
  (* Now step backward *)
  let events = DocumentManager.interpret_to_previous Settings.Mode.Manual in
  let todo = Sel.Todo.(add todo events) in
  let st = handle_dm_events todo st in
  [%test_pred: sentence_id option] (Option.equal Stateid.equal (Some s1.id)) (DocumentManager.Internal.observe_id st)

let%test_unit "mcp.operations.interpret_to_end" =
  let st, init_events = em_init_test_doc ~text:"Definition x := 1. Definition y := 2. Definition z := 3." in
  let st, (s1, (s2, (s3, ()))) = dm_parse st (P(P(P O))) in
  let events = DocumentManager.interpret_to_end Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  (* Should be at the last sentence *)
  [%test_pred: sentence_id option] (Option.equal Stateid.equal (Some s3.id)) (DocumentManager.Internal.observe_id st);
  check_no_diag st

let%test_unit "mcp.operations.interpret_to_point" =
  let st, init_events = em_init_test_doc ~text:"Definition x := 1.\nDefinition y := 2.\nDefinition z := 3." in
  let st, (s1, (s2, (s3, ()))) = dm_parse st (P(P(P O))) in
  (* Interpret to a position in the middle of the document (line 1) *)
  let pos = Lsp.Types.Position.create ~line:1 ~character:0 in
  let events = DocumentManager.interpret_to_position pos Settings.Mode.Manual
    ~point_interp_mode:Protocol.Settings.PointInterpretationMode.Cursor in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  (* Should have executed at least s1 *)
  let obs_id = DocumentManager.Internal.observe_id st in
  [%test_pred: sentence_id option] Option.is_some obs_id

let%test_unit "mcp.operations.proof_workflow" =
  (* Test a complete proof workflow: state -> tactic -> Qed *)
  let st, init_events = em_init_test_doc ~text:"Lemma foo : 1 = 1.\nProof.\n  reflexivity.\nQed." in
  let st, (s1, (s2, (s3, (s4, ())))) = dm_parse st (P(P(P(P O)))) in

  (* Execute to end to verify the whole proof works *)
  let events = DocumentManager.interpret_to_end Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in

  (* Should be at the last sentence (Qed) *)
  [%test_pred: sentence_id option] (Option.equal Stateid.equal (Some s4.id)) (DocumentManager.Internal.observe_id st);

  (* After completing Qed, should have no proof in progress *)
  let result = Mcpserver.McpPrinting.get_proof_state st in
  [%test_pred: string] (String.is_substring ~substring:"No proof in progress") result;

  check_no_diag st

let%test_unit "mcp.operations.multiple_goals" =
  (* Test a proof with multiple goals after split *)
  let st, init_events = em_init_test_doc ~text:"Lemma foo : True /\\ True.\nProof.\n  split." in
  let events = DocumentManager.interpret_to_end Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  (* After split, should have 2 goals *)
  let result = Mcpserver.McpPrinting.get_proof_state st in
  [%test_pred: string] (String.is_substring ~substring:"2 goal") result

let%test_unit "mcp.operations.shelved_goals" =
  (* Test a proof with shelved goals *)
  let st, init_events = em_init_test_doc ~text:"Lemma foo : True.\nProof.\n  shelve." in
  let events = DocumentManager.interpret_to_end Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  let result = Mcpserver.McpPrinting.format_interp_result st in
  [%test_pred: string] (String.is_substring ~substring:"Shelved") result

(* ============== MCP Text Edit Tests ============== *)

let edit_text st ~start ~stop ~text =
  let doc = DocumentManager.Internal.document st in
  let doc = Document.raw_document doc in
  let start = RawDocument.position_of_loc doc start in
  let end_ = RawDocument.position_of_loc doc stop in
  let range = Lsp.Types.Range.{ start; end_ } in
  let st, events = DocumentManager.apply_text_edits st [(range, text)] in
  let todo = Sel.Todo.add Sel.Todo.empty events in
  handle_dm_events todo st

let%test_unit "mcp.edit.basic" =
  let st, init_events = em_init_test_doc ~text:"Definition x := 1." in
  let events = DocumentManager.interpret_to_end Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  check_no_diag st;
  (* Edit the definition *)
  let st = edit_text st ~start:16 ~stop:17 ~text:"2" in
  let events = DocumentManager.interpret_to_end Settings.Mode.Manual in
  let todo = Sel.Todo.(add Sel.Todo.empty events) in
  let st = handle_dm_events todo st in
  check_no_diag st

let%test_unit "mcp.edit.invalidates_execution" =
  let st, init_events = em_init_test_doc ~text:"Definition x := 1. Definition y := x." in
  let st, (s1, (s2, ())) = dm_parse st (P(P O)) in
  let events = DocumentManager.interpret_to_end Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  [%test_pred: sentence_id option] (Option.equal Stateid.equal (Some s2.id)) (DocumentManager.Internal.observe_id st);
  (* Edit first definition - should invalidate second *)
  let st = edit_text st ~start:0 ~stop:18 ~text:"Definition x := 2." in
  (* observe_id should be reset since the dependency changed *)
  [%test_eq: int option] (Option.map ~f:Stateid.to_int (DocumentManager.Internal.observe_id st)) None
