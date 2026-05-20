open Lsp.Types

type region_type =
  | ProofRegion
  | SectionRegion
  | ModuleRegion

type entry = {
  range: Range.t;
  kind: FoldingRangeKind.t option;
  children: entry list;
}

type open_region = {
  name: string option;
  region_type: region_type;
  start: Position.t option;
  kind: FoldingRangeKind.t option;
  children: entry list;
}

type state = {
  stack: open_region list;
  top: entry list;
}

let empty_state = { stack = []; top = [] }

let range_spans_lines (range: Range.t) =
  range.start.line < range.end_.line

let make_entry ?(kind = Some FoldingRangeKind.Region) ?(children = []) (range: Range.t) =
  if range_spans_lines range then Some { range; kind; children } else None

let entry_of_loc raw loc =
  make_entry (RawDocument.range_of_loc raw loc)

let entry_of_sentence document (sentence: Document.sentence) =
  make_entry (Document.range_of_id document sentence.id)

let add_entry state entry =
  match state.stack with
  | [] -> { state with top = entry :: state.top }
  | region :: stack ->
    { state with stack = { region with children = entry :: region.children } :: stack }

let add_entries state entries =
  List.fold_left add_entry state entries

let open_region state region =
  { state with stack = region :: state.stack }

let close_top_region state pred end_ =
  match state.stack with
  | { start = Some start; _ } as region :: stack when pred region ->
    let entry = { range = { start; end_ }; kind = region.kind; children = List.rev region.children } in
    add_entry { state with stack } entry
  | region :: stack when pred region ->
    { state with stack }
  | _ -> state

let begin_proof state start =
  let rec aux seen = function
    | [] -> state.stack
    | { region_type = ProofRegion; start = None; _ } as region :: rest ->
      List.rev_append seen ({ region with start = Some start } :: rest)
    | region :: rest -> aux (region :: seen) rest
  in
  { state with stack = aux [] state.stack }

let close_proof state end_ =
  close_top_region state (fun region -> region.region_type = ProofRegion) end_

let close_segment state name end_ =
  close_top_region state (fun region ->
    match region.name with
    | Some region_name -> region_name = name
    | None -> false
  ) end_

let open_segment document (sentence: Document.sentence) lident region_type state =
  let range = Document.range_of_id document sentence.id in
  let name = Names.Id.to_string lident.CAst.v in
  open_region state { name = Some name; region_type; start = Some range.start; kind = Some FoldingRangeKind.Region; children = [] }

let open_proof _document (_sentence: Document.sentence) state =
  open_region state { name = None; region_type = ProofRegion; start = None; kind = Some FoldingRangeKind.Region; children = [] }

let loc_entries_of_constr raw (e: Constrexpr.constr_expr) =
  match e.CAst.loc with
  | None -> []
  | Some loc ->
    match entry_of_loc raw loc with
    | None -> []
    | Some entry -> [entry]

