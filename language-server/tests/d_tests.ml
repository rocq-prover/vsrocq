open Common
open Dm
open Types
open Base

[@@@warning "-27"]

let validate_document parsed_document =
  let doc, events = Document.validate_document parsed_document in
  let todo = Sel.Todo.add Sel.Todo.empty events in
  handle_d_events todo doc

let trdeps doc s1 =
  (* This closure should be an API used in Schedule used by ExecutionManager *)
  let rec trclose f s =
    let s' = Stateid.Set.fold (fun x acc -> Stateid.Set.union (f x) acc) s s in
    if Stateid.Set.equal s s' then s
    else trclose f s' in
  trclose (Scheduler.dependents (Document.schedule doc)) (Stateid.Set.singleton s1.id)

(* Replaces the text between [start] and [stop] with itself, so that it gets
   parsed again *)
let retype doc ~start ~stop =
  let raw = Document.raw_document doc in
  let text = RawDocument.string_in_range raw start stop in
  let range = Lsp.Types.Range.{ start = RawDocument.position_of_loc raw start; end_ = RawDocument.position_of_loc raw stop } in
  Document.apply_text_edits doc [range, text]


let%test_unit "parse.validate_errors_twice" = 
  let Document.{invalid_ids; parsed_document} = init_and_parse_test_doc () ~text:"Lemma a : True. Proof. idtac (fun x -> x). Qed." in
  [%test_eq: sentence_id list] [] (Stateid.Set.elements invalid_ids);
  let s1,(s2,(s3,(s4,()))) = d_sentences parsed_document (P(P(E(P(O))))) in
  [%test_eq: int] (List.length (Document.parse_errors parsed_document)) 1;
  let Document.{parsed_document} = validate_document (retype parsed_document ~start:s3.start ~stop:s3.stop) in
  [%test_eq: int] (List.length (Document.parse_errors parsed_document)) 1;
  let _,(_,(s3,(_,()))) = d_sentences parsed_document (P(P(E(P(O))))) in
  let Document.{parsed_document} = validate_document (retype parsed_document ~start:s3.start ~stop:s3.stop) in
  [%test_eq: int] (List.length (Document.parse_errors parsed_document)) 1

(* The Require parses but fails at synterp, which takes another path than a
   sentence that fails to parse. *)
let%test_unit "parse: a sentence failing at synterp starts after its blank" =
  let Document.{parsed_document} = init_and_parse_test_doc () ~text:"Definition x := 0.   Require fuhidkgjh." in
  let s2 = List.nth_exn (Document.sentences_sorted_by_loc parsed_document) 1 in
  [%test_eq: int] 18 s2.parsing_start;
  [%test_eq: int] 21 s2.start

let %test_unit "document: invalidate top" =
  let Document.{invalid_ids; parsed_document} = init_and_parse_test_doc () ~text:"Definition x := 3. Lemma foo : x = 3. Proof. reflexivity. Qed." in
  [%test_eq: sentence_id list] [] (Stateid.Set.elements invalid_ids);
  let s1,(s2,(s3,(s4,(s5,())))) = d_sentences parsed_document (P(P(P(P(P(O)))))) in
  let parsed_document = Document.apply_text_edits parsed_document [Document.range_of_id parsed_document s1.id,"Definition x := 4."] in
  let Document.{unchanged_id; invalid_ids; parsed_document} = validate_document parsed_document in
  let r1,(r2,(r3,(r4,(r5,())))) = d_sentences parsed_document (P(P(P(P(P(O)))))) in
  [%test_eq: sentence_id list] [s1.id] (Stateid.Set.elements invalid_ids);
  [%test_eq: sentence_id option] None unchanged_id;
  [%test_eq: sentence_id] s2.id r2.id;
  [%test_eq: sentence_id] s3.id r3.id;
  [%test_eq: sentence_id] s4.id r4.id;
  [%test_eq: sentence_id] s5.id r5.id;
  let deps = trdeps parsed_document s1 in
  [%test_pred: sentence_id] (fun x -> Stateid.Set.mem x deps) r2.id;
  [%test_pred: sentence_id] (fun x -> Stateid.Set.mem x deps) r3.id;
  [%test_pred: sentence_id] (fun x -> Stateid.Set.mem x deps) r4.id;
  [%test_pred: sentence_id] (fun x -> Stateid.Set.mem x deps) r5.id;
  ()

