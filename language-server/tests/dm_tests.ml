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

[@@@warning "-27"]

let edit_text st ~start ~stop ~text =
  let doc = DocumentManager.Internal.document st in
  let doc = Document.raw_document doc in
  let start = RawDocument.position_of_loc doc start in
  let end_ = RawDocument.position_of_loc doc stop in
  let range = Lsp.Types.Range.{ start; end_ } in
  let st, events = DocumentManager.apply_text_edits st [(range, text)] in
  let todo = Sel.Todo.add Sel.Todo.empty events in
  handle_dm_events todo st

  let apply_text_edits st l =
    let st, events = DocumentManager.apply_text_edits st l in
    let todo = Sel.Todo.add Sel.Todo.empty events in
    handle_dm_events todo st


let insert_text st ~loc ~text =
  edit_text st ~start:loc ~stop:loc ~text

let%test_unit "parse.init" =
  let st, init_events = em_init_test_doc ~text:"Definition x := true. Definition y := false." in
  let doc = Document.raw_document @@ DocumentManager.Internal.document st in
  [%test_eq: int] (RawDocument.end_loc doc) 44;
  let sentences = Document.sentences @@ DocumentManager.Internal.document st in
  let positions = Stdlib.List.map (fun (s : Document.sentence) -> s.Document.start) sentences in
  [%test_eq: int list] positions [ 0; 22 ];
  check_no_diag st

let%test_unit "parse.insert" =
  let st, init_events = em_init_test_doc ~text:"Definition x := true. Definition y := false." in
  let st = insert_text st ~loc:0 ~text:"Definition z := 0. " in
  let sentences = Document.sentences @@ DocumentManager.Internal.document st in
  let positions = Stdlib.List.map (fun (s : Document.sentence) -> s.Document.start) sentences in
  [%test_eq: int list] positions [ 0; 19; 41 ];
  check_no_diag st

let%test_unit "parse.squash" =
                                              (*          1         2         3         4         5         6         7*)
                                              (*01234567890123456789012345678901234567890123456789012345678901234567890*)
  let st, init_events = em_init_test_doc ~text:"Definition x := true. Definition y := false. Definition z := 0." in
  let st = edit_text st ~start:20 ~stop:21 ~text:"" in
  let doc = DocumentManager.Internal.document st in
  let sentences = Document.sentences doc in
  let start_positions = Stdlib.List.map (fun (s : Document.sentence) -> s.Document.start) sentences in
  let stop_positions = Stdlib.List.map (fun (s : Document.sentence) -> s.Document.stop) sentences in
  [%test_eq: int list] start_positions [ 0; 44 ];
  [%test_eq: int list] stop_positions [ 43; 62 ];
  [%test_eq: int] (List.length (Document.parse_errors doc)) 1

let%test_unit "parse.error_recovery" =
                                              (*          1         2         3         4         5         6         7*)
                                              (*01234567890123456789012345678901234567890123456789012345678901234567890*)
  let st, init_events = em_init_test_doc ~text:"## . Definition x := true. !! . Definition y := false." in
  let doc = DocumentManager.Internal.document st in
  let sentences = Document.sentences doc in
  let start_positions = Stdlib.List.map (fun (s : Document.sentence) -> s.Document.start) sentences in
  [%test_eq: int list] start_positions [ 0; 5; 26; 32 ];
  [%test_eq: int] (List.length (Document.parse_errors doc)) 2

let%test_unit "parse.extensions" =
                                              (*          1         2         3         4         5         6         7*)
                                              (*01234567890123456789012345678901234567890123456789012345678901234567890*)
  let st, init_events = em_init_test_doc ~text:"Notation \"## x\" := x (at level 0). Definition f (x : nat) := ##xx." in
  let sentences = Document.sentences @@ DocumentManager.Internal.document st in
  let start_positions = Stdlib.List.map (fun (s : Document.sentence) -> s.Document.start) sentences in
  [%test_eq: int list] start_positions [ 0; 35 ];
  check_no_diag st

