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

(* Skip mode must not publish the incomplete-proof error, nor Rocq >= 9.3's
   missing-proof-command warning, alongside the final Check. *)
let check_only_diag st spec =
  [%test_eq: int] 1 (List.length (DocumentManager.all_diagnostics st));
  check_diag st [spec]

let check_no_processing st =
  [%test_pred: Protocol.LspWrapper.Range.t list] List.is_empty
    (DocumentManager.executed_ranges st).Types.processing

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
  [%test_eq: int]
    0 (List.length (Document.all_checking_errors (DocumentManager.Internal.document st)));
  check_only_diag st (D (s4.id,Information,".*True.*"));
  ExecutionManager.set_default_options ()

[%%if rocq = "8.18" || rocq = "8.19" || rocq = "8.20" || rocq = "9.0" || rocq = "9.1" || rocq = "9.2" || rocq = "9.3"]

let%test_unit "exec: option overrides need Rocq 9.4" =
  [%test_eq: bool] true (Result.is_error (OptionOverrides.toggle_flag ["Mangle"; "Names"]))

[%%else]

let toggle key = Result.ok_or_failwith (OptionOverrides.toggle_flag key)
let toggle_debug name = Result.ok_or_failwith (OptionOverrides.toggle_debug_flag name)
let debug_flag name =
  Stdlib.List.find_map (fun (n, enabled, overridden) ->
    if String.equal n name then Some (enabled, overridden) else None)
    (OptionOverrides.debug_flags ())

let%test_unit "exec: option overrides" =
  let text = "Unset Mangle Names. Test Mangle Names. Set Debug \"-backtrace\". Test Debug." in
  let st, events = em_init_test_doc ~text in
  let st, (s1, (s2, (s3, (s4, ())))) = dm_parse st (P(P(P(P O)))) in
  [%test_eq: bool option] (Some true) (toggle ["Mangle"; "Names"]);
  let backtrace = Option.value_exn (Option.map ~f:fst (debug_flag "backtrace")) in
  [%test_eq: bool option] (Some (not backtrace)) (toggle_debug "backtrace");
  [%test_eq: (bool * bool) option] (Some (not backtrace, true)) (debug_flag "backtrace");
  let st = handle_dm_events Sel.Todo.(add events (DocumentManager.interpret_to_end ())) st in
  (* the overrides take precedence over the Unset and Set of the document,
     which still set the values saved in the states *)
  check_diag st [
    D (s2.id,Information,"Mangle Names is on (overridden, the value set by the commands is off)");
    D (s4.id,Information,".*-backtrace.*")
  ];
  [%test_eq: (bool * bool) option] (Some (not backtrace, true)) (debug_flag "backtrace");
  (* toggling again removes the overrides *)
  [%test_eq: bool option] None (toggle ["Mangle"; "Names"]);
  [%test_eq: bool option] None (toggle_debug "backtrace");
  [%test_eq: bool] false (Option.value_exn (Option.map ~f:snd (debug_flag "backtrace")));
  OptionOverrides.clear ()

(* Like [handle_dm_events], but also returns the events left, among which the
   feedback listener of the document, which later executions need *)
let rec run_events n todo st =
  if n <= 0 || Sel.Todo.is_empty todo then st, todo
  else match Sel.pop_timeout ~stop_after_being_idle_for:0.3 todo with
    | None, _ -> st, todo
    | Some ev, remaining ->
      let { Types.state; events; _ } = DocumentManager.handle_event ev st in
      let st = Option.value_map state ~default:st ~f:fst in
      run_events (n-1) (Sel.Todo.add remaining events) st
let run_events todo st = run_events 100 todo st

let%test_unit "exec: option overrides, removed before executing the next sentence" =
  (* Execute "Unset Mangle Names. Test Mangle Names." with Mangle Names
     overridden, remove the override, then append a third sentence and
     execute it: it starts from the state of the second sentence, which was
     computed with the override, and follows the document again *)
  let text = "Unset Mangle Names. Test Mangle Names." in
  let st, todo = em_init_test_doc ~text in
  [%test_eq: bool option] (Some true) (toggle ["Mangle"; "Names"]);
  let st, todo = run_events Sel.Todo.(add todo (DocumentManager.interpret_to_end ())) st in
  [%test_eq: bool option] None (toggle ["Mangle"; "Names"]);
  let raw = DocumentManager.Internal.raw_document st in
  let end_ = RawDocument.position_of_loc raw (String.length text) in
  let st, events = DocumentManager.apply_text_edits st [Lsp.Types.Range.{ start = end_; end_ }, " Test Mangle Names."] in
  let st, todo = run_events (Sel.Todo.add todo events) st in
  let st, (_, (s2, (s3, ()))) = dm_parse st (P(P(P O))) in
  let st, _ = run_events Sel.Todo.(add todo (DocumentManager.interpret_to_end ())) st in
  [%test_eq: bool] true (DocumentManager.Internal.is_locally_executed st s3.id);
  check_diag st [
    D (s2.id,Information,"Mangle Names is on (overridden, the value set by the commands is off)");
    D (s3.id,Information,"Mangle Names is off$")
  ];
  OptionOverrides.clear ()