let %test_unit "document: invalidate proof" =
  let Document.{invalid_ids; parsed_document} = init_and_parse_test_doc () ~text:"Definition x := 3. Lemma foo : x = 3. Proof. reflexivity. Qed." in
  [%test_eq: sentence_id list] [] (Stateid.Set.elements invalid_ids);
  let s1,(s2,(s3,(s4,(s5,())))) = d_sentences parsed_document (P(P(P(P(P(O)))))) in
  let parsed_document = Document.apply_text_edits parsed_document [Document.range_of_id parsed_document s3.id,"idtac."] in
  let Document.{unchanged_id; invalid_ids; parsed_document} = validate_document parsed_document in
  let r1,(r2,(r3,(r4,(r5,())))) = d_sentences parsed_document (P(P(P(P(P(O)))))) in
  [%test_eq: sentence_id list] [s3.id] (Stateid.Set.elements invalid_ids);
  [%test_eq: sentence_id option] (Some s2.id) unchanged_id;
  [%test_eq: sentence_id] s1.id r1.id;
  [%test_eq: sentence_id] s2.id r2.id;
  [%test_eq: sentence_id] s4.id r4.id;
  [%test_eq: sentence_id] s5.id r5.id;
  let deps = trdeps parsed_document s3 in
  [%test_pred: sentence_id] (fun x -> not (Stateid.Set.mem x deps)) r1.id;
  [%test_pred: sentence_id] (fun x -> not (Stateid.Set.mem x deps)) r2.id;
  [%test_pred: sentence_id] (fun x -> not (Stateid.Set.mem x deps)) r3.id;
  [%test_pred: sentence_id] (fun x -> not (Stateid.Set.mem x deps)) r5.id;
  ()


let %test_unit "document: invalidate proof 2" =
  let Document.{invalid_ids; parsed_document} = init_and_parse_test_doc () ~text:"Definition x := 3. Lemma foo : x = 3. Proof. reflexivity. Qed." in
  [%test_eq: sentence_id list] [] (Stateid.Set.elements invalid_ids);
  let s1,(s2,(s3,(s4,(s5,())))) = d_sentences parsed_document (P(P(P(P(P(O)))))) in
  let previous_document = parsed_document in
  let parsed_document = Document.apply_text_edits parsed_document [Document.range_of_id parsed_document s3.id,""] in
  let Document.{unchanged_id; invalid_ids; parsed_document} = validate_document parsed_document in
  let r1,(r2,(r3,(r4,()))) = d_sentences parsed_document (P(P(P(P(O))))) in
  [%test_eq: sentence_id list] [s3.id] (Stateid.Set.elements invalid_ids);
  [%test_eq: sentence_id option] (Some s2.id) unchanged_id;
  [%test_eq: sentence_id] s1.id r1.id;
  [%test_eq: sentence_id] s2.id r2.id;
  [%test_eq: sentence_id] s4.id r3.id;
  [%test_eq: sentence_id] s5.id r4.id;
  (* s4 keeps its id, but it depended on s3 in the previous schedule, so
     invalidating s3 also invalidates its execution. *)
  let deps = trdeps previous_document s3 in
  [%test_pred: sentence_id] (fun x -> Stateid.Set.mem x deps) s4.id

let %test_unit "document: delete line" = 
  let Document.{unchanged_id; invalid_ids; parsed_document} = init_and_parse_test_doc () ~text:"Definition x:= 3. Lemma foo : x = 3. Proof. reflexitivity. Qed." in 
  [%test_eq: sentence_id list] [] (Stateid.Set.elements invalid_ids);
  let s1,(s2,(s3,(s4,(s5,())))) = d_sentences parsed_document (P(P(P(P(P(O)))))) in
  let parsed_document = Document.apply_text_edits parsed_document [Document.range_of_id parsed_document s5.id,""] in
  let Document.{unchanged_id; invalid_ids; parsed_document} = validate_document parsed_document in 
  let sentences_id = Stateid.Set.of_list (List.map (Document.sentences parsed_document) ~f:(fun s -> s.id)) in
  [%test_pred: sentence_id] (fun x -> not (Stateid.Set.mem x sentences_id)) s5.id;
  ()

