(** Computes LSP folding ranges for parsed Rocq documents from sentence-level
    regions, located Gallina subexpressions, indentation fallback ranges, and
    recorded comments.
*)

open Lsp.Types

(** Classifies stack-managed regions whose end is discovered by a later
    vernacular sentence. *)
type region_type =
  | ProofRegion
  | SectionRegion
  | ModuleRegion
  | BulletRegion of Proof_bullet.t * int
  | SubproofRegion

(** Internal classification (later projected to LSP specific classifications) *)
type entry_kind =
  | Proof
  | Section
  | Module
  | Theorem
  | Definition
  | Inductive
  | External
  | Comment
  | ConstrSubexpression
  | Indentation

type outline_info = {
  outline_name: string;
  detail: string option;
  selection_range: Range.t;
}

(** Internal folding and outline entry tree *)
type entry = {
  entry_kind: entry_kind;
  close_name: string option;
  outline_info: outline_info option;
  range: Range.t;
  children: entry list;
}

(** Region currently open in the sentence traversal.  Proof regions start with
    no [start] and are claimed by the first proof step. *)
type open_region = {
  entry_kind: entry_kind;
  close_name: string option;
  outline_info: outline_info option;
  region_type: region_type;
  start: Position.t option;
  children: entry list;
}

(** Accumulator for the sentence traversal.  [stack] contains currently open
    regions with the innermost region first; entries discovered while a region
    is open are accumulated in that region's [children].  [top] contains closed
    top-level entries in reverse source order. *)
type state = {
  stack: open_region list;
  top: entry list;
}

let init_entry_state : state = { stack = []; top = [] }

let make_entry ?close_name ?outline_info ?(children: entry list = []) entry_kind (range: Range.t) : entry =
  { entry_kind; close_name; outline_info; range; children }

let entry_of_loc (raw: RawDocument.t) loc : entry option =
  Some (make_entry ConstrSubexpression (RawDocument.range_of_loc raw loc))

let entry_of_sentence ?(entry_kind = Indentation) (document: Document.document) (sentence: Document.sentence) : entry option =
  Some (make_entry entry_kind (Document.range_of_id document sentence.id))

let add_entry (state: state) (entry: entry) : state =
  match state.stack with
  | [] -> { state with top = entry :: state.top }
  | region :: stack ->
    { state with stack = { region with children = entry :: region.children } :: stack }

let add_entries (state: state) (entries: entry list) : state =
  List.fold_left add_entry state entries

let open_region (state: state) (region: open_region) : state =
  { state with stack = region :: state.stack }

let end_of_previous_line (raw: RawDocument.t) (position: Position.t) : Position.t =
  if position.line = 0 then position
  else
    let line_start = RawDocument.loc_of_position raw { line = position.line; character = 0 } in
    RawDocument.position_of_loc raw (line_start - 1)

(** Closes the first open region when it matches [pred], attaching its collected
    children to the emitted entry. *)
let close_top_region (state: state) (pred: open_region -> bool) (end_: Position.t) : state =
  match state.stack with
  | { start = Some start; _ } as region :: stack when pred region ->
    let entry = {
      entry_kind = region.entry_kind;
      close_name = region.close_name;
      outline_info = region.outline_info;
      range = { start; end_ };
      children = List.rev region.children;
    } in
    add_entry { state with stack } entry
  | region :: stack when pred region ->
    { state with stack }
  | _ -> state

(** Marks the first pending proof region as starting at the first proof command. *)
let begin_proof (state: state) (start: Position.t) : state =
  let rec aux seen = function
    | [] -> state.stack
    | { region_type = ProofRegion; start = None; _ } as region :: rest ->
      List.rev_append seen ({ region with start = Some start } :: rest)
    | region :: rest -> aux (region :: seen) rest
  in
  { state with stack = aux [] state.stack }

let close_proof (state: state) (end_: Position.t) : state =
  close_top_region state (fun region -> region.region_type = ProofRegion) end_

