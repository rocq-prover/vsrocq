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

[@@@warning "-27"]

let set_delegation_mode mode =
  ExecutionManager.(set_options { delegation_mode = mode; completion_options = { enable = false; unificationLimit = 100; algorithm = StructuredSplitUnification; atomicFactor = 5.; sizeFactor = 5. }; enableDiagnostics = true })

let%test_unit "exec: finished proof" =
  let st, events = em_init_test_doc ~text:"Lemma x : True. trivial. Qed. Check x." in
  let st, (s1, (s2, (s3, (s4, ())))) = dm_parse st (P(P(P(P O)))) in
  let exec_events = DocumentManager.interpret_to_end () in
  let todo = Sel.Todo.(add events exec_events) in
  let st = handle_dm_events todo st in
  check_diag st [
    D (s4.id,Information,".*True.*")
  ]

let%test_unit "exec: finished proof skip" =
  let st, events = em_init_test_doc ~text:"Lemma x : True. trivial. Qed. Check x." in
  let st, (s1, (s2, (s3, (s4, ())))) = dm_parse st (P(P(P(P O)))) in
  set_delegation_mode SkipProofs;
  let exec_events = DocumentManager.interpret_to_end () in
  let todo = Sel.Todo.(add events exec_events) in
  let st = handle_dm_events todo st in
  check_diag st [
    D (s4.id,Information,".*True.*")
  ];
  ExecutionManager.set_default_options ()

let%test_unit "exec: unfinished proof" =
  let st, events = em_init_test_doc ~text:"Lemma x : True. Qed. Check x." in
  let st, (s1, (s2, (s3, ()))) = dm_parse st (P(P(P O))) in
  let exec_events = DocumentManager.interpret_to_end () in
  let todo = Sel.Todo.(add events exec_events) in
  let st = handle_dm_events todo st in
  let errors = Document.all_checking_errors (DocumentManager.Internal.document st) in
  [%test_eq: bool] true (1 = List.length errors);
  check_diag st [
    D (s2.id,Error,".*incomplete proof.*");
  ];
  check_diag st [
    D (s3.id,Information,".*True.*")
  ]

let%test_unit "exec: unfinished proof skip" =
  let st, events = em_init_test_doc ~text:"Lemma x : True. Qed. Check x." in
  let st, (s1, (s2, (s3, ()))) = dm_parse st (P(P(P O))) in
  set_delegation_mode SkipProofs;
  let exec_events = DocumentManager.interpret_to_end () in
  let todo = Sel.Todo.(add events exec_events) in
  let st = handle_dm_events todo st in
  check_diag st [
    D (s2.id,Error,".*incomplete proof.*")
  ];
  check_diag st [
    D (s3.id,Information,".*True.*")
  ];
  ExecutionManager.set_default_options ()

let%test_unit "exec: unfinished proof delegate" =
  let st, events = em_init_test_doc ~text:"Lemma x : True. Qed. Check x." in
  let st, (s1, (s2, (s3, ()))) = dm_parse st (P(P(P O))) in
  set_delegation_mode (DelegateProofsToWorkers { number_of_workers = 1 });
  let exec_events = DocumentManager.interpret_to_end () in
  let todo = Sel.Todo.(add events exec_events) in
  let st = handle_dm_events todo st in
  check_diag st [
    D (s2.id,Error,".*incomplete proof.*")
  ];
  check_diag st [
    D (s3.id,Information,".*True.*")
  ];
  ExecutionManager.set_default_options ()


let%test_unit "exec: unstarted proof" =
  let st, events = em_init_test_doc ~text:"Qed. Check nat." in
  let st, (s1, (s2, ())) = dm_parse st (P(P O)) in
  let exec_events = DocumentManager.interpret_to_end () in
  let todo = Sel.Todo.(add events exec_events) in
  let st = handle_dm_events todo st in
  check_diag st [
    D (s1.id,Error,".*No proof-editing in progress.*");
  ];
  check_diag st [
    D (s2.id,Information,".*Set.*")
  ]

(* Fails if any diagnostic is an error, listing the first line of each. *)
let check_no_error st =
  let errors = List.filter (DocumentManager.all_diagnostics st)
    ~f:(fun d -> Stdlib.(d.Lsp.Types.Diagnostic.severity = Some Lsp.Types.DiagnosticSeverity.Error)) in
  [%test_eq: string list] [] (List.map errors ~f:(fun d -> List.hd_exn (String.split_lines (string_of_message d.message))))