let %test_unit "document: expand sentence" =
  let Document.{unchanged_id; invalid_ids; parsed_document} = init_and_parse_test_doc () ~text:"Lemma foo : x = 3. M." in
  [%test_eq: sentence_id list] [] (Stateid.Set.elements invalid_ids);
  let s1,(s2,()) = d_sentences parsed_document (P(P(O))) in
  let range = Document.range_of_id parsed_document s2.id in
  let new_range = Lsp.Types.Range.{ start = range.end_; end_ = range.end_ } in
  let parsed_document = Document.apply_text_edits parsed_document [new_range,"foo."] in
  let Document.{unchanged_id; invalid_ids; parsed_document} = validate_document parsed_document in
  let r1,(r2,()) = d_sentences parsed_document (P(P(O))) in
  [%test_eq: sentence_id] s1.id r1.id;
  ()

(* Oracle for incremental parsing: after the edits, the document must look the
   same as a fresh parse of its final text. The locations inside the AST of a
   moved sentence are behind by its [Document.ast_shift]. *)

let pp_loc_pair (bp, ep) = Printf.sprintf "%d-%d" bp ep
let pp_loc (loc : Loc.t option) = Option.value_map loc ~default:"none" ~f:(fun l -> pp_loc_pair (l.Loc.bp, l.Loc.ep))

let code_line_offsets = function
  | Document.Sentence s -> Printf.sprintf "S %d %d %d" s.parsing_start s.start s.stop
  | Document.ParsingError e -> Printf.sprintf "E %d %d" e.start e.stop
  | Document.Comment c -> Printf.sprintf "C %d %d %s" c.start c.stop c.content

let code_line_tokens = function
  | Document.Sentence ({ ast = Parsed { tokens } } as s) ->
    Printf.sprintf "S %d [%s]" s.start (String.concat ~sep:" " (List.map tokens ~f:(fun (l, t) ->
      Printf.sprintf "%s@%s" (Tok.extract_string true t) (pp_loc_pair (l.Loc.bp, l.Loc.ep)))))
  | Document.Sentence ({ ast = Error e } as s) -> Printf.sprintf "S %d error %s" s.start (pp_loc (fst e.msg))
  | Document.ParsingError e -> Printf.sprintf "E %d %s" e.start (pp_loc (fst e.msg))
  | Document.Comment c -> Printf.sprintf "C %d" c.start

let code_line_ast doc = function
  | Document.Sentence ({ ast = Parsed { ast } } as s) ->
    let shift = Document.ast_shift doc s.id in
    Some (Printf.sprintf "S %d ast %s" s.start (pp_loc (Option.map ast.CAst.loc ~f:(Loc.shift_loc shift shift))))
  | _ -> None

let check_same_as_fresh doc =
  let text = RawDocument.text (Document.raw_document doc) in
  let Document.{ parsed_document = fresh } = init_and_parse_test_doc () ~text in
  let lines d = Document.code_lines_sorted_by_loc d in
  [%test_eq: string list] (List.map (lines fresh) ~f:code_line_offsets) (List.map (lines doc) ~f:code_line_offsets);
  (* Every sentence reachable by id is the one reachable by position. *)
  let ids d = List.sort ~compare:Stateid.compare (List.map d ~f:(fun (s : Document.sentence) -> s.id)) in
  [%test_eq: sentence_id list] (ids (Document.sentences_sorted_by_loc doc)) (ids (Document.sentences doc));
  [%test_eq: string list] (List.map (lines fresh) ~f:code_line_tokens) (List.map (lines doc) ~f:code_line_tokens);
  let comments d = List.map (Document.comments d) ~f:(fun (c : Document.comment) -> Printf.sprintf "C %d %d %s" c.start c.stop c.content) in
  [%test_eq: string list] (comments fresh) (comments doc);
  [%test_eq: string list] (List.filter_map (lines fresh) ~f:(code_line_ast fresh)) (List.filter_map (lines doc) ~f:(code_line_ast doc))