let close_bullet (state: state) (end_: Position.t) : state =
  close_top_region state (function
    | { region_type = BulletRegion _; _ } -> true
    | _ -> false
  ) end_

let close_subproof (state: state) (end_: Position.t) : state =
  close_top_region state (function
    | { region_type = SubproofRegion; _ } -> true
    | _ -> false
  ) end_

let close_proof_subregions (raw: RawDocument.t) (state: state) (end_: Position.t) : state =
  let excluded_end = end_of_previous_line raw end_ in
  let rec loop state =
    match state.stack with
    | { region_type = BulletRegion _; _ } :: _ ->
      loop (close_bullet state excluded_end)
    | { region_type = SubproofRegion; _ } :: _ ->
      loop (close_subproof state excluded_end)
    | _ -> state
  in
  loop state

let rec close_subproof_region (raw: RawDocument.t) (state: state) (end_: Position.t) : state =
  match state.stack with
  | { region_type = BulletRegion _; _ } :: _ ->
    close_subproof_region raw (close_bullet state (end_of_previous_line raw end_)) end_
  | { region_type = SubproofRegion; _ } :: _ ->
    close_subproof state end_
  | _ -> state

let rec close_bullet_regions_for (raw: RawDocument.t) (bullet: Proof_bullet.t) (indent: int) (state: state) (end_: Position.t) : state =
  let excluded_end = end_of_previous_line raw end_ in
  match state.stack with
  | { region_type = BulletRegion (_, open_indent); _ } :: _ when open_indent > indent ->
    close_bullet_regions_for raw bullet indent (close_bullet state excluded_end) end_
  | { region_type = BulletRegion (open_bullet, open_indent); _ } :: _
      when open_indent = indent && Stdlib.(=) open_bullet bullet ->
    close_bullet_regions_for raw bullet indent (close_bullet state excluded_end) end_
  | _ -> state

let close_segment (state: state) (name: string) (end_: Position.t) : state =
  close_top_region state (fun region ->
    match region.close_name with
    | Some region_name -> region_name = name
    | None -> false
  ) end_

let finalize_open_regions (state: state) (end_: Position.t) : state =
  let rec loop state =
    match state.stack with
    | [] -> state
    | ({ start = Some start; _ } as region) :: stack ->
      let entry = {
        entry_kind = region.entry_kind;
        close_name = region.close_name;
        outline_info = region.outline_info;
        range = { start; end_ };
        children = List.rev region.children;
      } in
      loop (add_entry { state with stack } entry)
    | _ :: stack ->
      loop { state with stack }
  in
  loop state

let name_of_variables : Names.variable list -> string option = function
  | [] -> None
  | name :: _ -> Some (Names.Id.to_string name)

let names_or_default names =
  match names with
  | [] -> ["default"]
  | _ -> List.map Names.Id.to_string names

let declaration_entries (document: Document.document) (sentence: Document.sentence) entry_kind names : entry list =
  let range = Document.range_of_id document sentence.id in
  let raw = Document.raw_document document in
  let detail = RawDocument.string_in_range raw sentence.start sentence.stop in
  names_or_default names
  |> List.map (fun name ->
    let outline_info = { outline_name = name; detail = Some detail; selection_range = range } in
    make_entry ~outline_info entry_kind range)

(** Opens a named section/module region at the sentence start. *)
let open_segment (document: Document.document) (sentence: Document.sentence) (lident: Names.lident) (region_type: region_type) (state: state) : state =
  let range = Document.range_of_id document sentence.id in
  let name = Names.Id.to_string lident.CAst.v in
  let entry_kind = match region_type with
    | SectionRegion -> Section
    | ModuleRegion -> Module
    | _ -> assert false
  in
  let outline_info = { outline_name = name; detail = Some ""; selection_range = range } in
  open_region state { entry_kind; close_name = Some name; outline_info = Some outline_info; region_type; start = Some range.start; children = [] }