let%test_unit "parse.invalidate_before_module" =
  let st, init_events = em_init_test_doc ~text:"Check nat. Module M := Nat." in
  let st, (s1, (s2, ())) = dm_parse st (P(P O)) in
  let st, events = DocumentManager.interpret_to_end (`String "test") st Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  let doc = DocumentManager.Internal.document st in
  let st = apply_text_edits st [(Document.range_of_id doc s1.id, "")] in
  check_no_diag st

let%test_unit "exec.init" =
  let st, init_events = em_init_test_doc ~text:"Definition x := true. Definition y := false." in
  let st, events = DocumentManager.interpret_to_end (`String "test") st Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  let ranges = (DocumentManager.executed_ranges st Settings.Mode.Manual).processed in
  let positions = Stdlib.List.map (fun s -> s.Lsp.Types.Range.start.character) ranges in
  [%test_eq: int list] positions [ 0 ];
  let positions = Stdlib.List.map (fun s -> s.Lsp.Types.Range.end_.character) ranges in
  [%test_eq: int list] positions [ 44 ];
  check_no_diag st

let%test_unit "exec.require_error" =
  let st, init_events = em_init_test_doc ~text:"Require fuhidkgjh. Definition x := true." in
  let st, (s1, (s2, ())) = dm_parse st (E(P O)) in
  let st, events = DocumentManager.interpret_to_end (`String "test") st Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  let ranges = (DocumentManager.executed_ranges st Settings.Mode.Manual).processed in
  let positions = Stdlib.List.map (fun s -> s.Lsp.Types.Range.start.character) ranges in
  [%test_eq: int list] positions [ 18 ]

let%test_unit "step_forward.delete_observe_id" =
  let st, init_events = em_init_test_doc ~text:"Definition x := 3. Lemma foo : x = 3." in 
  let st, (s1, (s2, ())) = dm_parse st (P(P O)) in
  let st, events = DocumentManager.interpret_to_next (`String "test") st Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  let st, events = DocumentManager.interpret_to_next (`String "test") st Settings.Mode.Manual in
  let todo = Sel.Todo.(add todo events) in
  let st = handle_dm_events todo st in
  [%test_pred: sentence_id option] (Option.equal Stateid.equal (Some s2.id)) (DocumentManager.Internal.observe_id st);
  let doc = DocumentManager.Internal.document st in
  let st = apply_text_edits st [Document.range_of_id doc s2.id,""] in
  [%test_pred: sentence_id option] (Option.equal Stateid.equal (Some s1.id)) (DocumentManager.Internal.observe_id st)

let%test_unit "step_forward.expand_sentence_observe_id" =
  let st, init_events = em_init_test_doc ~text:"Definition x := 3. P." in 
  let st, (s1, (s2, ())) = dm_parse st (P(P O)) in
  let st, events = DocumentManager.interpret_to_next (`String "test") st Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  let st, events = DocumentManager.interpret_to_next (`String "test") st Settings.Mode.Manual in
  let todo = Sel.Todo.(add todo events) in
  let st = handle_dm_events todo st in
  [%test_pred: sentence_id option] (Option.equal Stateid.equal (Some s2.id)) (DocumentManager.Internal.observe_id st);
  let doc = DocumentManager.Internal.document st in
  let range = Document.range_of_id doc s2.id in
  let new_range = Lsp.Types.Range.{ start = range.end_; end_ = range.end_ } in
  let st = apply_text_edits st [new_range,"bar."] in
  [%test_pred: sentence_id option] (Option.equal Stateid.equal (Some s1.id)) (DocumentManager.Internal.observe_id st)

let%test_unit "step_forward.insert_space_after_sentence_observe_id" =
  let st, init_events = em_init_test_doc ~text:"Definition x := 3. P." in 
  let st, (s1, (s2, ())) = dm_parse st (P(P O)) in
  let st, events = DocumentManager.interpret_to_next (`String "test") st Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  let st, events = DocumentManager.interpret_to_next (`String "test") st Settings.Mode.Manual in
  let todo = Sel.Todo.(add todo events) in
  let st = handle_dm_events todo st in
  [%test_pred: sentence_id option] (Option.equal Stateid.equal (Some s2.id)) (DocumentManager.Internal.observe_id st);
  let doc = DocumentManager.Internal.document st in
  let range = Document.range_of_id doc s2.id in
  let new_range = Lsp.Types.Range.{ start = range.end_; end_ = range.end_ } in
  let st = apply_text_edits st [new_range," "] in
  [%test_pred: sentence_id option] (Option.equal Stateid.equal (Some s2.id)) (DocumentManager.Internal.observe_id st)

let%test_unit "step_forward.proof_view" =
  let st, init_events = em_init_test_doc ~text:"Definition x := 3. Lemma foo : x = 3." in 
  let st, (s1, (s2, ())) = dm_parse st (P(P O)) in
  let st, events = DocumentManager.interpret_to_next (`String "test") st Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  let st, events = DocumentManager.interpret_to_next (`String "test") st Settings.Mode.Manual in
  let todo = Sel.Todo.(add todo events) in
  let st = handle_dm_events todo st in
  let st, events = DocumentManager.interpret_to_next (`String "test") st Settings.Mode.Manual in
  let todo = Sel.Todo.(add todo events) in
  let st = handle_dm_events todo st in
  [%test_pred: sentence_id option] (Option.equal Stateid.equal (Some s2.id)) (DocumentManager.Internal.observe_id st);
  let data = DocumentManager.get_proof st Protocol.Settings.Goals.Diff.Mode.Off None in
  [%test_eq: bool] (Option.is_some data) true
  (* 
  let doc = DocumentManager.Internal.document st in
  let st = DocumentManager.apply_text_edits st [Document.range_of_id doc s2.id,""] in 
  [%test_pred: sentence_id option] (Option.equal Stateid.equal (Some s1.id)) (DocumentManager.Internal.observe_id st) *)