(* A sentence moved by an edit above it is not parsed again; its execution
   must still report locations in the current text, also inside a term. *)
let%test_unit "exec: error inside a moved sentence is at its current location" =
  let text = "Definition a := 1. Definition b := 2. Definition c := 1 + true." in
  let st, events = em_init_test_doc ~text in
  let st = handle_dm_events Sel.Todo.(add events (DocumentManager.interpret_to_end ())) st in
  let raw = Document.raw_document (DocumentManager.Internal.document st) in
  let range = Lsp.Types.Range.{ start = RawDocument.position_of_loc raw 16; end_ = RawDocument.position_of_loc raw 17 } in
  let st, events = DocumentManager.apply_text_edits st [range, "11"] in
  let st = handle_dm_events Sel.Todo.(add empty events) st in
  let st = handle_dm_events Sel.Todo.(add empty (DocumentManager.interpret_to_end ())) st in
  let errors = List.filter_map (DocumentManager.all_diagnostics st) ~f:(fun d ->
    if Stdlib.(d.Lsp.Types.Diagnostic.severity = Some Lsp.Types.DiagnosticSeverity.Error)
    then Some (d.range.start.character, d.range.end_.character) else None) in
  (* "true" is at 59-63 after the edit *)
  [%test_eq: (int * int) list] [59, 63] errors

(* Runs [text], replaces [start, stop) with [by], runs it again, and compares
   every diagnostic with a run of the final text from scratch. The todo is
   carried along, since it holds the listener for execution feedback. Messages
   of a run before an invalidation are kept next to the new ones, so equal
   diagnostics are counted once. *)
let check_exec_same_as_fresh ?(delegation = ExecutionManager.CheckProofsInMaster) ~text (start, stop, by) =
  set_delegation_mode delegation;
  Stdlib.Fun.protect ~finally:ExecutionManager.set_default_options @@ fun () ->
  let run text =
    let st, events = em_init_test_doc ~text in
    handle_dm_events_keep_todo Sel.Todo.(add events (DocumentManager.interpret_to_end ())) st in
  let diags st =
    List.map (DocumentManager.all_diagnostics st) ~f:(fun d ->
      let r = d.Lsp.Types.Diagnostic.range in
      Printf.sprintf "%d-%d %s" r.start.character r.end_.character
        (List.hd_exn (String.split_lines (string_of_message d.message))))
    |> List.dedup_and_sort ~compare:String.compare in
  let st, todo = run text in
  let raw = Document.raw_document (DocumentManager.Internal.document st) in
  let range = Lsp.Types.Range.{ start = RawDocument.position_of_loc raw start; end_ = RawDocument.position_of_loc raw stop } in
  let st, events = DocumentManager.apply_text_edits st [range, by] in
  let st, todo = handle_dm_events_keep_todo Sel.Todo.(add todo events) st in
  let st, _ = handle_dm_events_keep_todo Sel.Todo.(add todo (DocumentManager.interpret_to_end ())) st in
  let final = RawDocument.text (Document.raw_document (DocumentManager.Internal.document st)) in
  [%test_eq: string list] (diags (fst (run final))) (diags st)

let%test_unit "exec: warning inside a moved sentence is at its current location" =
  check_exec_same_as_fresh (16, 17, "11")
    ~text:"Definition a := 1. #[deprecated(since=\"x\")] Definition d := 1. Definition b := 2. Check d."

(* Runs [text] to the end, inserts [insert] at offset [at], and runs it again. *)
let insert_and_run ~text ~at ~insert =
  let st, events = em_init_test_doc ~text in
  let st = handle_dm_events Sel.Todo.(add events (DocumentManager.interpret_to_end ())) st in
  let raw = Document.raw_document (DocumentManager.Internal.document st) in
  let p = RawDocument.position_of_loc raw at in
  let st, events = DocumentManager.apply_text_edits st [Lsp.Types.Range.create ~start:p ~end_:p, insert] in
  let st = handle_dm_events Sel.Todo.(add empty events) st in
  handle_dm_events Sel.Todo.(add empty (DocumentManager.interpret_to_end ())) st

let%test_unit "exec: sentence after an inserted definition checked again" =
  check_no_error (insert_and_run ~text:"Definition a := 1. Check x." ~at:19 ~insert:"Definition x := 0. ")

let%test_unit "exec: qed checked again after a step inserted before it" =
  check_no_error (insert_and_run ~text:"Lemma x : True. Proof. Qed." ~at:23 ~insert:"exact I. ")