(** Opens a proof region whose start will be set by the first proof command. *)
let open_proof (names: Names.variable list) (state: state) : state =
  open_region state { entry_kind = Proof; close_name = name_of_variables names; outline_info = None; region_type = ProofRegion; start = None; children = [] }

let open_bullet_region (bullet: Proof_bullet.t) (indent: int) (start: Position.t) (state: state) : state =
  open_region state { entry_kind = Proof; close_name = None; outline_info = None; region_type = BulletRegion (bullet, indent); start = Some start; children = [] }

let open_subproof_region (start: Position.t) (state: state) : state =
  open_region state { entry_kind = Proof; close_name = None; outline_info = None; region_type = SubproofRegion; start = Some start; children = [] }

type proof_delimiter =
  | ProofBullet of Proof_bullet.t
  | ProofSubproofStart
  | ProofSubproofEnd

let proof_delimiter_of_ast (ast: Synterp.vernac_control_entry) : proof_delimiter option =
  match ast.v.expr with
  | Vernacexpr.VernacSynPure (Vernacexpr.VernacBullet bullet) -> Some (ProofBullet bullet)
  | Vernacexpr.VernacSynPure (Vernacexpr.VernacSubproof _) -> Some ProofSubproofStart
  | Vernacexpr.VernacSynPure Vernacexpr.VernacEndSubproof -> Some ProofSubproofEnd
  | _ -> None

let loc_entries_of_constr (raw: RawDocument.t) (e: Constrexpr.constr_expr) : entry list =
  match e.CAst.loc with
  | None -> []
  | Some loc ->
    match entry_of_loc raw loc with
    | None -> []
    | Some entry -> [entry]

let entries_of_whole_constr (raw: RawDocument.t) (e: Constrexpr.constr_expr) : entry list =
  loc_entries_of_constr raw e

(** Extracts folding entries from selected Gallina subexpressions that are useful
    fold points. *)
let entries_of_constr (raw: RawDocument.t) (e: Constrexpr.constr_expr) : entry list =
  let open Constrexpr in
  Utilities.fold_constr (fun entries e ->
    match e.CAst.v with
    | CCases _ | CIf _ | CLambdaN _ | CLetIn _ ->
      List.rev_append (loc_entries_of_constr raw e) entries
    | _ -> entries
  ) [] e
  |> List.rev

let entries_of_constr_opt (raw: RawDocument.t) : Constrexpr.constr_expr option -> entry list = function
  | None -> []
  | Some e -> entries_of_constr raw e

let entries_of_binders (raw: RawDocument.t) binders : entry list =
  binders
  |> List.concat_map Utilities.constrs_of_local_binder
  |> List.concat_map (entries_of_constr raw)

let count_indent (s: string) : int option =
  let rec loop i =
    if i >= String.length s then None
    else match s.[i] with
      | ' ' -> loop (i + 1)
      | '\t' -> loop (i + 2)
      | '\r' | '\n' -> None
      | _ -> Some i
  in
  loop 0

(** Uses indentation runs as a fallback for extension sentences whose AST does
    not expose more precise foldable structure. *)
let indentation_entries_of_sentence (document: Document.document) (sentence: Document.sentence) : entry list =
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
      make_entry Indentation range :: acc
  in
  let rec loop acc run = function
    | [] -> flush_run acc run
    | (line, start, stop) :: rest ->
      match count_indent line with
      | Some indent when indent > base_indent -> loop acc ((line, start, stop) :: run) rest
      | _ -> loop (flush_run acc run) [] rest
  in
  loop [] [] lines

(** Extracts folds from a record field or local definition declaration. *)
let entries_of_local_decl (raw: RawDocument.t) : _ -> entry list = function
  | Vernacexpr.AssumExpr (_, binders, ty) ->
    entries_of_binders raw binders @ entries_of_constr raw ty
  | Vernacexpr.DefExpr (_, binders, body, ty_opt) ->
    entries_of_binders raw binders
    @ entries_of_constr raw body
    @ entries_of_constr_opt raw ty_opt

