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

let folding_ranges_of text =
  let st, _init_events = em_init_test_doc ~text in
  DocumentManager.get_folding_ranges st

let has_folding_range ?kind ~startLine ~endLine ranges =
  let matches_kind (range: Lsp.Types.FoldingRange.t) =
    match kind with
    | None -> true
    | Some kind -> Stdlib.(=) range.kind (Some kind)
  in
  Stdlib.List.exists (fun (range: Lsp.Types.FoldingRange.t) ->
    range.startLine = startLine && range.endLine = endLine && matches_kind range
  ) ranges

let string_of_folding_range (range: Lsp.Types.FoldingRange.t) =
  let character = function
    | None -> "?"
    | Some character -> Int.to_string character
  in
  Printf.sprintf "%d:%s-%d:%s"
    range.startLine (character range.startCharacter) range.endLine (character range.endCharacter)

let string_of_folding_ranges ranges =
  ranges
  |> Stdlib.List.map string_of_folding_range
  |> Stdlib.String.concat ", "

let assert_has_folding_range ?kind ~startLine ~endLine ranges =
  if not (has_folding_range ?kind ~startLine ~endLine ranges) then
    failwith (Printf.sprintf "missing folding range %d-%d in [%s]"
      startLine endLine (string_of_folding_ranges ranges))

let assert_no_folding_range ?kind ~startLine ~endLine ranges =
  if has_folding_range ?kind ~startLine ~endLine ranges then
    failwith (Printf.sprintf "unexpected folding range %d-%d in [%s]"
      startLine endLine (string_of_folding_ranges ranges))

let%test_unit "folding.proof_starts_at_proof_command" =
  folding_ranges_of {|Lemma foo : True.
Proof.
  exact I.
Qed.|}
  |> assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:1 ~endLine:3

let%test_unit "folding.proof_without_proof_command_starts_at_first_tactic" =
  folding_ranges_of {|Lemma foo : True.
  exact I.
Qed.|}
  |> assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:1 ~endLine:2

let%test_unit "folding.proof_starts_at_first_proof_step" =
  let ranges = folding_ranges_of {|Lemma foo : True.
Proof.
  exact I.
  exact I.
Qed.|} in
  assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:1 ~endLine:4 ranges;
  assert_no_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:3 ~endLine:4 ranges

let%test_unit "folding.defined_emits_proof_fold" =
  folding_ranges_of {|Lemma foo : True.
Proof.
  exact I.
Defined.|}
  |> assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:1 ~endLine:3

let%test_unit "folding.admitted_emits_proof_fold" =
  folding_ranges_of {|Lemma foo : True.
Proof.
Admitted.|}
  |> assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:1 ~endLine:2

let%test_unit "folding.abort_emits_proof_fold" =
  folding_ranges_of {|Lemma foo : True.
Proof.
Abort.|}
  |> assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:1 ~endLine:2

let%test_unit "folding.section" =
  folding_ranges_of {|Section S.
Definition x := true.
End S.|}
  |> assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:0 ~endLine:2

let%test_unit "folding.module" =
  folding_ranges_of {|Module M.
Definition x := true.
End M.|}
  |> assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:0 ~endLine:2

let%test_unit "folding.nested_section_module" =
  let ranges = folding_ranges_of {|Module M.
Section S.
Definition x := true.
End S.
End M.|} in
  assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:0 ~endLine:4 ranges;
  assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:1 ~endLine:3 ranges

let%test_unit "folding.multiline_comment" =
  folding_ranges_of {|(* one
two *)
Check nat.|}
  |> assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Comment ~startLine:0 ~endLine:1

let%test_unit "folding.single_line_ranges_filtered" =
  let ranges = folding_ranges_of {|Definition x := true.
(* comment *)|} in
  [%test_eq: int] (Stdlib.List.length ranges) 0

let%test_unit "folding.inductive_whole_declaration" =
  folding_ranges_of {|Inductive color :=
| Red
| Blue.|}
  |> assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:0 ~endLine:2

let%test_unit "folding.inductive_constructor_type" =
  let ranges = folding_ranges_of {|Inductive tree : Type :=
| Leaf : tree
| Node :
    tree ->
    tree ->
    tree.|} in
  assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:0 ~endLine:5 ranges;
  [%test_eq: bool] (Stdlib.List.exists (fun (range: Lsp.Types.FoldingRange.t) ->
    range.startLine > 0 && range.endLine = 5 && Stdlib.(=) range.kind (Some Lsp.Types.FoldingRangeKind.Region)
  ) ranges) true

let%test_unit "folding.record_whole_declaration" =
  folding_ranges_of {|Record box := {
  value : nat
}.|}
  |> assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:0 ~endLine:2

let%test_unit "folding.single_line_inductive_filtered" =
  let ranges = folding_ranges_of "Inductive color := Red | Blue." in
  [%test_eq: int] (Stdlib.List.length ranges) 0

let%test_unit "folding.module_type" =
  folding_ranges_of {|Module Type T.
Parameter x : nat.
End T.|}
  |> assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:0 ~endLine:2

let%test_unit "folding.require_multiline" =
  folding_ranges_of {|Require Import
  Coq.Init.Nat.|}
  |> assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:0 ~endLine:1

let%test_unit "folding.notation_multiline" =
  folding_ranges_of {|Notation "## x" :=
  x
  (at level 0).|}
  |> assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:0 ~endLine:2

let%test_unit "folding.definition_multiline_body" =
  let ranges = folding_ranges_of {|Definition f :=
  match true with
  | true => 0
  | false => 1
  end.|} in
  assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:1 ~endLine:4 ranges

let%test_unit "folding.theorem_multiline_statement" =
  let ranges = folding_ranges_of {|Theorem foo :
  True ->
  True.
Proof.
  exact (fun _ => I).
Qed.|} in
  assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:1 ~endLine:2 ranges;
  assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:3 ~endLine:5 ranges

let%test_unit "folding.fixpoint_multiline_body" =
  let ranges = folding_ranges_of {|Fixpoint length {A : Type} (xs : list A) : nat :=
  match xs with
  | nil => 0
  | cons _ xs' => S (length xs')
  end.|} in
  assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:1 ~endLine:4 ranges

let%test_unit "folding.definition_multiline_type_and_body" =
  let ranges = folding_ranges_of {|Definition complex_definition
  : forall A : Type,
    A -> A
  := fun A x =>
    match x with
    | y => y
    end.|} in
  assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:3 ~endLine:6 ranges;
  assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:4 ~endLine:6 ranges

let%test_unit "folding.theorem_multiline_quantified_statement" =
  let ranges = folding_ranges_of {|Theorem complex_theorem :
  forall A : Type,
  forall x : A,
    x = x.
Proof.
  intros A x.
  reflexivity.
Qed.|} in
  assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:1 ~endLine:3 ranges;
  assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:4 ~endLine:7 ranges

let%test_unit "folding.definition_nested_match_body" =
  let ranges = folding_ranges_of {|Definition nested_match (b c : bool) :=
  match b with
  | true =>
      match c with
      | true => 1
      | false => 2
      end
  | false => 0
  end.|} in
  assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:1 ~endLine:8 ranges;
  assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:3 ~endLine:6 ranges