let%test_unit "step_forward.document_begin" =
  let st, init_events = em_init_test_doc ~text:"(* Some comment *)\nLemma foo : x = 3." in
  let st, (s1, ()) = dm_parse st (P O) in
  let st, events = DocumentManager.interpret_to_next (`String "test") st Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in 
  [%test_pred: sentence_id option] (Option.equal Stateid.equal (Some s1.id)) (DocumentManager.Internal.observe_id st)

let%test_unit "step_backward.document_begin" =
  let st, init_events = em_init_test_doc ~text:"(* Some comment *)\nLemma foo : x = 3." in
  let st, (s1, ()) = dm_parse st (P O) in
  let st, events = DocumentManager.interpret_to_next (`String "test") st Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  let todo = Sel.Todo.(add init_events events) in
  let st, events = DocumentManager.interpret_to_previous (`String "test") st Settings.Mode.Manual in
  let st = handle_dm_events todo st in
  [%test_eq: bool] (Option.is_none (DocumentManager.Internal.observe_id st)) true

(*
let%test_unit "exec.insert" =
  let st, events = init_test_doc ~text:"Definition x := true. Definition y := false." in
  (* let st = handle_dm_events events st in *)
  let st = DocumentManager.validate_document st in
  let st, events = DocumentManager.interpret_to_end st in
  let st = insert_text st ~loc:0 ~text:"Definition z := 0. " in
  let st = DocumentManager.validate_document st in
  let st, events = DocumentManager.interpret_to_end st in
  let ranges = (DocumentManager.executed_ranges st).processed in
  let positions = Stdlib.List.map (fun s -> s.Lsp.Types.Range.start.char) ranges in
  check_no_diag st;
  [%test_eq: int list] positions [ 0; 22 ]
  *)

let%test_unit "edit.shift_warning_in_sentence" =
  let st, init_events = em_init_test_doc ~text:"#[deprecated(note = \"foo\", since = \"foo\")] Definition x := true. Definition y := x." in
  let st, (s1, (s2, ())) = dm_parse st (P(P O)) in
  let st, events = DocumentManager.interpret_to_end (`String "test") st Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  check_diag st [
    D (s2.id,Warning,".*deprecated.*")
  ];
  let warning = Stdlib.List.hd @@ DocumentManager.all_diagnostics st in
  [%test_eq: int] 81 (warning.range.start.character);
  [%test_eq: int] 82 (warning.range.end_.character);
  let doc = DocumentManager.Internal.document st in
  let start = (Document.range_of_id doc s2.id).start in
  let range = Lsp.Types.Range.{ start; end_ = start } in
  let st = apply_text_edits st [range,"   "] in
  check_diag st [
    D (s2.id,Warning,".*deprecated.*")
  ];
  let warning = Stdlib.List.hd @@ DocumentManager.all_diagnostics st in
  [%test_eq: int] 84 (warning.range.start.character);
  [%test_eq: int] 85 (warning.range.end_.character)