(** Extracts folds from an inductive body, including constructor types and
    record fields. *)
let entries_of_inductive (raw: RawDocument.t) (((_coercion, (_name, _univs)), (params, extra_params), rtype, ctors), _notations) : entry list =
  let param_entries = entries_of_binders raw params in
  let extra_param_entries = Option.cata (entries_of_binders raw) [] extra_params in
  let rtype_entries = entries_of_constr_opt raw rtype in
  let ctor_entries =
    match ctors with
    | Vernacexpr.Constructors constructors ->
      List.concat_map (fun (_, (_name, ty)) ->
        entries_of_whole_constr raw ty @ entries_of_constr raw ty
      ) constructors
    | Vernacexpr.RecordDecl (_, fields, _) ->
      List.concat_map (fun (decl, _attrs) -> entries_of_local_decl raw decl) fields
  in
  param_entries @ extra_param_entries @ rtype_entries @ ctor_entries

let entries_of_recursive_defs raw defs =
  List.concat_map (fun def ->
    entries_of_binders raw def.Vernacexpr.binders
    @ entries_of_constr raw def.Vernacexpr.rtype
    @ entries_of_constr_opt raw def.Vernacexpr.body_def
  ) defs

[%%if rocq = "8.18" || rocq = "8.19" || rocq = "8.20"]
let entries_of_fixpoint raw = function
  | Vernacexpr.VernacFixpoint (_, fixes) -> entries_of_recursive_defs raw fixes
  | _ -> []
[%%else]
let entries_of_fixpoint raw = function
  | Vernacexpr.VernacFixpoint (_, (_, fixes)) -> entries_of_recursive_defs raw fixes
  | _ -> []
[%%endif]

(** Extracts sub-sentence Gallina folds from vernacular AST nodes that contain
    located terms. *)
let entries_of_vernac_ast (document: Document.document) (sentence: Document.sentence) (ast: Synterp.vernac_control_entry) : entry list =
  let raw = Document.raw_document document in
  match ast.v.expr with
  | Vernacexpr.VernacSynPure pure ->
    begin match pure with
    | Vernacexpr.VernacDefinition (_, _, body) ->
      begin match body with
      | Vernacexpr.ProveBody (binders, ty) ->
        entries_of_binders raw binders
        @ entries_of_constr raw ty
      | Vernacexpr.DefineBody (binders, _, body, rest) ->
        entries_of_binders raw binders
        @ entries_of_constr raw body
        @ entries_of_constr_opt raw rest
      end
    | Vernacexpr.VernacStartTheoremProof (_, proofs) ->
      List.concat_map (fun (_name_decl, (binders, ty)) ->
        entries_of_binders raw binders
        @ entries_of_whole_constr raw ty
        @ entries_of_constr raw ty
      ) proofs
    | Vernacexpr.VernacFixpoint _ as pure ->
      entries_of_fixpoint raw pure
    | Vernacexpr.VernacCoFixpoint (_, cofixes) ->
      entries_of_recursive_defs raw cofixes
    | Vernacexpr.VernacInductive (_, inds) ->
      List.concat_map (entries_of_inductive raw) inds
      @ Utilities.option_to_list (entry_of_sentence document sentence)
    | _ -> []
    end
  | Vernacexpr.VernacSynterp (Synterp.EVernacRequire _)
  | Vernacexpr.VernacSynterp (Synterp.EVernacNotation _) ->
    Utilities.option_to_list (entry_of_sentence document sentence)
  | Vernacexpr.VernacSynterp (Synterp.EVernacExtend _) ->
    indentation_entries_of_sentence document sentence
  | _ -> []