let rec entries_of_constr raw (e: Constrexpr.constr_expr) =
  let open Constrexpr in
  let self = entries_of_constr raw in
  let self_opt = function None -> [] | Some e -> self e in
  let entries_of_binders binders =
    List.concat_map (function
      | CLocalAssum (_, _, _, ty) -> self ty
      | CLocalDef (_, _, e, e_opt) -> self e @ self_opt e_opt
      | CLocalPattern _ -> []
    ) binders
  in
  let nested =
    match e.CAst.v with
    | CRef _ | CHole _ | CPatVar _ | CEvar _ | CSort _ | CPrim _
    | CGenarg _ | CGenargGlob _ -> []
    | CNotation (_, _, (terms, recursive_terms, _, recursive_binders)) ->
      List.concat_map self terms
      @ List.concat_map (List.concat_map self) recursive_terms
      @ List.concat_map entries_of_binders recursive_binders
    | CFix (_, fixes) ->
      List.concat_map (fun (_name, _rel, _order, binders, rtype, body) ->
        entries_of_binders binders @ self rtype @ self body
      ) fixes
    | CCoFix (_, cofixes) ->
      List.concat_map (fun (_name, _rel, binders, rtype, body) ->
        entries_of_binders binders @ self rtype @ self body
      ) cofixes
    | CProdN (binders, body) | CLambdaN (binders, body) ->
      entries_of_binders binders @ self body
    | CLetIn (_, e1, e2_opt, e3) ->
      self e1 @ self_opt e2_opt @ self e3
    | CAppExpl (_, args) -> List.concat_map self args
    | CApp (fn, args) -> self fn @ List.concat_map (fun (arg, _) -> self arg) args
    | CProj (_, _, args, e) ->
      List.concat_map (fun (arg, _) -> self arg) args @ self e
    | CRecord fields -> List.concat_map (fun (_, e) -> self e) fields
    | CCases (_style, ret, scrutinees, branches) ->
      self_opt ret
      @ List.concat_map (fun (e, _, _) -> self e) scrutinees
      @ List.concat_map (fun (branch: branch_expr) -> let (_pats, body) = branch.CAst.v in self body) branches
    | CLetTuple (_, _, e1, e2) -> self e1 @ self e2
    | CIf (cond, (_, ret_opt), then_br, else_br) ->
      self cond @ self_opt ret_opt @ self then_br @ self else_br
    | CCast (e1, _, e2) -> self e1 @ self e2
    | CGeneralization (_, e) | CDelimiters (_, _, e) -> self e
    | CArray (_, elems, _, default) ->
      List.concat_map self (Array.to_list elems) @ self default
  in
  let own =
    match e.CAst.v with
    | CCases _ | CIf _ | CLambdaN _ | CLetIn _ -> loc_entries_of_constr raw e
    | _ -> []
  in
  own @ nested

let entries_of_constr_opt raw = function
  | None -> []
  | Some e -> entries_of_constr raw e

let entries_of_binders raw binders =
  let open Constrexpr in
  List.concat_map (function
    | CLocalAssum (_, _, _, ty) -> entries_of_constr raw ty
    | CLocalDef (_, _, e, e_opt) -> entries_of_constr raw e @ entries_of_constr_opt raw e_opt
    | CLocalPattern _ -> []
  ) binders

let entry_of_constr_loc raw e =
  match e.CAst.loc with
  | None -> []
  | Some loc ->
    match entry_of_loc raw loc with
    | None -> []
    | Some entry -> [entry]

let option_to_list = function
  | None -> []
  | Some x -> [x]

let entries_of_local_decl raw = function
  | Vernacexpr.AssumExpr (_, binders, ty) ->
    entries_of_binders raw binders @ entry_of_constr_loc raw ty @ entries_of_constr raw ty
  | Vernacexpr.DefExpr (_, binders, body, ty_opt) ->
    entries_of_binders raw binders
    @ entry_of_constr_loc raw body @ entries_of_constr raw body
    @ entries_of_constr_opt raw ty_opt

let entries_of_inductive raw (((_coercion, (_name, _univs)), (params, extra_params), rtype, ctors), _notations) =
  let param_entries = entries_of_binders raw params in
  let extra_param_entries = Option.cata (entries_of_binders raw) [] extra_params in
  let rtype_entries = entries_of_constr_opt raw rtype in
  let ctor_entries =
    match ctors with
    | Vernacexpr.Constructors constructors ->
      List.concat_map (fun (_, (_name, ty)) -> entry_of_constr_loc raw ty @ entries_of_constr raw ty) constructors
    | Vernacexpr.RecordDecl (_, fields, _) ->
      List.concat_map (fun (decl, _attrs) -> entries_of_local_decl raw decl) fields
  in
  param_entries @ extra_param_entries @ rtype_entries @ ctor_entries