let%test_unit "exec: option overrides, errors" =
  [%test_eq: bool] true (Result.is_error (OptionOverrides.toggle_flag ["No"; "Such"; "Option"]));
  (* not a flag *)
  [%test_eq: bool] true (Result.is_error (OptionOverrides.toggle_flag ["Printing"; "Width"]));
  [%test_eq: bool] true (Result.is_error (OptionOverrides.toggle_debug_flag "no-such-flag"))

[%%endif]

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

let%test_unit "exec: client fixture proof skip" =
  let text = "Lemma x : True.\nProof.\n  idtac.\n  apply foobar.\n  idtac.\nQed.\nCheck x." in
  let st, events = em_init_test_doc ~text in
  let st, (s1, (s2, (s3, (s4, (s5, (s6, (s7, ()))))))) =
    dm_parse st (P(P(P(P(P(P(P O))))))) in
  set_delegation_mode SkipProofs;
  let exec_events = DocumentManager.interpret_to_end () in
  let todo = Sel.Todo.(add events exec_events) in
  let st = handle_dm_events todo st in
  let errors = Document.all_checking_errors (DocumentManager.Internal.document st) in
  [%test_eq: int] 0 (List.length errors);
  check_only_diag st (D (s7.id,Information,".*True.*"));
  ExecutionManager.set_default_options ()

let%test_unit "exec: unfinished proof skip" =
  let st, events = em_init_test_doc ~text:"Lemma x : True. Qed. Check x." in
  let st, (s1, (s2, (s3, ()))) = dm_parse st (P(P(P O))) in
  set_delegation_mode SkipProofs;
  let exec_events = DocumentManager.interpret_to_end () in
  let todo = Sel.Todo.(add events exec_events) in
  let st = handle_dm_events todo st in
  [%test_eq: int]
    0 (List.length (Document.all_checking_errors (DocumentManager.Internal.document st)));
  check_only_diag st (D (s3.id,Information,".*True.*"));
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
  check_no_processing st;
  ExecutionManager.set_default_options ()

(* The delegated proof is the last task of the run, so nothing after it
   forwards the event that starts the worker. *)
let%test_unit "exec: unfinished proof delegate, qed last" =
  let st, events = em_init_test_doc ~text:"Lemma x : True. Proof. idtac. Qed." in
  let st, (s1, (s2, (s3, (s4, ())))) = dm_parse st (P(P(P(P O)))) in
  set_delegation_mode (DelegateProofsToWorkers { number_of_workers = 1 });
  let exec_events = DocumentManager.interpret_to_end () in
  let todo = Sel.Todo.(add events exec_events) in
  let st = handle_dm_events todo st in
  check_diag st [
    D (s4.id,Error,".*incomplete proof.*")
  ];
  ExecutionManager.set_default_options ()

let%test_unit "exec: feedback after a delegated proof" =
  let st, events = em_init_test_doc ~text:"Lemma x : True. Qed." in
  let st, (s1, (s2, ())) = dm_parse st (P(P O)) in
  set_delegation_mode (DelegateProofsToWorkers { number_of_workers = 1 });
  let todo = Sel.Todo.(add events (DocumentManager.interpret_to_end ())) in
  let _ = handle_dm_events todo st in
  ExecutionManager.set_default_options ();
  (* The worker has exited, and the master's own feedback must not go to it *)
  let st, events = em_init_test_doc ~text:"Check nat." in
  let st, (s1, ()) = dm_parse st (P O) in
  let todo = Sel.Todo.(add events (DocumentManager.interpret_to_end ())) in
  let st = handle_dm_events todo st in
  check_diag st [
    D (s1.id,Information,".*Set.*")
  ]

let%test_unit "exec: delegated proof with tactics" =
  let st, events = em_init_test_doc ~text:"Lemma x : True. Proof. exact I. exact I. Qed. Check x." in
  let st, (s1, (s2, (s3, (s4, (s5, (s6, ())))))) = dm_parse st (P(P(P(P(P(P O)))))) in
  set_delegation_mode (DelegateProofsToWorkers { number_of_workers = 1 });
  let todo = Sel.Todo.(add events (DocumentManager.interpret_to_end ())) in
  let st = handle_dm_events todo st in
  check_diag st [
    D (s4.id,Error,".*No such goal.*")
  ];
  check_diag st [
    D (s6.id,Information,".*True.*")
  ];
  ExecutionManager.set_default_options ()

(* A proof with no steps gives the delegated job no tasks. *)
let%test_unit "exec: admitted proof delegate, no steps" =
  let st, events = em_init_test_doc ~text:"Lemma x : True. Admitted. Check x." in
  let st, (s1, (s2, (s3, ()))) = dm_parse st (P(P(P O))) in
  set_delegation_mode (DelegateProofsToWorkers { number_of_workers = 1 });
  let exec_events = DocumentManager.interpret_to_end () in
  let todo = Sel.Todo.(add events exec_events) in
  let st = handle_dm_events todo st in
  check_no_processing st;
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