(** Adds whole-sentence folds *)
let full_sentence_entry (document: Document.document) (sentence: Document.sentence) (ast: Synterp.vernac_control_entry) : entry list =
  match ast.v.expr with
  | Vernacexpr.VernacSynterp (Synterp.EVernacExtend _) ->
    Utilities.option_to_list (entry_of_sentence document sentence)
    @ indentation_entries_of_sentence document sentence
  | _ -> []

let declaration_entries_of_classification (document: Document.document) (sentence: Document.sentence) (p_ast: Document.parsed_ast) : entry list =
  let open Vernacextend in
  match p_ast.classification with
  | VtStartProof (_, names) ->
    begin match p_ast.ast.v.expr with
    | Vernacexpr.VernacSynPure (Vernacexpr.VernacStartTheoremProof _) ->
      declaration_entries document sentence Theorem names
    | Vernacexpr.VernacSynPure (Vernacexpr.VernacDefinition _)
    | Vernacexpr.VernacSynPure (Vernacexpr.VernacFixpoint _)
    | Vernacexpr.VernacSynPure (Vernacexpr.VernacCoFixpoint _) ->
      declaration_entries document sentence Definition names
    | _ -> []
    end
  | VtSideff (names, _) ->
    begin match p_ast.ast.v.expr with
    | Vernacexpr.VernacSynterp (Synterp.EVernacExtend _) when names <> [] ->
      declaration_entries document sentence External names
    | Vernacexpr.VernacSynPure (Vernacexpr.VernacStartTheoremProof _) ->
      declaration_entries document sentence Theorem names
    | Vernacexpr.VernacSynPure (Vernacexpr.VernacDefinition _)
    | Vernacexpr.VernacSynPure (Vernacexpr.VernacFixpoint _)
    | Vernacexpr.VernacSynPure (Vernacexpr.VernacCoFixpoint _) ->
      declaration_entries document sentence Definition names
    | Vernacexpr.VernacSynPure (Vernacexpr.VernacInductive _) ->
      declaration_entries document sentence Inductive names
    | _ -> []
    end
  | _ -> []

(** Updates the open-region stack according to Rocq's vernacular
    classification for sections, modules, and proofs. *)
let apply_classification (document: Document.document) (sentence: Document.sentence) (p_ast: Document.parsed_ast) (state: state) : state =
  let open Vernacextend in
  let raw = Document.raw_document document in
  let ast = p_ast.ast in
  match p_ast.classification with
  | VtProofStep _ ->
    let range = Document.range_of_id document sentence.id in
    let state = begin_proof state range.start in
    begin match proof_delimiter_of_ast ast with
    | Some (ProofBullet bullet) ->
      let state = close_bullet_regions_for raw bullet range.start.character state range.start in
      open_bullet_region bullet range.start.character range.start state
    | Some ProofSubproofStart ->
      open_subproof_region range.start state
    | Some ProofSubproofEnd ->
      close_subproof_region raw state range.start
    | None -> state
    end
  | VtQed _ ->
    let range = Document.range_of_id document sentence.id in
    let state = close_proof_subregions raw state range.start in
    close_proof state range.start
  | VtStartProof (_, names) ->
    open_proof names state
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

(** Adds entries discovered from the current parsed AST to the current open
    region or to the top level. *)
let add_ast_entries (document: Document.document) (sentence: Document.sentence) (p_ast: Document.parsed_ast) (state: state) : state =
  let entries = entries_of_vernac_ast document sentence p_ast.ast
    @ full_sentence_entry document sentence p_ast.ast
    @ declaration_entries_of_classification document sentence p_ast in
  add_entries state entries

(** Converts recorded multi-line comments into entries. *)
let comment_entries (document: Document.document) : entry list =
  let raw = Document.raw_document document in
  Document.comments document
  |> List.filter_map (fun (comment: Document.comment) ->
    let range: Range.t = { start = RawDocument.position_of_loc raw comment.start; end_ = RawDocument.position_of_loc raw comment.stop } in
    Some (make_entry Comment range))

