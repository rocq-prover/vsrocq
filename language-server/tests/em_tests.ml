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

let set_check_mode check_mode =
  CheckingManager.(set_options {
    block_on_first_error = false;
    check_mode;
    diff_mode = Protocol.Settings.Goals.Diff.Mode.Off;
    pp_mode = Protocol.Settings.Goals.PrettyPrint.Pp;
    point_interp_mode = Protocol.Settings.PointInterpretationMode.Cursor;
    preempt = true;
  })

(* Runs [text] to the end, replaces the sentence at 0-based [index] with [by]
   in one edit, and runs it again. Returns the state and the sentences after
   the edit. Fails unless every other sentence keeps its id. Typing the
   replacement character by character can re-create the Qed, which hides
   stale results. *)
let replace_sentence ?(delegation = ExecutionManager.CheckProofsInMaster) ?(check_mode = Protocol.Settings.Mode.Manual) ~text ~index ~by () =
  set_delegation_mode delegation;
  set_check_mode check_mode;
  Stdlib.Fun.protect ~finally:(fun () ->
    ExecutionManager.set_default_options ();
    set_check_mode Protocol.Settings.Mode.Manual) @@ fun () ->
  let st, events = em_init_test_doc ~text in
  let st = handle_dm_events Sel.Todo.(add events (DocumentManager.interpret_to_end ())) st in
  let sentences st = Document.sentences_sorted_by_loc (DocumentManager.Internal.document st) in
  let ids st = List.filteri (sentences st) ~f:(fun i _ -> i <> index)
    |> List.map ~f:(fun (s : Document.sentence) -> Stateid.to_int s.id) in
  let ids_before = ids st in
  let edited = List.nth_exn (sentences st) index in
  let range = Document.range_of_id (DocumentManager.Internal.document st) edited.id in
  let st, events = DocumentManager.apply_text_edits st [range, by] in
  let st = handle_dm_events Sel.Todo.(add empty events) st in
  let st =
    if Stdlib.(check_mode = Protocol.Settings.Mode.Manual) then
      handle_dm_events Sel.Todo.(add empty (DocumentManager.interpret_to_end ())) st
    else st in
  [%test_eq: int list] ids_before (ids st);
  st, Array.of_list (sentences st)

(* Fails if any diagnostic is an error, listing the first line of each. *)
let check_no_error st =
  let errors = List.filter (DocumentManager.all_diagnostics st)
    ~f:(fun d -> Stdlib.(d.Lsp.Types.Diagnostic.severity = Some Lsp.Types.DiagnosticSeverity.Error)) in
  [%test_eq: string list] [] (List.map errors ~f:(fun d -> List.hd_exn (String.split_lines (string_of_message d.message))))

let proof step = "Lemma x : True. Proof. " ^ step ^ " Qed. Check x."

let%test_unit "exec: qed rechecked when a proof step is replaced (#1355)" =
  let st, s = replace_sentence ~text:(proof "exact I.") ~index:2 ~by:"idtac." () in
  check_diag st [ D (s.(3).id, Error, ".*incomplete proof.*") ]

let%test_unit "exec: qed error cleared when a proof step is replaced (#1058)" =
  let st, s = replace_sentence ~text:(proof "idtac.") ~index:2 ~by:"exact I." () in
  check_no_error st;
  check_diag st [ D (s.(4).id, Information, ".*True.*") ]

let%test_unit "exec: qed rechecked when a proof step is replaced, delegate" =
  let delegation = ExecutionManager.DelegateProofsToWorkers { number_of_workers = 1 } in
  let st, s = replace_sentence ~delegation ~text:(proof "exact I.") ~index:2 ~by:"idtac." () in
  check_diag st [ D (s.(3).id, Error, ".*incomplete proof.*") ]

let%test_unit "exec: qed error cleared when a proof step is replaced, delegate" =
  let delegation = ExecutionManager.DelegateProofsToWorkers { number_of_workers = 1 } in
  let st, s = replace_sentence ~delegation ~text:(proof "idtac.") ~index:2 ~by:"exact I." () in
  check_no_error st;
  check_diag st [ D (s.(4).id, Information, ".*True.*") ]

let%test_unit "exec: qed rechecked when a proof step is replaced, continuous" =
  let check_mode = Protocol.Settings.Mode.Continuous in
  let st, s = replace_sentence ~check_mode ~text:(proof "exact I.") ~index:2 ~by:"idtac." () in
  check_diag st [ D (s.(3).id, Error, ".*incomplete proof.*") ]

let%test_unit "exec: qed error cleared when a proof step is replaced, continuous" =
  let check_mode = Protocol.Settings.Mode.Continuous in
  let st, s = replace_sentence ~check_mode ~text:(proof "idtac.") ~index:2 ~by:"exact I." () in
  check_no_error st;
  check_diag st [ D (s.(4).id, Information, ".*True.*") ]

let%test_unit "exec: nested qed rechecked when a proof step is replaced" =
  let text = "Set Nested Proofs Allowed. Lemma x : True. Proof. Lemma y : True. Proof. exact I. Qed. exact y. Qed." in
  let st, s = replace_sentence ~text ~index:5 ~by:"idtac." () in
  check_diag st [ D (s.(6).id, Error, ".*incomplete proof.*") ]

(* Each Qed below is a dependent of its opener and of its three proof steps, so
   a walk of the dependents that does not skip visited sentences reaches the
   sentences after the n-th proof 4^n times. With 15 proofs, such a walk takes
   tens of minutes, so a regression shows up as a hang rather than as a failed
   assertion. *)
let%test_unit "exec: edit before many proofs invalidates each sentence once" =
  let text = "Definition d := 0. " ^ String.concat (List.init 15 ~f:(fun i ->
    Printf.sprintf "Lemma l%d : True. Proof. idtac. exact I. Qed. " i)) in
  let st, events = em_init_test_doc ~text in
  let st = handle_dm_events events st in
  let document st = DocumentManager.Internal.document st in
  let first = List.hd_exn (Document.sentences_sorted_by_loc (document st)) in
  let range = Document.range_of_id (document st) first.id in
  let st, events = DocumentManager.apply_text_edits st [range, "Definition d := 1."] in
  let st = handle_dm_events Sel.Todo.(add empty events) st in
  (* Checks that the edit kept every sentence of the 15 proofs. *)
  [%test_eq: int] 76(List.length (Document.sentences_sorted_by_loc (document st)))