let entries_of_vernac_ast raw (ast: Synterp.vernac_control_entry) =
  match ast.v.expr with
  | Vernacexpr.VernacSynPure pure ->
    begin match pure with
    | Vernacexpr.VernacDefinition (_, _, body) ->
      begin match body with
      | Vernacexpr.ProveBody (binders, ty) ->
        entries_of_binders raw binders @ entry_of_constr_loc raw ty @ entries_of_constr raw ty
      | Vernacexpr.DefineBody (binders, _, body, rest) ->
        entries_of_binders raw binders
        @ entry_of_constr_loc raw body @ entries_of_constr raw body
        @ entries_of_constr_opt raw rest
      end
    | Vernacexpr.VernacStartTheoremProof (_, proofs) ->
      List.concat_map (fun (_name_decl, (binders, ty)) ->
        entries_of_binders raw binders @ entry_of_constr_loc raw ty @ entries_of_constr raw ty
      ) proofs
    | Vernacexpr.VernacFixpoint (_, (_, fixes)) ->
      List.concat_map (fun fix ->
        entries_of_binders raw fix.Vernacexpr.binders
        @ entry_of_constr_loc raw fix.Vernacexpr.rtype
        @ entries_of_constr raw fix.Vernacexpr.rtype
        @ entries_of_constr_opt raw fix.Vernacexpr.body_def
      ) fixes
    | Vernacexpr.VernacCoFixpoint (_, cofixes) ->
      List.concat_map (fun cofix ->
        entries_of_binders raw cofix.Vernacexpr.binders
        @ entry_of_constr_loc raw cofix.Vernacexpr.rtype
        @ entries_of_constr raw cofix.Vernacexpr.rtype
        @ entries_of_constr_opt raw cofix.Vernacexpr.body_def
      ) cofixes
    | Vernacexpr.VernacInductive (_, inds) ->
      List.concat_map (entries_of_inductive raw) inds
    | _ -> []
    end
  | _ -> []

let count_indent s =
  let rec loop i =
    if i >= String.length s then None
    else match s.[i] with
      | ' ' -> loop (i + 1)
      | '\t' -> loop (i + 2)
      | '\r' | '\n' -> None
      | _ -> Some i
  in
  loop 0

let indentation_entries_of_sentence document (sentence: Document.sentence) =
  let raw = Document.raw_document document in
  let text = RawDocument.string_in_range raw sentence.start sentence.stop in
  let lines = String.split_on_char '\n' text in
  let rec with_offsets offset = function
    | [] -> []
    | line :: rest ->
      let start = sentence.start + offset in
      let stop = start + String.length line in
      (line, start, stop) :: with_offsets (offset + String.length line + 1) rest
  in
  let lines = with_offsets 0 lines in
  let base_indent =
    lines
    |> List.find_map (fun (line, _, _) -> count_indent line)
    |> Option.cata (fun indent -> indent) 0
  in
  let flush_run acc = function
    | [] | [_] -> acc
    | run ->
      let rev_run = List.rev run in
      let (_, start, _) = List.hd rev_run in
      let (_, _, stop) = List.hd run in
      let range: Range.t = { start = RawDocument.position_of_loc raw start; end_ = RawDocument.position_of_loc raw stop } in
      begin match make_entry range with
      | None -> acc
      | Some entry -> entry :: acc
      end
  in
  let rec loop acc run = function
    | [] -> flush_run acc run
    | (line, start, stop) :: rest ->
      match count_indent line with
      | Some indent when indent > base_indent -> loop acc ((line, start, stop) :: run) rest
      | _ -> loop (flush_run acc run) [] rest
  in
  loop [] [] lines

let sentence_entries_of_ast document sentence (ast: Synterp.vernac_control_entry) =
  match ast.v.expr with
  | Vernacexpr.VernacSynterp (Synterp.EVernacRequire _)
  | Vernacexpr.VernacSynterp (Synterp.EVernacNotation _) ->
    option_to_list (entry_of_sentence document sentence)
  | Vernacexpr.VernacSynterp (Synterp.EVernacExtend _) ->
    option_to_list (entry_of_sentence document sentence) @ indentation_entries_of_sentence document sentence
  | _ -> []