(** Get the structured outline of the documents *)
let document_entries (document: Document.document) : entry list =
  let state =
    List.fold_left (fun state (sentence: Document.sentence) ->
      match sentence.ast with
      | Error _ -> state
      | Parsed ast ->
        state
        |> apply_classification document sentence ast
        |> add_ast_entries document sentence ast
    ) init_entry_state (Document.sentences_sorted_by_loc document)
  in
  let raw = Document.raw_document document in
  let eof = RawDocument.position_of_loc raw (RawDocument.end_loc raw) in
  let state = finalize_open_regions state eof in
  let entries = List.rev state.top
    @ comment_entries document in
  entries

let folding_kind_of_entry_kind = function
  | Comment -> Some FoldingRangeKind.Comment
  | Proof | Section | Module | Theorem | Definition | Inductive | External | ConstrSubexpression | Indentation -> Some FoldingRangeKind.Region

let symbol_kind_of_entry_kind = function
  | Proof | Theorem -> Some SymbolKind.Function
  | Definition -> Some SymbolKind.Variable
  | Inductive -> Some SymbolKind.Struct
  | Section | Module -> Some SymbolKind.Class
  | External -> Some SymbolKind.Null
  | Comment | ConstrSubexpression | Indentation -> None

let range_spans_lines (range: Range.t) : bool =
  range.start.line < range.end_.line

let rec flatten_entry (entry: entry) : entry list =
  entry :: List.concat_map flatten_entry entry.children

let compare_range (a: entry) (b: entry) : int =
  let c = Int.compare a.range.start.line b.range.start.line in
  if c <> 0 then c else
  let c = Int.compare a.range.start.character b.range.start.character in
  if c <> 0 then c else
  let c = Int.compare a.range.end_.line b.range.end_.line in
  if c <> 0 then c else
  Int.compare a.range.end_.character b.range.end_.character

let range_eq (a: entry) (b: entry) : bool =
  a.range = b.range && folding_kind_of_entry_kind a.entry_kind = folding_kind_of_entry_kind b.entry_kind

(** Normalizes collected entries by flattening nesting, removing single-line
    ranges, sorting by source order, and dropping exact duplicates. *)
let normalize_entries (entries: entry list) : entry list =
  entries
  |> List.concat_map flatten_entry
  |> List.filter (fun entry -> range_spans_lines entry.range)
  |> List.sort compare_range
  |> List.fold_left (fun acc entry ->
    match acc with
    | last :: _ when range_eq last entry -> acc
    | _ -> entry :: acc
  ) []
  |> List.rev

(** Convert entry to an LSP folding range *)
let folding_range_of_entry (entry: entry) : FoldingRange.t =
  let startLine = entry.range.start.line in
  let startCharacter = entry.range.start.character in
  let endLine = entry.range.end_.line in
  let endCharacter = entry.range.end_.character in
  let kind = folding_kind_of_entry_kind entry.entry_kind in
  FoldingRange.create ~startLine ~startCharacter ~endLine ~endCharacter ?kind ()

let rec document_symbols_of_entry (entry: entry) : DocumentSymbol.t list =
  let children = List.concat_map document_symbols_of_entry entry.children in
  match entry.outline_info, symbol_kind_of_entry_kind entry.entry_kind with
  | Some outline_info, Some kind ->
    let children = match children with
      | [] -> None
      | _ -> Some children
    in
    [DocumentSymbol.{
      name = outline_info.outline_name;
      detail = outline_info.detail;
      kind;
      range = entry.range;
      selectionRange = outline_info.selection_range;
      children;
      deprecated = None;
      tags = None;
    }]
  | _ -> children

(** Computes all LSP folding ranges for a parsed document. *)
let folding_ranges (document: Document.document) : FoldingRange.t list =
  List.map folding_range_of_entry (normalize_entries (document_entries document))

(** Computes document symbols from the folding entry tree. *)
let document_symbols (document: Document.document) : DocumentSymbol.t list =
  document_entries document
  |> List.concat_map document_symbols_of_entry
