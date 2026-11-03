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

(* Each proof keeps its worker busy for about 0.2 s, so that the workers of
   consecutive proofs overlap. *)
let burning_proofs n =
  "Set Warnings \"-abstract-large-number\". \
   Fixpoint flip (n : nat) (b : bool) : bool := \
     match n with 0 => b | S m => flip m (negb b) end. \
   Fixpoint burn (k n : nat) (b : bool) : bool := \
     match k with 0 => b | S j => burn j n (flip n b) end. \
   Ltac burn k := let _ := eval vm_compute in (burn k 10000 true) in idtac. " ^
  Stdlib.String.concat " " (Stdlib.List.init n (fun i ->
    Printf.sprintf "Lemma p%d : True. Proof. burn 1000. exact I. Qed." i)) ^
  " Check I."

(* Checks a document of [proofs] delegated proofs with [workers] proof
   workers, calling [on_change ~before n] each time the number of running
   workers changes from [before] to [n]. *)
let run_delegated_proofs ~workers ~proofs ~on_change =
  [%test_eq: int] 0 (ExecutionManager.running_proof_workers ());
  set_delegation_mode (DelegateProofsToWorkers { number_of_workers = workers });
  let st, events = em_init_test_doc ~text:(burning_proofs proofs) in
  let last = ref 0 in
  let after_event () =
    let n = ExecutionManager.running_proof_workers () in
    if n <> !last then begin on_change ~before:!last n; last := n end in
  let exec_events = DocumentManager.interpret_to_end () in
  let st = handle_dm_events_with ~idle:1.0 ~after_event Sel.Todo.(add events exec_events) st in
  let errors = Document.all_checking_errors (DocumentManager.Internal.document st) in
  [%test_eq: int] 0 (List.length errors);
  [%test_eq: int] 0 (ExecutionManager.running_proof_workers ());
  ExecutionManager.set_default_options ()

let%test_unit "exec: delegate, proof workers bounded by the setting" =
  List.iter [1; 2; 3] ~f:(fun workers ->
    let peak = ref 0 in
    run_delegated_proofs ~workers ~proofs:(2 * workers + 1)
      ~on_change:(fun ~before:_ n -> peak := max !peak n);
    [%test_eq: int] workers !peak)

let%test_unit "exec: delegate, proof workers below 1 means 1" =
  let peak = ref 0 in
  run_delegated_proofs ~workers:0 ~proofs:3
    ~on_change:(fun ~before:_ n -> peak := max !peak n);
  [%test_eq: int] 1 !peak

(* Shrinking the pool stops no worker. A new one starts only once the number
   of running workers is below the new size. *)
let%test_unit "exec: delegate, shrinking the pool with workers running" =
  let resized = ref false in
  let running_after_start = ref [] in
  run_delegated_proofs ~workers:3 ~proofs:7 ~on_change:(fun ~before n ->
    if !resized then begin
      if n > before then running_after_start := n :: !running_after_start
    end else if n = 3 then begin
      set_delegation_mode (DelegateProofsToWorkers { number_of_workers = 1 });
      resized := true
    end);
  [%test_eq: bool] true !resized;
  [%test_eq: int list] [1; 1; 1; 1] !running_after_start

let%test_unit "exec: delegate, growing the pool with workers running" =
  let resized = ref false in
  let peak_after = ref 0 in
  run_delegated_proofs ~workers:1 ~proofs:5 ~on_change:(fun ~before:_ n ->
    if !resized then peak_after := max !peak_after n
    else if n = 1 then begin
      set_delegation_mode (DelegateProofsToWorkers { number_of_workers = 3 });
      resized := true
    end);
  [%test_eq: bool] true !resized;
  [%test_eq: int] 3 !peak_after

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
