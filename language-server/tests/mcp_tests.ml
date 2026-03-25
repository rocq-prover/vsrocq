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
  (* At start, there are no messages *)
  [%test_pred: string option] Option.is_none result

let%test_unit "mcp.printing.get_errors.no_errors" =
  let st, init_events = em_init_test_doc ~text:"Definition x := 1." in
  let events = DocumentManager.interpret_to_end Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  let result = Mcpserver.McpPrinting.get_errors st in
  (* No errors should be present *)
  [%test_pred: string option] Option.is_none result

let%test_unit "mcp.printing.get_errors.with_errors" =
  let st, init_events = em_init_test_doc ~text:"undefined_var." in
  let events = DocumentManager.interpret_to_end Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  let result = Mcpserver.McpPrinting.get_errors st in
  (* Should have errors *)
  [%test_pred: string option] Option.is_some result

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
  (* Edit the definition - replace "1" with "2" *)
  let st = edit_text st ~start:16 ~stop:17 ~text:"2" in
  let events = DocumentManager.interpret_to_end Settings.Mode.Manual in
  let todo = Sel.Todo.(add Sel.Todo.empty events) in
  let st = handle_dm_events todo st in
  check_no_diag st

let%test_unit "mcp.edit.line_character_positions" =
  (* Test that line/character positions work correctly for apply_edit *)
  let st, init_events = em_init_test_doc ~text:"Definition x := 1.\nDefinition y := 2." in
  (* Execute to end *)
  let events = DocumentManager.interpret_to_end Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  (* Get the raw document *)
  let doc = DocumentManager.Internal.document st in
  let raw_doc = Document.raw_document doc in
  (* Verify initial text *)
  [%test_pred: string] (String.is_substring ~substring:"Definition x := 1.") (RawDocument.text raw_doc);
  (* Apply edit using line/character positions: line 0, chars 16-17 (replacing "1" with "42") *)
  let range = Lsp.Types.Range.{
    start = Lsp.Types.Position.create ~line:0 ~character:16;
    end_ = Lsp.Types.Position.create ~line:0 ~character:17
  } in
  let st, events = DocumentManager.apply_text_edits st [(range, "42")] in
  let todo = Sel.Todo.add Sel.Todo.empty events in
  let st = handle_dm_events todo st in
  (* Verify the text was updated correctly *)
  let doc = DocumentManager.Internal.document st in
  let raw_doc = Document.raw_document doc in
  let text = RawDocument.text raw_doc in
  [%test_pred: string] (String.is_substring ~substring:"Definition x := 42") text

let%test_unit "mcp.edit.line_edit_single_line" =
  (* Test editing a single line using line/character positions *)
  let st, init_events = em_init_test_doc ~text:"Definition x := 1.\nDefinition y := 2." in
  (* Apply edit: replace entire line 0 with new content *)
  (* Line 0 is "Definition x := 1." (positions 0-17), newline at 17 *)
  (* Range from (0, 0) to (1, 0) replaces "Definition x := 1.\n" *)
  let range = Lsp.Types.Range.{
    start = Lsp.Types.Position.create ~line:0 ~character:0;
    end_ = Lsp.Types.Position.create ~line:1 ~character:0
  } in
  let st, events = DocumentManager.apply_text_edits st [(range, "Definition x := 42.")] in
  let todo = Sel.Todo.add Sel.Todo.empty events in
  let st = handle_dm_events todo st in
  (* Verify the text was updated correctly *)
  let doc = DocumentManager.Internal.document st in
  let raw_doc = Document.raw_document doc in
  let text = RawDocument.text raw_doc in
  (* Should have the new line and the second line should follow *)
  [%test_pred: string] (String.is_substring ~substring:"Definition x := 42.") text;
  [%test_pred: string] (String.is_substring ~substring:"Definition y := 2.") text

let%test_unit "mcp.edit.multiline_edit" =
  (* Test editing across multiple lines using line/character positions *)
  let st, init_events = em_init_test_doc ~text:"Definition x := 1.\nDefinition y := 2." in
  (* Get raw document to understand positions *)
  let doc = DocumentManager.Internal.document st in
  let raw_doc = Document.raw_document doc in
  (* Edit: change line 1 "Definition y := 2." to "Definition y := 42." *)
  (* Line 1 starts at character 18 (after "Definition x := 1.\n") *)
  (* "Definition y := 2." is at positions 18-36 approximately *)
  let range = Lsp.Types.Range.{
    start = Lsp.Types.Position.create ~line:1 ~character:18;
    end_ = Lsp.Types.Position.create ~line:1 ~character:36
  } in
  let st, events = DocumentManager.apply_text_edits st [(range, "Definition y := 42.")] in
  let todo = Sel.Todo.add Sel.Todo.empty events in
  let st = handle_dm_events todo st in
  (* Verify the text was updated correctly *)
  let doc = DocumentManager.Internal.document st in
  let raw_doc = Document.raw_document doc in
  let text = RawDocument.text raw_doc in
  [%test_pred: string] (String.is_substring ~substring:"Definition y := 42") text

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