let apply_classification document (sentence: Document.sentence) (p_ast: Document.parsed_ast) state =
  let open Vernacextend in
  let ast = p_ast.ast in
  match p_ast.classification with
  | VtProofStep _ ->
    let range = Document.range_of_id document sentence.id in
    begin_proof state range.start
  | VtQed _ ->
    let range = Document.range_of_id document sentence.id in
    close_proof state range.start
  | VtStartProof _ ->
    open_proof document sentence state
  | VtSideff _ ->
    begin match ast.v.expr with
    | Vernacexpr.VernacSynterp (Synterp.EVernacBeginSection lident) ->
      open_segment document sentence lident SectionRegion state
    | Vernacexpr.VernacSynterp (Synterp.EVernacDeclareModuleType (lident, _, _, _, _)) ->
      open_segment document sentence lident ModuleRegion state
    | Vernacexpr.VernacSynterp (Synterp.EVernacDefineModule (_, lident, _, _, _, _)) ->
      open_segment document sentence lident ModuleRegion state
    | Vernacexpr.VernacSynterp (Synterp.EVernacDeclareModule (_, lident, _, _)) ->
      open_segment document sentence lident ModuleRegion state
    | Vernacexpr.VernacSynterp (Synterp.EVernacEndSegment lident) ->
      let range = Document.range_of_id document sentence.id in
      close_segment state (Names.Id.to_string lident.CAst.v) range.end_
    | _ -> state
    end
  | _ -> state

let add_ast_entries document (sentence: Document.sentence) (p_ast: Document.parsed_ast) state =
  let raw = Document.raw_document document in
  let entries = entries_of_vernac_ast raw p_ast.ast @ sentence_entries_of_ast document sentence p_ast.ast in
  add_entries state entries

let comment_entries document =
  let raw = Document.raw_document document in
  Document.comments document
  |> List.filter_map (fun (comment: Document.comment) ->
    let range: Range.t = { start = RawDocument.position_of_loc raw comment.start; end_ = RawDocument.position_of_loc raw comment.stop } in
    make_entry ~kind:(Some FoldingRangeKind.Comment) range)

let rec flatten_entry (entry: entry) =
  entry :: List.concat_map flatten_entry entry.children

let compare_range (a: entry) (b: entry) =
  let c = Int.compare a.range.start.line b.range.start.line in
  if c <> 0 then c else
  let c = Int.compare a.range.start.character b.range.start.character in
  if c <> 0 then c else
  let c = Int.compare a.range.end_.line b.range.end_.line in
  if c <> 0 then c else
  Int.compare a.range.end_.character b.range.end_.character

let same_range (a: entry) (b: entry) =
  a.range = b.range && a.kind = b.kind

let sort_dedup_filter entries =
  entries
  |> List.concat_map flatten_entry
  |> List.filter (fun entry -> range_spans_lines entry.range)
  |> List.sort compare_range
  |> List.fold_left (fun acc entry ->
    match acc with
    | last :: _ when same_range last entry -> acc
    | _ -> entry :: acc
  ) []
  |> List.rev

let to_lsp (entry: entry) =
  let startLine = entry.range.start.line in
  let startCharacter = entry.range.start.character in
  let endLine = entry.range.end_.line in
  let endCharacter = entry.range.end_.character in
  FoldingRange.create ~startLine ~startCharacter ~endLine ~endCharacter ?kind:entry.kind ()

let folding_ranges document =
  let state =
    List.fold_left (fun state (sentence: Document.sentence) ->
      match sentence.ast with
      | Error _ -> state
      | Parsed ast ->
        state
        |> apply_classification document sentence ast
        |> add_ast_entries document sentence ast
    ) empty_state (Document.sentences_sorted_by_loc document)
  in
  let entries = List.rev state.top @ comment_entries document in
  List.map to_lsp (sort_dedup_filter entries)
