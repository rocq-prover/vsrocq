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

let document_symbols_of text =
  let st, _init_events = em_init_test_doc ~text in
  DocumentManager.get_document_symbols st

let children_of_symbol (symbol: Lsp.Types.DocumentSymbol.t) =
  match symbol.children with
  | None -> []
  | Some children -> children

let find_symbol name symbols =
  Stdlib.List.find_opt (fun (symbol: Lsp.Types.DocumentSymbol.t) -> Stdlib.(=) symbol.name name) symbols

let assert_symbol ?kind name symbols =
  match find_symbol name symbols with
  | None -> failwith (Printf.sprintf "missing document symbol %s" name)
  | Some symbol ->
    begin match kind with
    | None -> ()
    | Some kind -> [%test_eq: bool] Stdlib.(symbol.kind = kind) true
    end;
    symbol

let has_folding_range ?kind ~startLine ~endLine ranges =
  let matches_kind (range: Lsp.Types.FoldingRange.t) =
    match kind with
    | None -> true
    | Some kind -> Stdlib.(=) range.kind (Some kind)
  in
  Stdlib.List.exists (fun (range: Lsp.Types.FoldingRange.t) ->
    range.startLine = startLine && range.endLine = endLine && matches_kind range
  ) ranges

let count_folding_ranges ?kind ~startLine ~endLine ranges =
  let matches_kind (range: Lsp.Types.FoldingRange.t) =
    match kind with
    | None -> true
    | Some kind -> Stdlib.(=) range.kind (Some kind)
  in
  ranges
  |> Stdlib.List.filter (fun (range: Lsp.Types.FoldingRange.t) ->
    range.startLine = startLine && range.endLine = endLine && matches_kind range
  )
  |> Stdlib.List.length

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

let%test_unit "folding.proof_multiline_dash_bullet_blocks" =
  let ranges = folding_ranges_of {|Lemma foo : True /\ True.
Proof.
  split.
  -
    exact I.
  -
    exact I.
Qed.|} in
  assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:1 ~endLine:7 ranges;
  assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:3 ~endLine:4 ranges;
  assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:5 ~endLine:6 ranges

let%test_unit "folding.proof_nested_bullet_blocks" =
  let ranges = folding_ranges_of {|Lemma foo : (True /\ True) /\ (True /\ True).
Proof.
  split.
  - split.
    +
      exact I.
    +
      exact I.
  - split.
    +
      exact I.
    +
      exact I.
Qed.|} in
  assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:3 ~endLine:7 ranges;
  assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:4 ~endLine:5 ranges;
  assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:6 ~endLine:7 ranges;
  assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:8 ~endLine:12 ranges

let%test_unit "folding.proof_curly_subproof" =
  let ranges = folding_ranges_of {|Lemma foo : True.
Proof.
  {
    exact I.
  }
Qed.|} in
  assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:1 ~endLine:5 ranges;
  assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:2 ~endLine:4 ranges

let%test_unit "folding.proof_nested_curly_subproofs" =
  let ranges = folding_ranges_of {|Lemma foo : True.
Proof.
  {
    {
      exact I.
    }
  }
Qed.|} in
  assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:2 ~endLine:6 ranges;
  assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:3 ~endLine:5 ranges

let%test_unit "folding.proof_mixed_bullets_and_curly_subproofs" =
  let ranges = folding_ranges_of {|Lemma foo : True /\ True.
Proof.
  split.
  -
    {
      exact I.
    }
  - exact I.
Qed.|} in
  assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:3 ~endLine:6 ranges;
  assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:4 ~endLine:6 ranges

let%test_unit "folding.incomplete_curly_subproof_closes_at_qed" =
  let ranges = folding_ranges_of {|Lemma foo : True.
Proof.
  {
    exact I.
Qed.|} in
  assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:2 ~endLine:3 ranges

let%test_unit "folding.incomplete_proof_closes_at_eof" =
  folding_ranges_of {|Lemma foo : True.
Proof.
  exact I.|}
  |> assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:1 ~endLine:2

let%test_unit "folding.incomplete_proof_bullet_closes_at_eof" =
  let ranges = folding_ranges_of {|Lemma foo : True /\ True.
Proof.
  split.
  -
    exact I.
  -
    exact I.|} in
  assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:1 ~endLine:6 ranges;
  assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:5 ~endLine:6 ranges

let%test_unit "folding.section" =
  folding_ranges_of {|Section S.
Definition x := true.
End S.|}
  |> assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:0 ~endLine:2

let%test_unit "folding.incomplete_section_closes_at_eof" =
  folding_ranges_of {|Section S.
Definition x := true.|}
  |> assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:0 ~endLine:1

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

let%test_unit "folding_symbols.single_line_definition" =
  let symbols = document_symbols_of "Definition x := true." in
  let symbol = assert_symbol ~kind:Lsp.Types.SymbolKind.Variable "x" symbols in
  [%test_eq: int] symbol.range.start.line 0;
  [%test_eq: int] symbol.selectionRange.start.line 0

let%test_unit "folding_symbols.nested_module_section_ranges" =
  let symbols = document_symbols_of {|Module M.
Section S.
Definition x := true.
End S.
End M.|} in
  let m = assert_symbol ~kind:Lsp.Types.SymbolKind.Class "M" symbols in
  [%test_eq: int] m.range.start.line 0;
  [%test_eq: int] m.range.end_.line 4;
  [%test_eq: int] m.selectionRange.start.line 0;
  [%test_eq: int] m.selectionRange.end_.line 0;
  let s = assert_symbol ~kind:Lsp.Types.SymbolKind.Class "S" (children_of_symbol m) in
  [%test_eq: int] s.range.start.line 1;
  [%test_eq: int] s.range.end_.line 3;
  [%test_eq: int] s.selectionRange.start.line 1;
  [%test_eq: int] s.selectionRange.end_.line 1;
  ignore (assert_symbol ~kind:Lsp.Types.SymbolKind.Variable "x" (children_of_symbol s))

let%test_unit "folding_symbols.constr_subexpressions_not_symbols" =
  let symbols = document_symbols_of {|Definition nested_match (b c : bool) :=
  match b with
  | true =>
      match c with
      | true => 1
      | false => 2
      end
  | false => 0
  end.|} in
  [%test_eq: int] (Stdlib.List.length symbols) 1;
  ignore (assert_symbol ~kind:Lsp.Types.SymbolKind.Variable "nested_match" symbols)

let%test_unit "folding_symbols.notation_folds_not_symbols" =
  let symbols = document_symbols_of {|Notation "## x" :=
  x
  (at level 0).|} in
  [%test_eq: int] (Stdlib.List.length symbols) 0

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

let%test_unit "folding.extension_tab_indentation" =
  let ranges = folding_ranges_of "Ltac foo :=\n\tmatch goal with\n\t| |- True => exact I\n\tend." in
  assert_has_folding_range ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:1 ~endLine:3 ranges;
  [%test_eq: int]
    (count_folding_ranges ~kind:Lsp.Types.FoldingRangeKind.Region ~startLine:1 ~endLine:3 ranges)
    1

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