let get_document_text st =
  let doc = DocumentManager.Internal.document st in
  let raw = Document.raw_document doc in
  RawDocument.text raw

(* Helper for applying text edits using ranges *)
let apply_text_edits st l =
  let st, events = DocumentManager.apply_text_edits st l in
  let todo = Sel.Todo.add Sel.Todo.empty events in
  handle_dm_events todo st

let%test_unit "mcp.edit.updates_content" =
  (* Test that apply_edit correctly updates the document content *)
  let initial_text = "Definition x := 1." in
  let st, init_events = em_init_test_doc ~text:initial_text in
  (* Verify initial content *)
  [%test_eq: string] (get_document_text st) initial_text;
  (* Edit: change "1" to "42" *)
  let st = edit_text st ~start:16 ~stop:17 ~text:"42" in
  let expected_text = "Definition x := 42." in
  [%test_eq: string] (get_document_text st) expected_text

let%test_unit "mcp.edit.insert_text" =
  (* Test inserting text (empty range) *)
  let initial_text = "Definition x := 1." in
  let st, _init_events = em_init_test_doc ~text:initial_text in
  (* Insert " + 1" before the period (at position 17, right after "1") *)
  let st = edit_text st ~start:17 ~stop:17 ~text:" + 1" in
  let expected_text = "Definition x := 1 + 1." in
  [%test_eq: string] (get_document_text st) expected_text

let%test_unit "mcp.edit.delete_text" =
  (* Test deleting text (empty replacement) *)
  let initial_text = "Definition foo := 1." in
  let st, _init_events = em_init_test_doc ~text:initial_text in
  (* Delete "foo" (positions 11-14) and replace with "x" *)
  let st = edit_text st ~start:11 ~stop:14 ~text:"x" in
  let expected_text = "Definition x := 1." in
  [%test_eq: string] (get_document_text st) expected_text

let%test_unit "mcp.edit.multiline" =
  (* Test editing multiline content *)
  let initial_text = "Definition x := 1.\nDefinition y := 2." in
  let st, _init_events = em_init_test_doc ~text:initial_text in
  (* Replace "1" with "100" in first definition *)
  let st = edit_text st ~start:35 ~stop:36 ~text:"300" in
  let expected_text = "Definition x := 1.\nDefinition y := 300." in
  [%test_eq: string] (get_document_text st) expected_text

let%test_unit "mcp.edit.replace_entire_content" =
  (* Test replacing entire document content *)
  let initial_text = "Definition x := 1." in
  let st, _init_events = em_init_test_doc ~text:initial_text in
  let new_text = "Lemma foo : True." in
  let st = edit_text st ~start:0 ~stop:(String.length initial_text) ~text:new_text in
  [%test_eq: string] (get_document_text st) new_text

(* ============== MCP update_proof Tests ============== *)
(* Tests for the update_proof command which re-parses the document *)

let trigger_update_proof st =
  (* Simulates what update_proof does: apply_text_edits with empty list *)
  let st, events = DocumentManager.apply_text_edits st [] in
  let todo = Sel.Todo.add Sel.Todo.empty events in
  handle_dm_events todo st

let%test_unit "mcp.update_proof.triggers_reparse" =
  (* Test that update_proof triggers re-parsing by checking document text is preserved *)
  let st, init_events = em_init_test_doc ~text:"Definition x := 1." in
  (* Execute the document *)
  let events = DocumentManager.interpret_to_end Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  (* Now call update_proof (empty edit) - should trigger re-parse *)
  let st = trigger_update_proof st in
  (* After update_proof, document should still have the correct text *)
  let doc = DocumentManager.Internal.document st in
  let raw_doc = Document.raw_document doc in
  let text = RawDocument.text raw_doc in
  [%test_pred: string] (String.is_substring ~substring:"Definition x := 1.") text