let%test_unit "edit.shift_warning_before_sentence" =
  let st, init_events = em_init_test_doc ~text:"#[deprecated(note = \"foo\", since = \"foo\")] Definition x := true. Definition y := x." in
  let st, (s1, (s2, ())) = dm_parse st (P(P O)) in
  let st, events = DocumentManager.interpret_to_end (`String "test") st Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  check_diag st [
    D (s2.id,Warning,".*deprecated.*")
  ];
  let warning = Stdlib.List.hd @@ DocumentManager.all_diagnostics st in
  [%test_eq: int] 81 (warning.range.start.character);
  [%test_eq: int] 82 (warning.range.end_.character);
  let st = edit_text st ~start:0 ~stop:0 ~text:"   " in
  check_diag st [
    D (s2.id,Warning,".*deprecated.*")
  ];
  let warning = Stdlib.List.hd @@ DocumentManager.all_diagnostics st in
  [%test_eq: int] 84 (warning.range.start.character);
  [%test_eq: int] 85 (warning.range.end_.character)

let%test_unit "edit.shift_error_in_sentence" =
  let st, init_events = em_init_test_doc ~text:"Definition x := true. Definition y := z." in
  let st, (s1, (s2, ())) = dm_parse st (P(P O)) in
  let st, events = DocumentManager.interpret_to_end (`String "test") st Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  check_diag st [
    D (s2.id,Error,".*z was not found.*")
  ];
  let warning = Stdlib.List.hd @@ DocumentManager.all_diagnostics st in
  [%test_eq: int] 38 (warning.range.start.character);
  [%test_eq: int] 39 (warning.range.end_.character);
  let doc = DocumentManager.Internal.document st in
  let start = (Document.range_of_id doc s2.id).start in
  let range = Lsp.Types.Range.{ start; end_ = start } in
  let st = apply_text_edits st [range,"   "] in
  check_diag st [
    D (s2.id,Error,".*z was not found.*")
  ];
  let warning = Stdlib.List.hd @@ DocumentManager.all_diagnostics st in
  [%test_eq: int] 41 (warning.range.start.character);
  [%test_eq: int] 42 (warning.range.end_.character)

let%test_unit "edit.shift_error_before_sentence" =
  let st, init_events = em_init_test_doc ~text:"Definition x := true. Definition y := z." in
  let st, (s1, (s2, ())) = dm_parse st (P(P O)) in
  let st, events = DocumentManager.interpret_to_end (`String "test") st Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  check_diag st [
    D (s2.id,Error,".*z was not found.*")
  ];
  let warning = Stdlib.List.hd @@ DocumentManager.all_diagnostics st in
  [%test_eq: int] 38 (warning.range.start.character);
  [%test_eq: int] 39 (warning.range.end_.character);
  let st = edit_text st ~start:0 ~stop:0 ~text:"   " in
  check_diag st [
    D (s2.id,Error,".*z was not found.*")
  ];
  let warning = Stdlib.List.hd @@ DocumentManager.all_diagnostics st in
  [%test_eq: int] 41 (warning.range.start.character);
  [%test_eq: int] 42 (warning.range.end_.character)

let%test_unit "edit.edit_non_root_observe_id_top" =
  let st, init_events = em_init_test_doc ~text:"Definition x := 1. Definition y := 2." in
  let st, (s1, (s2, ())) = dm_parse st (P(P O)) in
  let st, events = DocumentManager.interpret_to_end (`String "test") st Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  let st = edit_text st ~start:0 ~stop:18 ~text:"Definition x := 3." in
  [%test_eq: bool] (ExecutionManager.is_locally_executed (DocumentManager.Internal.execution_state st) s2.id) false;
  [%test_eq: int option] (Option.map ~f:Stateid.to_int (DocumentManager.Internal.observe_id st)) None

let%test_unit "edit.edit_non_root_observe_id" =
  let st, init_events = em_init_test_doc ~text:"Definition x := 1. Definition y := 2. Definition z := 3." in
  let st, (s1, (s2, (s3, ()))) = dm_parse st (P(P(P O))) in
  let st, events = DocumentManager.interpret_to_end (`String "test") st Settings.Mode.Manual in
  let todo = Sel.Todo.(add init_events events) in
  let st = handle_dm_events todo st in
  let st = edit_text st ~start:19 ~stop:37 ~text:"Definition y := 4." in
  [%test_eq: bool] (ExecutionManager.is_locally_executed (DocumentManager.Internal.execution_state st) s3.id) false;
  [%test_eq: int option] (Option.map ~f:Stateid.to_int (DocumentManager.Internal.observe_id st))
    (Some (Stateid.to_int s1.id))