(* An edit replaces [start, stop) of the text current at the time it is applied. *)
let range_of doc start stop =
  let raw = Document.raw_document doc in
  Lsp.Types.Range.{ start = RawDocument.position_of_loc raw start; end_ = RawDocument.position_of_loc raw stop }

let edit doc (start, stop, text) = range_of doc start stop, text

(* Applies each edit with its own [apply_text_edit] call, as DocumentManager does,
   then parses once. *)
let edit_one_by_one ~text edits =
  let Document.{ parsed_document } = init_and_parse_test_doc () ~text in
  let doc = List.fold edits ~init:parsed_document ~f:(fun doc e -> fst (Document.apply_text_edit doc (edit doc e))) in
  let Document.{ parsed_document } = validate_document doc in
  parsed_document

(* Applies all edits in a single [apply_text_edits] call, each edit's offsets
   being relative to the text left by the previous ones, as in an LSP didChange. *)
let edit_at_once ~text edits =
  let Document.{ parsed_document } = init_and_parse_test_doc () ~text in
  let raw, edits = List.fold edits ~init:(Document.raw_document parsed_document, []) ~f:(fun (raw, acc) (start, stop, t) ->
    let range = Lsp.Types.Range.{ start = RawDocument.position_of_loc raw start; end_ = RawDocument.position_of_loc raw stop } in
    fst (RawDocument.apply_text_edit raw (range, t)), (range, t) :: acc) in
  ignore raw;
  let Document.{ parsed_document } = validate_document (Document.apply_text_edits parsed_document (List.rev edits)) in
  parsed_document

let three = "Definition a := 1. Definition b := 2. Definition c := 3."

let%test_unit "oracle: no edit" =
  check_same_as_fresh (edit_one_by_one ~text:three [0, 0, ""])

let%test_unit "oracle: grow the first sentence" =
  check_same_as_fresh (edit_one_by_one ~text:three [16, 17, "11"])

let%test_unit "oracle: shrink the first sentence" =
  check_same_as_fresh (edit_one_by_one ~text:"Definition a := 11. Definition b := 2. Definition c := 3." [16, 18, "1"])

let%test_unit "oracle: grow the last sentence" =
  check_same_as_fresh (edit_one_by_one ~text:three [54, 55, "33"])

let%test_unit "oracle: delete the middle sentence" =
  check_same_as_fresh (edit_one_by_one ~text:three [19, 38, ""])

let%test_unit "oracle: merge two sentences" =
  check_same_as_fresh (edit_one_by_one ~text:"Check 1. Check 2. Check 3." [7, 8, ""])

let%test_unit "oracle: split a sentence" =
  check_same_as_fresh (edit_one_by_one ~text:"Check 1. Check 2. Check 3." [7, 7, ". Check 4"])

let%test_unit "oracle: introduce a parse error" =
  check_same_as_fresh (edit_one_by_one ~text:three [30, 30, "("])

let%test_unit "oracle: edit a comment" =
  check_same_as_fresh (edit_one_by_one ~text:"Check 1. (* x *) Check 2." [12, 13, "yy"])

(* B: each [apply_text_edit] call must keep the pending range of the previous ones. *)
let%test_unit "oracle: two edits in separate calls" =
  check_same_as_fresh (edit_one_by_one ~text:three [(16, 17, "11"); (55, 56, "33")])

(* F: offsets of a later edit are relative to the text after the earlier ones. *)
let%test_unit "oracle: two edits in one call" =
  check_same_as_fresh (edit_at_once ~text:three [(16, 17, "11"); (55, 56, "33")])

let five = "Check 1. Check 2. Check 3. Check 4. Check 5."

(* Unchanged sentences between the two edits let parsing stop before the second. *)
let%test_unit "oracle: two edits in one call, the first one deleting" =
  check_same_as_fresh (edit_at_once ~text:five [(0, 9, ""); (33, 34, "55")])

let%test_unit "oracle: two edits in separate calls, far apart" =
  check_same_as_fresh (edit_one_by_one ~text:five [(6, 7, "11"); (43, 44, "55")])

(* B: an edit arriving while a parse is running cancels it, and the next parse
   must still cover the first edit. *)