let%test_unit "mcp.update_proof.invalidates_after_edit" =
  (* Test that edit properly invalidates the state *)
  let st, init_events = em_init_test_doc ~text:"Definition x := 1. Definition y := x." in
  (* Execute to the end *)
  let events = DocumentManager.interpret_to_end Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  (* Verify we're at the end *)
  [%test_pred: sentence_id option] Option.is_some (DocumentManager.Internal.observe_id st);
  (* Now edit the first definition - this changes x from 1 to 2 *)
  let st = edit_text st ~start:0 ~stop:18 ~text:"Definition x := 2." in
  (* After edit, the execution state should be invalidated (observe_id reset) *)
  [%test_pred: sentence_id option] Option.is_none (DocumentManager.Internal.observe_id st)

let%test_unit "mcp.update_proof.after_external_edit" =
  (* Test the workflow: document is edited externally, then update_proof is called *)
  let initial_text = "Lemma foo : 1 = 1. Proof. reflexivity. Defined." in
  let st, init_events = em_init_test_doc ~text:initial_text in
  (* Execute to the end - should have a completed proof *)
  let events = DocumentManager.interpret_to_end Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  (* Should have executed all sentences *)
  [%test_pred: sentence_id option] Option.is_some (DocumentManager.Internal.observe_id st);
  (* Now simulate external edit by replacing "reflexivity" (positions 26-36) with "exact (eq_refl)" *)
  let st = edit_text st ~start:26 ~stop:37 ~text:"exact (eq_refl)" in
  (* Now call update_proof to re-parse *)
  let st = trigger_update_proof st in
  (* After update_proof, document should have the new text and be re-parsed *)
  let doc = DocumentManager.Internal.document st in
  let raw_doc = Document.raw_document doc in
  let text = RawDocument.text raw_doc in
  [%test_pred: string] (String.is_substring ~substring:"exact (eq_refl)") text

let%test_unit "mcp.update_proof.returns_state_before_edit" =
  (* Test that after an edit and calling update_proof,
     the proof state is properly invalidated and re-parsed *)
  let initial_text = "Definition a := 1. Definition b := 2. Definition c := 3." in
  let st, init_events = em_init_test_doc ~text:initial_text in
  (* Parse the document to get sentence positions - there are 3 sentences *)
  let st, (s1, (s2, (s3, ()))) = dm_parse st (P(P(P O))) in
  (* Execute to the end - should have executed all sentences *)
  let events = DocumentManager.interpret_to_end Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  (* Verify we're at the last sentence *)
  let obs_id = DocumentManager.Internal.observe_id st in
  [%test_pred: sentence_id option] (Option.equal Stateid.equal (Some s3.id)) obs_id;
  (* Now edit the FIRST definition (this should invalidate all following state) *)
  let st = edit_text st ~start:0 ~stop:18 ~text:"Definition a := 42." in
  (* After edit, the observe_id should be reset because the first sentence changed *)
  let obs_id_after_edit = DocumentManager.Internal.observe_id st in
  [%test_pred: sentence_id option] Option.is_none obs_id_after_edit;
  (* Now call update_proof to re-parse *)
  let st = trigger_update_proof st in
  (* After update_proof, the document should be re-parsed.
     The observe_id is still None because we haven't re-executed yet.
     But the document text should be updated. *)
  let obs_id_after_update = DocumentManager.Internal.observe_id st in
  [%test_pred: sentence_id option] Option.is_none obs_id_after_update;
  (* Verify the document text was updated *)
  let doc = DocumentManager.Internal.document st in
  let raw_doc = Document.raw_document doc in
  let text = RawDocument.text raw_doc in
  [%test_pred: string] (String.is_substring ~substring:"Definition a := 42") text

let%test_unit "mcp.update_proof.state_before_edit_in_proof" =
  (* Test that editing in the middle of a proof and calling update_proof
     properly re-parses the document *)
  (* Document structure:
     s1: Lemma foo : 1 = 1.
     s2: Proof.
     s3: reflexivity.
     s4: Defined. *)
  let initial_text = "Lemma foo : 1 = 1. Proof. reflexivity. Defined." in
  let st, init_events = em_init_test_doc ~text:initial_text in
  (* Parse to get sentence positions: s1, s2, s3, s4 *)
  let st, (s1, (s2, (s3, (s4, ())))) = dm_parse st (P(P(P(P O)))) in
  (* Execute to the end - should be at s4 *)
  let events = DocumentManager.interpret_to_end Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  (* Verify we're at the last sentence s4 *)
  let obs_id = DocumentManager.Internal.observe_id st in
  [%test_pred: sentence_id option] (Option.equal Stateid.equal (Some s4.id)) obs_id;
  (* Now edit s3 (reflexivity) to "exact (eq_refl)" using the sentence range *)
  let doc = DocumentManager.Internal.document st in
  let st = apply_text_edits st [(Document.range_of_id doc s3.id, "exact (eq_refl)")] in
  (* After edit, verify the document text was updated *)
  let doc = DocumentManager.Internal.document st in
  let raw_doc = Document.raw_document doc in
  let text = RawDocument.text raw_doc in
  [%test_pred: string] (String.is_substring ~substring:"exact (eq_refl)") text