let%test_unit "oracle: edit during a parse" =
  let Document.{ parsed_document } = init_and_parse_test_doc () ~text:five in
  let doc = fst (Document.apply_text_edit parsed_document (edit parsed_document (6, 7, "11"))) in
  let doc, _cancelled = Document.validate_document doc in
  let doc = fst (Document.apply_text_edit doc (edit doc (43, 44, "55"))) in
  let Document.{ parsed_document } = validate_document doc in
  check_same_as_fresh parsed_document

let%test_unit "oracle: move a parse error" =
  check_same_as_fresh (edit_one_by_one ~text:"Definition a := 1. MDefinition x := 1. Check a." [16, 17, "11"])

(* An insertion moves the following sentences by more than their own length:
   the old ones after the edit must be found at their old offsets. *)
let%test_unit "oracle: insert a sentence" =
  check_same_as_fresh (edit_one_by_one ~text:three [19, 19, "Definition x := 0. "])

let%test_unit "oracle: insert a sentence longer than the next ones" =
  check_same_as_fresh (edit_one_by_one ~text:five [9, 9, "Definition long_name := 0. "])

let%test_unit "oracle: insert two sentences" =
  check_same_as_fresh (edit_one_by_one ~text:five [9, 9, "Check 6. Definition long_name := 0. "])

(* The string opened by the edit ends inside the last sentence, so parsing
   stops in the middle of it. *)
let%test_unit "oracle: open a string that ends inside a later sentence" =
  check_same_as_fresh (edit_one_by_one ~text:"Check 1. Check 2. Check \"x. y\"." [6, 6, "\""])

(* The string opened by the edit contains a comment of the last parse. *)
let%test_unit "oracle: open a string over a comment" =
  check_same_as_fresh (edit_one_by_one ~text:"Check 1. (* a *) Check \"x. y\"." [6, 6, "\""])

(* The inserted sentence has the same tokens as the next one. *)
let%test_unit "oracle: insert a copy of the next sentence" =
  check_same_as_fresh (edit_one_by_one ~text:"Check 1. Check 2." [8, 8, " Check 2."])

(* The deleted sentence has the same tokens as the next one. *)
let%test_unit "oracle: delete the first of two equal sentences" =
  check_same_as_fresh (edit_one_by_one ~text:"Check 1. Check 2. Check 2." [8, 17, ""])

let%test_unit "oracle: delete two sentences" =
  check_same_as_fresh (edit_one_by_one ~text:five [9, 27, ""])

let%test_unit "oracle: replace a sentence by a longer one" =
  check_same_as_fresh (edit_one_by_one ~text:five [9, 17, "Definition long_name := 0."])

let%test_unit "document: inserted sentences keep the ids of the next ones" =
  let ids doc = List.map (Document.sentences_sorted_by_loc doc) ~f:(fun (s : Document.sentence) -> Stateid.to_int s.id) in
  let Document.{ parsed_document } = init_and_parse_test_doc () ~text:five in
  let before = ids parsed_document in
  let doc = fst (Document.apply_text_edit parsed_document (edit parsed_document (9, 9, "Check 6. Definition long_name := 0. "))) in
  let Document.{ parsed_document } = validate_document doc in
  [%test_eq: int list] before (List.filteri (ids parsed_document) ~f:(fun i _ -> i <> 1 && i <> 2))

let notation = "Notation \"x '+++' y\" := (x + y) (at level 50). Check 1. Check (1 +++ 2)."

(* Sentences after a grammar change that is no longer there parse differently,
   also when they are not in the edited range. *)
let%test_unit "oracle: delete a notation" =
  check_same_as_fresh (edit_one_by_one ~text:notation [0, 47, ""])

let%test_unit "oracle: break a notation" =
  check_same_as_fresh (edit_one_by_one ~text:notation [7, 8, ""])

(* The edit removes the blank before "Check 2", where that sentence's parsing
   starts, and there is nothing to parse before it. *)
let%test_unit "oracle: delete the first sentence and the blank after it" =
  check_same_as_fresh (edit_one_by_one ~text:five [0, 9, ""])

(* The notation is not the first sentence touched by the edit. *)
let%test_unit "oracle: delete a sentence and the notation after it" =
  check_same_as_fresh (edit_one_by_one ~text:("Check 0. " ^ notation) [0, 56, ""])
