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
open Gramlib
open Types
open Lsp.Types
open Scheduler

let Log log = Log.mk_log "document"

module LM = Map.Make (Int)

module SM = Map.Make (Stateid)

type proof_block_type =
  | TheoremKind
  | DefinitionType
  | InductiveType
  | BeginSection
  | BeginModule
  | End
  | Other

type proof_step = {
  id: sentence_id;
  tactic: string;
  range: Range.t;
}

type outline_element = {
  id: sentence_id;
  name: string;
  type_: proof_block_type;
  statement: string;
  proof: proof_step list;
  range: Range.t
}

type outline = outline_element list

type parsed_ast = {
  ast: Synterp.vernac_control_entry;
  classification: Vernacextend.vernac_classification;
  tokens: Tok.t list
}

type comment = {
  start: int;
  stop: int;
  content: string;
}

type parsing_error = {
  start: int;
  stop: int;
  msg: Pp.t Loc.located;
  qf: Quickfix.t list option;
  str: string;
}

type sentence_state =
  | Error of parsing_error
  | Parsed of parsed_ast

type pre_sentence = {
  parsing_start : int;
  start : int;
  stop : int;
  synterp_state : Vernacstate.Synterp.t; (* synterp state after this sentence's synterp phase *)
  ast : sentence_state;
}

(* Example:                        *)
(* "  Check 3. "                   *)
(* ^  ^       ^---- end            *)
(* |  |------------ start          *)
(* |---------------- parsing_start *)
type sentence = {
  parsing_start : int;
  start : int;
  stop : int;
  synterp_state : Vernacstate.Synterp.t; (* synterp state after this sentence's synterp phase *)
  scheduler_state_before : Scheduler.state;
  scheduler_state_after : Scheduler.state;
  ast : sentence_state;
  id : sentence_id;
  messages : feedback_message list;
  checked : sentence_checking_result option;
}

type document = {
  sentences_by_id : sentence SM.t;
  sentences_by_end : sentence_id LM.t;
  parsing_errors_by_end : parsing_error LM.t;
  comments_by_end : comment LM.t;
  schedule : Scheduler.schedule;
  parsed_loc : int;
  raw_doc : RawDocument.t;
  init_synterp_state : Vernacstate.Synterp.t;
  cancel_handle: Sel.Event.cancellation_handle option;
  doc_id : document_id; (* Rocq specific identifier, used for feedback & co *)
}

let id { doc_id } = doc_id

let sentence_of_id { sentences_by_id } id =
  match SM.find_opt id sentences_by_id with
  | None -> assert false
  | Some s -> s

type parse_state = {
  started: float;
  stop: int;
  top_id: sentence_id option;
  loc: Loc.t option;
  synterp_state : Vernacstate.Synterp.t;
  stream: (unit, char) Gramlib.Stream.t;
  raw: RawDocument.t;
  parsed: pre_sentence list;
  errors: parsing_error list;
  parsed_comments: comment list;
  previous_document: document;
}

type parsing_end_info = {
    unchanged_id: sentence_id option;
    invalid_ids: sentence_id_set;
    previous_document: document;
    parsed_document: document;
}

type event = 
| Parse of (bool * parse_state) interruptible_result Sel.Promise.state
let pp_event fmt = function
 | Parse _ -> Format.fprintf fmt "Parse _"

type events = event Sel.Event.t list

let range_of_sentence raw (sentence : sentence) =
  let start = RawDocument.position_of_loc raw sentence.start in
  let end_ = RawDocument.position_of_loc raw sentence.stop in
  Range.{ start; end_ }

let string_of_sentence raw (sentence: sentence) =
    let string = RawDocument.string_in_range raw sentence.start sentence.stop in
    string

let range_of_sentence_with_blank_space raw (sentence : sentence) =
  let start = RawDocument.position_of_loc raw sentence.parsing_start in
  let end_ = RawDocument.position_of_loc raw sentence.stop in
  Range.{ start; end_ }

let string_of_id document id =
  match SM.find_opt id document.sentences_by_id with
  | None -> CErrors.anomaly Pp.(str"Trying to get range of non-existing sentence " ++ Stateid.print id)
  | Some sentence -> string_of_sentence document.raw_doc sentence

let has_sentence document id =
  None <> SM.find_opt id document.sentences_by_id

let range_of_id document id =
  match SM.find_opt id document.sentences_by_id with
  | None -> CErrors.anomaly Pp.(str"Trying to get range of non-existing sentence " ++ Stateid.print id)
  | Some sentence -> range_of_sentence document.raw_doc sentence

let range_of_id_with_blank_space document id =
  match SM.find_opt id document.sentences_by_id with
  | None -> CErrors.anomaly Pp.(str"Trying to get range of non-existing sentence " ++ Stateid.print id)
  | Some sentence -> range_of_sentence_with_blank_space document.raw_doc sentence

let push_proof_step_in_outline document id (outline : outline_element list) =
  let range = range_of_id document id in
  let tactic = string_of_id document id in
  let proof_step = {id; tactic; range} in
  match outline with
  | [] -> outline
  | e :: l -> 
    let proof = proof_step :: e.proof in
    {e with proof} :: l

let record_outline document id (ast : Synterp.vernac_control_entry) classif (outline : outline_element list) =
  let open Vernacextend in
  match classif with
  | VtProofStep _ | VtQed _ -> push_proof_step_in_outline document id outline
  | VtStartProof (_, names) ->
    let vernac_gen_expr = ast.v.expr in
    let type_ = match vernac_gen_expr with
      | VernacSynterp _ -> None
      | VernacSynPure pure -> 
        match pure with
        | Vernacexpr.VernacStartTheoremProof _ -> Some TheoremKind
        | Vernacexpr.VernacDefinition _ -> Some DefinitionType
        | Vernacexpr.VernacFixpoint _ -> Some DefinitionType
        | Vernacexpr.VernacCoFixpoint _ -> Some DefinitionType
        | _ -> None
    in
    let str_names =
      match names with
      | [] -> ["default"]
      | _ -> List.map (fun n -> Names.Id.to_string n) names
    in

    begin match type_ with
    | None -> outline
    | Some type_ ->
      let range = range_of_id document id in
      let statement = string_of_id document id in
      let elements = List.map (fun name -> {id; type_; name; statement; range; proof=[]}) str_names in
      List.append elements outline
    end
  | VtSideff (names, _) ->
    let vernac_gen_expr = ast.v.expr in
    let type_, statement = match vernac_gen_expr with
      | VernacSynterp (Synterp.EVernacExtend _) when names <> [] -> Some Other, "external"
      | VernacSynterp (Synterp.EVernacBeginSection  _) -> log (fun () -> Format.sprintf "BEGIN SECTION %s" (string_of_id document id)); Some BeginSection, ""
      | VernacSynterp (Synterp.EVernacDeclareModuleType  _) -> log (fun () -> Format.sprintf "BEGIN MODULE %s" (string_of_id document id)); Some BeginModule, ""
      | VernacSynterp (Synterp.EVernacDefineModule  _) -> log (fun () -> Format.sprintf "BEGIN MODULE %s" (string_of_id document id)); Some BeginModule, ""
      | VernacSynterp (Synterp.EVernacDeclareModule  _) -> log (fun () -> Format.sprintf "BEGIN MODULE %s" (string_of_id document id)); Some BeginModule, ""
      | VernacSynterp (Synterp.EVernacEndSegment  _) -> log (fun () -> Format.sprintf "END SEGMENT"); Some End, ""
      | VernacSynterp _ -> None, ""
      | VernacSynPure pure -> 
        match pure with
        | Vernacexpr.VernacStartTheoremProof _ -> Some TheoremKind, string_of_id document id
        | Vernacexpr.VernacDefinition _ -> Some DefinitionType, string_of_id document id
        | Vernacexpr.VernacInductive _ -> Some InductiveType, string_of_id document id
        | Vernacexpr.VernacFixpoint _ -> Some DefinitionType, string_of_id document id
        | Vernacexpr.VernacCoFixpoint _ -> Some DefinitionType, string_of_id document id
        | _ -> None, ""
    in
    let str_names =
      match names with
      | [] -> ["default"]
      | _ -> List.map (fun n -> Names.Id.to_string n) names
    in
    begin match type_ with
    | None -> outline
    | Some type_ ->
      let range = range_of_id document id in
      let element = List.map (fun name -> {id; type_; name; statement; range; proof=[]}) str_names in
      List.append element outline
    end
  | _ -> outline

let record_outline document {id; ast} outline =
  match ast with
  | Error _ -> outline
  | Parsed ast -> record_outline document id ast.ast ast.classification outline

let compute_outline ({ sentences_by_end } as document) =
  LM.fold (fun _ s -> record_outline document (sentence_of_id document s)) sentences_by_end []

type entry_type =
  | ProofKindEntry
  | GallinaKindEntry
  | SectionKindEntry
  | ModuleKindEntry
  | OtherKindEntry

(* represents the document entries used for othe folding and the outline *)
type document_entries = {
  name: string;
  entry_type: entry_type;
  statement: string;
  range: Range.t;
  (* TODO: do we want this? *)
  children: document_entries list;
}

(** Finds the last entry matching a predicate with an unset end (start=end_) and sets its end *)
let update_last_open (pred: document_entries -> bool) (end_range: Position.t) (acc: document_entries list): document_entries list =
  let rec aux acc = function
    | [] -> List.rev acc
    | e :: l when pred e && e.range.start = e.range.end_ ->
      let e = {e with range = {e.range with end_ = end_range}} in
      List.rev_append acc (e :: l)
    | e :: l -> aux (e :: acc) l
  in
  aux [] acc

(** Finds the last entry matching a predicate with an unset end (start=end_) and sets its start *)
let update_start_last_open (pred: document_entries -> bool) (start_range: Position.t) (acc: document_entries list): document_entries list =
  let rec aux acc = function
    | [] -> List.rev acc
    | e :: l when pred e && e.range.start = e.range.end_ ->
      let e = {e with range = {e.range with start = start_range}} in
      List.rev_append acc (e :: l)
    | e :: l -> aux (e :: acc) l
  in
  aux [] acc

(** Finds the last entry matching a predicate and sets its end (no open check) *)
let update_end_last (pred: document_entries -> bool) (end_range: Position.t) (acc: document_entries list): document_entries list =
  let rec aux acc = function
    | [] -> List.rev acc
    | e :: l when pred e ->
      let e = {e with range = {e.range with end_ = end_range}} in
      List.rev_append acc (e :: l)
    | e :: l -> aux (e :: acc) l
  in
  aux [] acc

let insert_end_by_name (name: string) (end_range: Position.t) (acc: document_entries list): document_entries list =
  update_last_open (fun e -> e.name = name) end_range acc

let close_last_proof (end_range: Position.t) (acc: document_entries list): document_entries list =
  update_end_last (fun e -> e.entry_type = ProofKindEntry) end_range acc

let begin_last_proof (start_range: Position.t) (acc: document_entries list): document_entries list =
  update_start_last_open (fun e -> e.entry_type = ProofKindEntry) start_range acc

let string_names_of_names_wdefault = function
  | [] -> ["default"]
  | names -> List.map (fun n -> Names.Id.to_string n) names

let open_segment_entry document id (lident: Names.lident) (entry_type: entry_type) (acc: document_entries list) =
  let str_nm = Names.Id.to_string lident.v in
  let curr_range = range_of_id document id in
  let range = {curr_range with end_ = curr_range.start} in
  let entry = {name = str_nm; entry_type; statement = string_of_id document id; range; children = []} in
  List.cons entry acc

(** Inspects a single [constr_expr] node and produces folding range entries
    for match/if/fun/let expressions. Designed as a callback for [Utilities.fold_constr]. *)
let gallina_folding_range_of_constr (raw: RawDocument.t) (acc: document_entries list) (e: Constrexpr.constr_expr) : document_entries list =
  let open Constrexpr in
  let loc_entry name (loc: Loc.t) acc =
    let range_start = RawDocument.position_of_loc raw loc.Loc.bp in
    let range_end = RawDocument.position_of_loc raw loc.Loc.ep in
    if range_start <> range_end then
      {name; entry_type = GallinaKindEntry; statement = ""; range = {start = range_start; end_ = range_end}; children = []} :: acc
    else acc
  in
  match e.v with
  | CCases (_style, _ret, _scrutinees, branches) ->
    let acc = begin match e.loc with
      | None -> acc
      | Some loc -> loc_entry "match" loc acc
    end in
    List.fold_left (fun acc (b : branch_expr) ->
      match b.loc with
      | None -> acc
      | Some loc -> loc_entry "branch" loc acc
    ) acc branches
  | CIf _ ->
    begin match e.loc with
    | None -> acc
    | Some loc -> loc_entry "if" loc acc
    end
  | CLambdaN (_binders, _body) ->
    begin match e.loc with
    | None -> acc
    | Some loc -> loc_entry "fun" loc acc
    end
  | CLetIn (_binder, _def, _, _body) ->
    begin match e.loc with
    | None -> acc
    | Some loc -> loc_entry "let" loc acc
    end
  | _ -> acc

(** Walks a vernac expression, extracts all constr_expr sub-trees, and collects
    Gallina folding ranges (match/if/fun/let) from each using [Utilities.fold_constr]. *)
(* Vernacstate.Synterp.t VernacControl.control_entry *)
let gallina_folding_ranges_of_vernac_expr (raw: RawDocument.t) (acc: document_entries list) (ast: Synterp.vernac_control_entry) : document_entries list =
  let open Constrexpr in
  let f acc e = gallina_folding_range_of_constr raw acc e in
  let walk_constr acc e = Utilities.fold_constr f acc e in
  let walk_constr_opt acc = function None -> acc | Some e -> walk_constr acc e in
  let walk_binders acc binders =
    List.fold_left (fun acc b -> match b with
      | CLocalAssum (_, _, _, ty) -> walk_constr acc ty
      | CLocalDef (_, _, e, e_opt) -> walk_constr_opt (walk_constr acc e) e_opt
      | CLocalPattern _ -> acc
    ) acc binders
  in
  match ast.v.expr with
  | Vernacexpr.VernacSynPure pure ->
    begin match pure with
    | Vernacexpr.VernacDefinition (_, _, body) ->
      begin match body with
      | Vernacexpr.ProveBody (binders, ty) ->
        walk_constr (walk_binders acc binders) ty
      | Vernacexpr.DefineBody (binders, _, body, rest) ->
        let acc = walk_constr (walk_binders acc binders) body in
        walk_constr_opt acc rest
      end
    | Vernacexpr.VernacStartTheoremProof (_, proofs) ->
      List.fold_left (fun acc (_name_decl, (binders, ty)) ->
        walk_constr (walk_binders acc binders) ty
      ) acc proofs
    | Vernacexpr.VernacFixpoint (_, (_, fixes)) ->
      List.fold_left (fun acc fix ->
        let acc = walk_binders acc fix.Vernacexpr.binders in
        let acc = walk_constr acc fix.Vernacexpr.rtype in
        walk_constr_opt acc fix.Vernacexpr.body_def
      ) acc fixes
    | Vernacexpr.VernacCoFixpoint (_, cofixes) ->
      List.fold_left (fun acc cofix ->
        let acc = walk_binders acc cofix.Vernacexpr.binders in
        let acc = walk_constr acc cofix.Vernacexpr.rtype in
        walk_constr_opt acc cofix.Vernacexpr.body_def
      ) acc cofixes
    | Vernacexpr.VernacInductive (_, inds) ->
      List.fold_left (fun acc (((_coercion, (_name, _univs)), (params, _extra_params), rtype, _ctors), _notations) ->
        let acc = walk_binders acc params in
        walk_constr_opt acc rtype
      ) acc inds
    | _ -> acc
    end
  | _ -> acc

(** Creates the initial folding entries for the start of a proof: one Gallina entry,
    one open Proof entry to be closed by Qed, and Gallina folding ranges from the statement. *)
let folding_range_of_proof_start document (id: sentence_id) (names: Names.variable list) (ast: Synterp.vernac_control_entry) =
  let str_names = string_names_of_names_wdefault names in
  let range = range_of_id document id in
  let statement = string_of_id document id in
  let entries = List.concat_map (fun name -> [
    {name; entry_type = GallinaKindEntry; statement; range; children=[]};
    {name; entry_type = ProofKindEntry; statement; range = {start = range.end_; end_ = range.end_}; children=[]};
  ]) str_names in
  gallina_folding_ranges_of_vernac_expr document.raw_doc entries ast

(** Creates folding entries for a side-effect sentence: opens/closes sections and modules,
    creates Gallina definition entries, and collects nested Gallina ranges. *)
let folding_entries_of_sideff (document: document) (id: sentence_id) (names: Names.variable list) (ast: Synterp.vernac_control_entry) (acc: document_entries list) : document_entries list =
  begin match ast.v.expr with
  | VernacSynterp (Synterp.EVernacBeginSection lident) ->
    open_segment_entry document id lident SectionKindEntry acc
  | VernacSynterp (Synterp.EVernacDeclareModuleType (lident, _, _, _, _)) ->
    open_segment_entry document id lident ModuleKindEntry  acc
  | VernacSynterp (Synterp.EVernacDefineModule (_, lident, _, _, _, _)) ->
    open_segment_entry document id lident ModuleKindEntry acc
  | VernacSynterp (Synterp.EVernacDeclareModule (_, lident, _, _)) ->
    open_segment_entry document id lident ModuleKindEntry acc
  | VernacSynterp (Synterp.EVernacEndSegment lident) ->
    let str_nm = Names.Id.to_string lident.v in
    let curr_range = range_of_id document id in
    insert_end_by_name str_nm curr_range.end_ acc
  | VernacSynPure pure ->
    let is_gallina = match pure with
      | Vernacexpr.VernacDefinition _ | Vernacexpr.VernacInductive _
      | Vernacexpr.VernacFixpoint _ | Vernacexpr.VernacCoFixpoint _ -> true
      | _ -> false
    in
    if is_gallina then begin
      let str_names = string_names_of_names_wdefault names in
      let range = range_of_id document id in
      let entries = List.map (fun name ->
        {name; entry_type = GallinaKindEntry; statement = string_of_id document id; range; children = []}
      ) str_names in
      gallina_folding_ranges_of_vernac_expr document.raw_doc (List.append entries acc) ast
    end else acc
  | VernacSynterp (Synterp.EVernacRequire _) ->
    log (fun () -> Format.sprintf "FOLDING_RANGES: Vernac Require %s" (string_of_id document id));
    (* TODO: fold requires *)
    acc
  | VernacSynterp (Synterp.EVernacNotation _) ->
    log (fun () -> Format.sprintf "FOLDING_RANGES: Vernac Notation %s" (string_of_id document id));
    (* TODO: fold notations *)
    acc
  | VernacSynterp (Synterp.EVernacExtend _) ->
    log (fun () -> Format.sprintf "FOLDING_RANGES: Vernac EXTEND %s" (string_of_id document id));
    acc
  | _ ->
    log (fun () -> Format.sprintf "FOLDING_RANGES: SIDEFF UNKNOWN %s" (string_of_id document id));
    acc
  end

(* TODO: do one type of opearation based on classif and other based on ast, then aggregate them (concat or apply in some other way) *)
(* probably modify the current acc based on classif and ppend the ast entries *)

(* TODO: extract the folding/entries related code to a separate file *)

(* TODO: actually use the "children" field -- update it when closing a section and when adding Gallina expressions *)

(* TODO: Also fold: Inductive cases, comments *)

(* TODO: for unsupported features, specifically vernac extend implement a string(indentation) based callback (+ plus folding the whole thing) *)

(* TODO: in Gallina try if we can fold code that USES notations *)

(** Adds folding entries for the current ast *)
let update_entries_with_ast document (id: sentence_id) (p_ast: parsed_ast) (acc: document_entries list): document_entries list =
  let classif = p_ast.classification in
  let ast = p_ast.ast in
  let open Vernacextend in
  begin match classif with
  | VtProofStep _ ->
    let curr_range = range_of_id document id in
    begin_last_proof curr_range.start acc
  | VtQed _ ->
    let curr_range = range_of_id document id in
    close_last_proof curr_range.start acc
  | VtStartProof (_, names) ->
    List.append (folding_range_of_proof_start document id names ast) acc
  | VtSideff (names, _) ->
    folding_entries_of_sideff document id names ast acc
  | _ -> acc
  end

let folding_ranges ({ sentences_by_end } as document) =
  LM.fold (fun _ s acc ->
    let {id; ast} = sentence_of_id document s in
    match ast with
    | Error _ -> acc
    | Parsed ast -> update_entries_with_ast document id ast acc
  ) sentences_by_end []

let schedule doc = doc.schedule

let raw_document doc = doc.raw_doc

let outline doc = compute_outline doc
let parse_errors parsed =
  List.map snd (LM.bindings parsed.parsing_errors_by_end)

let add_sentence parsed parsing_start start stop (ast: sentence_state) synterp_state scheduler_state_before =
  let id = Stateid.fresh () in
  let scheduler_state_after, schedule = 
    match ast with
    | Error {msg} ->
      scheduler_state_before, Scheduler.schedule_errored_sentence id msg synterp_state parsed.schedule
    | Parsed ast ->
      let ast' = (ast.ast, ast.classification, synterp_state) in
      Scheduler.schedule_sentence (id, ast') scheduler_state_before parsed.schedule
  in
  (* FIXME may invalidate scheduler_state_XXX for following sentences -> propagate? *)
  (* What about messages generated during parsing? *)
  let sentence = { parsing_start; start; stop; ast; id; synterp_state; scheduler_state_before; scheduler_state_after; messages = []; checked = None } in
  let document = { 
    parsed with sentences_by_end = LM.add stop id parsed.sentences_by_end;
    sentences_by_id = SM.add id sentence parsed.sentences_by_id;
    schedule;
  } in
  document, scheduler_state_after

let remove_sentence parsed id =
  match SM.find_opt id parsed.sentences_by_id with
  | None -> parsed
  | Some sentence ->
    let sentences_by_id = SM.remove id parsed.sentences_by_id in
    let sentences_by_end = LM.remove sentence.stop parsed.sentences_by_end in
    (* TODO clean up the schedule and free cached states *)
    { parsed with sentences_by_id; sentences_by_end }

let sentences parsed =
  List.map snd @@ SM.bindings parsed.sentences_by_id
  
type code_line =
  | Sentence of sentence
  | ParsingError of parsing_error
  | Comment of comment
  
let start_of_code_line = function
  | Sentence { start = x } -> x
  | ParsingError  { start = x } -> x
  | Comment { start = x } -> x

let compare_code_line x y =
  let s1 = start_of_code_line x in
  let s2 = start_of_code_line y in
  s1 - s2

let code_lines_sorted_by_loc parsed =
  List.sort compare_code_line @@ List.concat [
    (List.map (fun (_,x) -> Sentence x) @@ SM.bindings parsed.sentences_by_id) ;
    (List.map (fun (_,x) -> ParsingError x) @@ LM.bindings parsed.parsing_errors_by_end) ;
    []  (* todo comments *)
   ]

let code_lines_by_end_sorted_by_loc parsed =
  List.sort compare_code_line @@ List.concat [
    (List.map (fun (_,x) -> Sentence (sentence_of_id parsed x)) @@ LM.bindings parsed.sentences_by_end) ;
    (List.map (fun (_,x) -> ParsingError x) @@ LM.bindings parsed.parsing_errors_by_end) ;
    []  (* todo comments *)
   ]

let sentences_sorted_by_loc parsed =
  List.sort (fun ({start = s1} : sentence) {start = s2} -> s1 - s2) @@ List.map snd @@ SM.bindings parsed.sentences_by_id

let sentences_before parsed loc =
  let (before,ov,_after) = LM.split loc parsed.sentences_by_end in
  let before = Option.cata (fun v -> LM.add loc v before) before ov in
  List.map (fun (_id,s) -> sentence_of_id parsed s) @@ LM.bindings before

let sentences_after parsed loc =
  let (_before,ov,after) = LM.split loc parsed.sentences_by_end in
  let after = Option.cata (fun v -> LM.add loc v after) after ov in
  List.map (fun (_id,s) -> s) @@ LM.bindings after

let parsing_errors_before parsed loc =
  LM.filter (fun stop _v -> stop <= loc) parsed.parsing_errors_by_end

let comments_before parsed loc =
  LM.filter (fun stop _v -> stop <= loc) parsed.comments_by_end
let get_sentence parsed id =
  SM.find_opt id parsed.sentences_by_id

let find_sentence parsed loc =
  match LM.find_first_opt (fun k -> loc <= k) parsed.sentences_by_end with
  | Some (_, sentence_id) ->
      let sentence = sentence_of_id parsed sentence_id in
      if sentence.start <= loc then Some sentence else None
  | _ -> None

let find_sentence_before parsed loc =
  match LM.find_last_opt (fun k -> k <= loc) parsed.sentences_by_end with
  | Some (_, sentence_id) -> Some (sentence_of_id parsed sentence_id)
  | _ -> None

(* moved here from DM, maybe can be simplified / use find_sentence_after *)
let find_sentence_before_pos document pos =
  let loc = RawDocument.loc_of_position (raw_document document) pos in
  find_sentence_before document loc

let find_sentence_strictly_before parsed loc =
  match LM.find_last_opt (fun k -> k < loc) parsed.sentences_by_end with
  | Some (_, sentence) -> Some sentence
  | _ -> None

let find_sentence_after parsed loc = 
  match LM.find_first_opt (fun k -> loc <= k) parsed.sentences_by_end with
  | Some (_, sentence_id) -> Some (sentence_of_id parsed sentence_id)
  | _ -> None

(* moved here from DM, maybe can be simplified / use find_sentence_after *)
let find_sentence_after_pos document pos =
  let loc = RawDocument.loc_of_position (raw_document document) pos in
  (* if the current loc falls squarely within a sentence *)
  match find_sentence document loc with
  | Some x -> Some x
  | None -> 
    (** otherwise the sentence start is after the loc,
        so we must be in the whitespace before the sentence
        and need to interpret to the sentence before instead
    *)
    match find_sentence_before document loc with
    | None -> None
    | Some x -> Some x

let find_next_qed parsed loc =
  let exception Found of sentence in
  let f k sentence_id =
    if loc <= k then
    let sentence = sentence_of_id parsed sentence_id in
    match sentence.ast with
    | Error _ -> ()
    | Parsed ast ->
    match ast.classification with
      | VtQed _ -> raise (Found sentence)
      | _ -> () in
  (* We can't use find_first since f isn't monotone *)
  match LM.iter f parsed.sentences_by_end with
  | () -> None
  | exception (Found n) -> Some n

let find_next_qed_pos parsed pos =
  let loc = RawDocument.loc_of_position (raw_document parsed) pos in
  find_next_qed parsed loc

let get_first_sentence parsed = 
  Option.map (fun (_,id) -> sentence_of_id parsed id) @@
    LM.find_first_opt (fun _ -> true) parsed.sentences_by_end

let get_last_sentence parsed = 
  Option.map (fun (_,id) -> sentence_of_id parsed id) @@
    LM.find_last_opt (fun _ -> true) parsed.sentences_by_end

let state_after_sentence parsed = function
  | Some (stop, sentence_id) ->
    let { synterp_state; scheduler_state_after } = sentence_of_id parsed sentence_id in
    (stop, synterp_state, scheduler_state_after)
  | None -> (-1, parsed.init_synterp_state, Scheduler.initial_state)

let state_at_pos parsed pos =
  state_after_sentence parsed @@
    LM.find_last_opt (fun stop -> stop <= pos) parsed.sentences_by_end

let state_strictly_before parsed pos =
  state_after_sentence parsed @@
    LM.find_last_opt (fun stop -> stop < pos) parsed.sentences_by_end

let pos_at_end parsed =
  match LM.max_binding_opt parsed.sentences_by_end with
  | Some (stop, _) -> stop
  | None -> -1

let is_sentence_above st id1 id2 =
  let range1 = range_of_id st id1 in
  let range2 = range_of_id st id2 in
  let pos1 = range1.start in
  let pos2 = range2.start in
  match Int.compare pos1.line pos2.line with
  | 0 -> Int.compare pos1.character pos2.character < 0
  | x -> x < 0

let all_feedback parsed =
  SM.bindings parsed.sentences_by_id |>
  List.fold_left (fun acc (id, { messages }) -> List.map (fun x -> (id, x)) messages @ acc) []
 
let feedback parsed id =
  match SM.find_opt id parsed.sentences_by_id with
  | None -> []
  | Some { messages } -> messages

let all_checking_errors parsed =
  SM.bindings parsed.sentences_by_id |>
  List.fold_left (fun acc (id, { checked }) ->
    match checked with
    | None | Some (Success _) -> acc
    | Some (Failure ((loc,e),qf,_)) -> (id,(loc,e,qf)) :: acc) []

let error parsed id =
  match SM.find_opt id parsed.sentences_by_id with
  | Some { checked = Some (Failure ((loc,e),qf,_)) } -> Some (loc,e,qf)
  | _ -> None

let is_qed = function
  | Parsed { classification = Vernacextend.(VtQed (VtKeep VtKeepOpaque)) } -> true
  (* Updating a sentences marked with Success only happens when a Qed closing
     a delegated proof receives an updated by a worker saying that the proof is
     not completed. Here we double check this invariant. *)
  | _ -> false

let update_checked parsed (id, v) =
  match SM.find_opt id parsed.sentences_by_id with
  | None -> parsed
  | Some ({ checked; ast } as s) ->
      match checked with
      | None | Some (Failure _)->
          { parsed with sentences_by_id = SM.add id { s with checked = Some v} parsed.sentences_by_id }
      | Some (Success _) when is_qed ast ->
          { parsed with sentences_by_id = SM.add id { s with checked = Some v} parsed.sentences_by_id }
      | _ -> log (fun () -> "Ignoring bad update for checked status, possibly a bug"); parsed

let set_unchecked parsed id =
  match SM.find_opt id parsed.sentences_by_id with
  | None -> parsed
  | Some s ->
    { parsed with sentences_by_id = SM.add id { s with checked = None } parsed.sentences_by_id }

let is_checked parsed id =
  match SM.find_opt id parsed.sentences_by_id with
  | None -> false
  | Some { checked } -> not(checked = None)

let append_feedback parsed id (_, _, _, msg as fb) =
  match SM.find_opt id parsed.sentences_by_id with
  | None -> 
    log (fun () -> "Received feedback on non-existing state id " ^ Stateid.to_string id ^ ": " ^ Pp.string_of_ppcmds msg);
    parsed
  | Some s ->
      { parsed with sentences_by_id = SM.add id { s with messages = s.messages @ [fb] } parsed.sentences_by_id }

let shift_sentence ~start ~offset s =
  let messages = CList.Smart.map (Utilities.shift_feedback ~start ~offset) s.messages in
  let checked = Option.Smart.map (Utilities.shift_checking_result ~start ~offset) s.checked in
  if messages == s.messages && checked == s.checked then s
  else { s with messages; checked }

let shift_feedbacks_and_checking_errors ~start ~offset parsed =
  { parsed with sentences_by_id = SM.map (shift_sentence ~start ~offset) parsed.sentences_by_id }

let string_of_parsed_ast { tokens } = 
  (* TODO implement printer for vernac_entry *)
  "[" ^ String.concat "--" (List.map (Tok.extract_string false) tokens) ^ "]"

let string_of_parsed_ast = function
| Error e -> "[errored sentence]: " ^ (e.str)
| Parsed ast -> string_of_parsed_ast ast

let patch_sentence parsed scheduler_state_before id ({ parsing_start; ast; start; stop; synterp_state } : pre_sentence) =
  let old_sentence = SM.find id parsed.sentences_by_id in
  log (fun () -> Format.sprintf "Patching sentence %s , %s" (Stateid.to_string id) (string_of_parsed_ast old_sentence.ast));
  let scheduler_state_after, schedule =
    match ast with
    | Error {msg} ->
      scheduler_state_before, Scheduler.schedule_errored_sentence id msg synterp_state parsed.schedule
    | Parsed ast ->
      let ast = (ast.ast, ast.classification, synterp_state) in
      Scheduler.schedule_sentence (id,ast) scheduler_state_before parsed.schedule
  in
  let new_sentence = { old_sentence with ast; parsing_start; start; stop; scheduler_state_before; scheduler_state_after } in
  let sentences_by_id = SM.add id new_sentence parsed.sentences_by_id in
  let sentences_by_end = match LM.find_opt old_sentence.stop parsed.sentences_by_end with
  | Some id when Stateid.equal id new_sentence.id ->
    LM.remove old_sentence.stop parsed.sentences_by_end 
  | _ -> parsed.sentences_by_end
  in
  let sentences_by_end = LM.add new_sentence.stop id sentences_by_end in
  { parsed with sentences_by_end; sentences_by_id; schedule }, scheduler_state_after

type diff =
  | Deleted of sentence_id list
  | Added of pre_sentence list
  | Equal of (sentence_id * pre_sentence) list

let tok_equal t1 t2 =
  let open Tok in
  match t1, t2 with
  | KEYWORD s1, KEYWORD s2 -> CString.equal s1 s2
  | IDENT s1, IDENT s2 -> CString.equal s1 s2
  | FIELD s1, FIELD s2 -> CString.equal s1 s2
  | NUMBER n1, NUMBER n2 -> NumTok.Unsigned.equal n1 n2
  | STRING s1, STRING s2 -> CString.equal s1 s2
  | LEFTQMARK, LEFTQMARK -> true
  | BULLET s1, BULLET s2 -> CString.equal s1 s2
  | EOI, EOI -> true
  | QUOTATION(s1,t1), QUOTATION(s2,t2) -> CString.equal s1 s2 && CString.equal t1 t2
  | _ -> false

let same_errors (e1 : parsing_error) (e2 : parsing_error) =
  (String.compare e1.str e2.str = 0) && (e1.start = e2.start) && (e1.stop = e2.stop)

let same_tokens (s1 : sentence) (s2 : pre_sentence) =
  match s1.ast, s2.ast with
  | Error e1, Error e2 -> same_errors e1 e2
  | Parsed ast1, Parsed ast2 ->
    CList.equal tok_equal ast1.tokens ast2.tokens
  | _, _ -> false
  
(* TODO improve diff strategy (insertions,etc) *)
let rec diff old_sentences new_sentences =
  match old_sentences, new_sentences with
  | [], [] -> []
  | [], new_sentences -> [Added new_sentences]
  | old_sentences, [] -> [Deleted (List.map (fun s -> s.id) old_sentences)]
    (* FIXME something special should be done when `Deleted` is applied to a parsing effect *)
  | old_sentence::old_sentences, new_sentence::new_sentences ->
    if same_tokens old_sentence new_sentence then 
      Equal [(old_sentence.id,new_sentence)] :: diff old_sentences new_sentences
    else 
      Deleted [old_sentence.id] :: Added [new_sentence] :: diff old_sentences new_sentences

let string_of_diff_item doc = function
  | Deleted ids ->
      let get_str id = match get_sentence doc id with
      | None -> "missing from doc"
      | Some s -> string_of_parsed_ast s.ast
      in
       ids |> List.map (fun id -> Printf.sprintf "- (id: %d) %s" (Stateid.to_int id) (get_str id))
  | Added sentences ->
       sentences |> List.map (fun (s : pre_sentence) -> Printf.sprintf "+ %s" (string_of_parsed_ast s.ast))
  | Equal l ->
       l |> List.map (fun (id, (s : pre_sentence)) -> Printf.sprintf "= (id: %d) %s" (Stateid.to_int id) (string_of_parsed_ast s.ast))

let string_of_diff doc l =
  String.concat "\n" (List.flatten (List.map (string_of_diff_item doc) l))

[%%if rocq = "8.18" || rocq = "8.19" || rocq = "8.20"]
  let get_keyword_state = Pcoq.get_keyword_state
[%%else]
  let get_keyword_state = Procq.get_keyword_state
[%%endif]

[%%if rocq = "8.18" || rocq = "8.19" || rocq = "8.20" || rocq = "9.0" || rocq = "9.1"]
let rec stream_tok n_tok acc str begin_line begin_char =
  let e = LStream.next (get_keyword_state ()) str in
  match e with
  | Tok.EOI ->
    List.rev acc
  | _ ->
    stream_tok (n_tok+1) (e::acc) str begin_line begin_char
[%%else]
let rec stream_tok n_tok acc str begin_line begin_char =
  let e = LStream.next (get_keyword_state ()) str in
  match e with
  | Some Tok.EOI ->
    List.rev acc
  | Some e ->
    stream_tok (n_tok+1) (e::acc) str begin_line begin_char
  | None -> assert false (* should get EOI before None *)
[%%endif]
    (*
let parse_one_sentence stream ~st =
  let pa = Pcoq.Parsable.make stream in
  Vernacstate.Parser.parse st (Pvernac.main_entry (Some (Vernacinterp.get_default_proof_mode ()))) pa
  (* FIXME: handle proof mode correctly *)
  *)


[%%if rocq = "8.18" || rocq = "8.19"]
let parse_one_sentence ?loc stream ~st =
  Vernacstate.Synterp.unfreeze st;
  let entry = Pvernac.main_entry (Some (Synterp.get_default_proof_mode ())) in
  let pa = Pcoq.Parsable.make ?loc stream in
  let sentence = Pcoq.Entry.parse entry pa in
  (sentence, [])
[%%elif rocq = "8.20"]
let parse_one_sentence ?loc stream ~st =
  Vernacstate.Synterp.unfreeze st;
  Flags.record_comments := true;
  let entry = Pvernac.main_entry (Some (Synterp.get_default_proof_mode ())) in
  let pa = Pcoq.Parsable.make ?loc stream in
  let sentence = Pcoq.Entry.parse entry pa in
  let comments = Pcoq.Parsable.comments pa in
  (sentence, comments)
[%%elif rocq = "9.0" || rocq = "9.1"]
let parse_one_sentence ?loc stream ~st =
  Vernacstate.Synterp.unfreeze st;
  Flags.record_comments := true;
  let entry = Pvernac.main_entry (Some (Synterp.get_default_proof_mode ())) in
  let pa = Procq.Parsable.make ?loc stream in
  let sentence = Procq.Entry.parse entry pa in
  let comments = Procq.Parsable.comments pa in
  (sentence, comments)
[%%else]
let parse_one_sentence ?loc stream ~st =
  Vernacstate.Synterp.unfreeze st;
  CLexer.record_comments := true;
  let entry = Pvernac.main_entry (Some (Synterp.get_default_proof_mode ())) in
  let pa = Procq.Parsable.make ?loc stream in
  let sentence = Procq.Entry.parse entry pa in
  let comments = Procq.Parsable.comments pa in
  (sentence, comments)
[%%endif]

let rec junk_sentence_end stream =
  match Stream.npeek () 2 stream with
  | ['.'; (' ' | '\t' | '\n' |'\r')] -> Stream.junk () stream
  | [] -> ()
  | _ ->  Stream.junk () stream; junk_sentence_end stream

[%%if rocq = "8.18"]
exception E = Stream.Error
[%%elif rocq = "8.19" || rocq = "8.20" || rocq = "9.0" || rocq = "9.1"]
exception E = Grammar.Error
[%%else]
exception E = Grammar.ParseError
[%%endif]

[%%if rocq = "8.18" || rocq = "8.19"]
let get_loc_from_info_or_exn e info =
  match e with
  | Synterp.UnmappedLibrary (_, qid) -> qid.loc
  | Synterp.NotFoundLibrary (_, qid) -> qid.loc
  | _ -> Loc.get_loc @@ info
[%%else]
let get_loc_from_info_or_exn _ info =
  Loc.get_loc info

(* let get_qf_from_info info = Quickfix.get_qf info *)
[%%endif]

[%%if rocq = "8.18" || rocq = "8.19"]
let get_entry ast = Synterp.synterp_control ast
[%%else]
let get_entry ast =
  let intern = Vernacinterp.fs_intern in
  Synterp.synterp_control ~intern ast
[%%endif]


let rec handle_parse_error start parsing_start msg qf ({stream; errors; parsed;} as parse_state) synterp_state =
  log (fun () -> "handling parse error at " ^ string_of_int start);
  let stop = Stream.count stream in
  let str = String.sub (RawDocument.text parse_state.raw) parsing_start (stop - parsing_start) in
  let parsing_error = { msg; start; stop; qf; str} in
  let sentence = { parsing_start; ast = Error parsing_error; start; stop; synterp_state } in
  let parsed = sentence :: parsed in
  let errors = parsing_error :: errors in
  let parse_state = {parse_state with errors; parsed} in
  (* TODO: we could count the \n between start and stop and increase Loc.line_nb *)
  true, parse_state

and parse_more ({loc; synterp_state; stream; raw; parsed; parsed_comments} as parse_state) : bool * parse_state =
  let start = Stream.count stream in
  log (fun () -> "Start of parse is: " ^ (string_of_int start));
  begin
    (* FIXME should we save lexer state? *)
    match parse_one_sentence ?loc stream ~st:synterp_state with
    | None, _ (* EOI *) -> false, parse_state
    | Some ast, comments ->
      let stop = Stream.count stream in
      let begin_line, begin_char, end_char =
              match ast.loc with
              | Some lc -> lc.line_nb, lc.bp, lc.ep
              | None -> assert false
      in
      let str = String.sub (RawDocument.text raw) begin_char (end_char - begin_char) in
      let sstr = Stream.of_string str in
      let lex = CLexer.Lexer.tok_func sstr in
      let tokens = stream_tok 0 [] lex begin_line begin_char in
      begin
        try
          log (fun () -> "Parsed: " ^ (Pp.string_of_ppcmds @@ Ppvernac.pr_vernac ast));
          let entry = get_entry ast in
          let classification = Vernac_classifier.classify_vernac ast in
          let synterp_state = Vernacstate.Synterp.freeze () in
          let parsed_ast = Parsed { ast = entry; classification; tokens } in
          let sentence = { parsing_start = start; ast = parsed_ast; start = begin_char; stop; synterp_state } in
          let parsed = sentence :: parsed in
          let comments = List.map (fun ((start, stop), content) -> {start; stop; content}) comments in
          let parsed_comments = List.append comments parsed_comments in
          let loc = ast.loc in
          let parse_state = {parse_state with parsed_comments; parsed; loc; synterp_state} in
          true, parse_state
        with exn ->
          let e, info = Exninfo.capture exn in
          let loc = get_loc_from_info_or_exn e info in
          let qf = Result.value ~default:[] @@ Quickfix.from_exception e in
          handle_parse_error start begin_char (loc, CErrors.iprint_no_report (e,info)) (Some qf) parse_state synterp_state
        end
    | exception (E _ as exn) ->
      let e, info = Exninfo.capture exn in
      let loc = get_loc_from_info_or_exn e info in
      let qf = Result.value ~default:[] @@ Quickfix.from_exception e in
      junk_sentence_end stream;
      handle_parse_error start start (loc, CErrors.iprint_no_report (e, info)) (Some qf) {parse_state with stream} synterp_state
    | exception (CLexer.Error.E _ as exn) -> (* May be more problematic to handle for the diff *)
      let e, info = Exninfo.capture exn in
      let loc = get_loc_from_info_or_exn e info in
      let qf = Result.value ~default:[] @@ Quickfix.from_exception exn in
      junk_sentence_end stream;
      handle_parse_error start start (loc,CErrors.iprint_no_report (e, info)) (Some qf) {parse_state with stream} synterp_state
    | exception exn ->
      let e, info = Exninfo.capture exn in
      let loc = Loc.get_loc @@ info in
      let qf = Result.value ~default:[] @@ Quickfix.from_exception exn in
      junk_sentence_end stream;
      handle_parse_error start start (loc, CErrors.iprint_no_report (e,info)) (Some qf) {parse_state with stream} synterp_state
  end
and create_parse_event ~doc_id parse_state =
  let priority = Some PriorityManager.parsing in
  Sel.On.promise ~name:"Parse" ?priority (ProverThread.eventually_run ~doc_id ~name:"create_parse_event" (fun () -> parse_more parse_state)) (fun x -> Parse x)


let rec unchanged_id id = function
  | [] -> id
  | Equal s :: diffs ->
    let get_id_ignore_error id_option (id, (s: pre_sentence)) =
      match s.ast with
        | Error _ -> id_option
        | Parsed _ ->  Some id
    in
    unchanged_id (List.fold_left get_id_ignore_error id s) diffs
  | (Added _ | Deleted _) :: _ -> id

let invalidate top_edit top_id parsed_doc new_sentences =
  let rec add_new_or_patch parsed_doc scheduler_state = function
    | [] -> parsed_doc
    | Deleted _ :: diffs -> add_new_or_patch parsed_doc scheduler_state diffs
    | Equal s :: diffs ->
      let patch_sentence (parsed_doc,scheduler_state) (id,new_s) =
        patch_sentence parsed_doc scheduler_state id new_s
      in
      let parsed_doc, scheduler_state = List.fold_left patch_sentence (parsed_doc, scheduler_state) s in
      add_new_or_patch parsed_doc scheduler_state diffs
    | Added new_sentences :: diffs ->
    (* FIXME could have side effect on the following, unchanged sentences *)
      let add_sentence (parsed_doc,scheduler_state) ({ parsing_start; start; stop; ast; synterp_state } : pre_sentence) =
        add_sentence parsed_doc parsing_start start stop ast synterp_state scheduler_state
      in
      let parsed_doc, scheduler_state = List.fold_left add_sentence (parsed_doc,scheduler_state) new_sentences in
      add_new_or_patch parsed_doc scheduler_state diffs
  in
  let rec remove_old parsed_doc invalid_ids = function
    | [] -> parsed_doc, invalid_ids
    | Deleted ids :: diffs ->
      let invalid_ids = List.fold_left (fun ids id -> Stateid.Set.add id ids) invalid_ids ids in
      let parsed_doc = List.fold_left remove_sentence parsed_doc ids in
      (* FIXME update scheduler state, maybe invalidate after diff zone *)
      remove_old parsed_doc invalid_ids diffs
    | Equal _ :: diffs
    | Added _ :: diffs -> remove_old parsed_doc invalid_ids diffs in
  let (_,_synterp_state,scheduler_state) = state_at_pos parsed_doc top_edit in
  log (fun () -> 
    let sentence_strings = LM.bindings @@ LM.map (fun s -> string_of_parsed_ast (sentence_of_id parsed_doc s).ast) parsed_doc.sentences_by_end in
    let sentence_strings = List.map (fun s -> snd s) sentence_strings in
    let sentence_string = String.concat " " sentence_strings in
    let sentence_strings_id = SM.bindings @@ SM.map (fun s -> string_of_parsed_ast s.ast) parsed_doc.sentences_by_id in
    let sentence_strings_id = List.map (fun s -> snd s) sentence_strings_id in
    let sentence_string_id = String.concat " " sentence_strings_id in    
    Format.sprintf "Top edit: %i, Doc: %s, Doc by id: %s" top_edit sentence_string sentence_string_id);
  let old_sentences = List.map (sentence_of_id parsed_doc) @@ sentences_after parsed_doc top_edit in
  let diff = diff old_sentences new_sentences in
  let parsed_doc, invalid_ids = remove_old parsed_doc Stateid.Set.empty diff in
  let parsed_doc = add_new_or_patch parsed_doc scheduler_state diff in
  let unchanged_id = unchanged_id top_id diff in
  log (fun () -> "diff:\n" ^ string_of_diff parsed_doc diff);
  unchanged_id, invalid_ids, parsed_doc

(** Validate document when raw text has changed *)
let validate_document ({ parsed_loc; raw_doc; cancel_handle; doc_id } as document) =
  (* Cancel any previous parsing event *)
  Option.iter Sel.Event.cancel cancel_handle;
  (* We take the state strictly before parsed_loc to cover the case when the
  end of the sentence is editted *)
  let (stop, synterp_state, _scheduler_state) = state_strictly_before document parsed_loc in
  (* let top_id = find_sentence_strictly_before document parsed_loc with None -> Top | Some sentence -> Id sentence.id in *)
  let top_id = find_sentence_strictly_before document parsed_loc in
  let text = RawDocument.text raw_doc in
  let stream = Stream.of_string text in
  while Stream.count stream < stop do Stream.junk () stream done;
  log (fun () -> Format.sprintf "Parsing more from pos %i" stop);
  let started = Unix.gettimeofday () in
  let parsed_state = {stop; top_id;synterp_state; stream; raw=raw_doc; parsed=[]; errors=[]; parsed_comments=[]; loc=None; started; previous_document=document} in
  let event = create_parse_event ~doc_id parsed_state in
  let cancel_handle = Some (Sel.Event.get_cancellation_handle event) in
  {document with cancel_handle}, [event]

let handle_invalidate {parsed; errors; parsed_comments; stop; top_id; started; previous_document} document =
  let end_ = Unix.gettimeofday ()in
  let time = end_ -. started in
  (* log (fun () -> Format.sprintf "Parsing phase ended in %5.3f" time); *)
  log (fun () -> Format.sprintf "Parsing phase ended in %5.3f\n%!" time);
  let new_sentences = List.rev parsed in
  let new_comments = List.rev parsed_comments in
  let new_errors = errors in
  log (fun () -> Format.sprintf "%i new sentences" (List.length new_sentences));
  log (fun () -> Format.sprintf "%i new comments" (List.length new_comments));
  let errors = parsing_errors_before document stop in
  let comments = comments_before document stop in
  let unchanged_id, invalid_ids, document = invalidate (stop+1) top_id document new_sentences in
  let parsing_errors_by_end =
    List.fold_left (fun acc (error : parsing_error) -> LM.add error.stop error acc) errors new_errors
  in
  let comments_by_end =
    List.fold_left (fun acc (comment : comment) -> LM.add comment.stop comment acc) comments new_comments
  in
  let parsed_loc = pos_at_end document in
  let parsed_document = {document with parsed_loc; parsing_errors_by_end; comments_by_end} in
  Some {parsed_document; unchanged_id; invalid_ids; previous_document}

let handle_event document = function
| Parse (Sel.Promise.Rejected e) -> raise e
| Parse (Sel.Promise.Fulfilled Interrupted) -> assert false
| Parse (Sel.Promise.Fulfilled (Aborted e)) -> CErrors.user_err e
| Parse (Sel.Promise.Fulfilled (Terminated (true,parse_state))) -> 
  (* let event = create_parse_event parse_state in *)
  let event = create_parse_event ~doc_id:document.doc_id parse_state in
  let cancel_handle = Some (Sel.Event.get_cancellation_handle event) in
  {document with cancel_handle}, [event], None
| Parse (Sel.Promise.Fulfilled (Terminated (false,parse_state))) -> 
  {document with cancel_handle=None}, [], handle_invalidate parse_state document

let create_document ~doc_id init_synterp_state text =
  let raw_doc = RawDocument.create text in
    { 
      parsed_loc = -1;
      raw_doc;
      sentences_by_id = SM.empty;
      sentences_by_end = LM.empty;
      parsing_errors_by_end = LM.empty;
      comments_by_end = LM.empty;
      schedule = initial_schedule;
      init_synterp_state;
      cancel_handle = None;
      doc_id;
    }

let apply_text_edit document edit =
  let raw_doc, start = RawDocument.apply_text_edit document.raw_doc edit in
  let parsed_loc = min document.parsed_loc start in
  { document with raw_doc; parsed_loc }

let apply_text_edits document edits =
  let doc' = { document with raw_doc = document.raw_doc } in
  List.fold_left apply_text_edit doc' edits

module Internal = struct

  let string_of_sentence sentence =
    Format.sprintf "[%s] %s (%i -> %i)" (Stateid.to_string sentence.id)
    (string_of_parsed_ast sentence.ast)
    sentence.start
    sentence.stop

  let string_of_error error =
    let (_, pp) = error.msg in
    Format.sprintf "[parsing error] [%s] (%i -> %i)"
    (Pp.string_of_ppcmds pp)
    error.start
    error.stop

  let string_of_item = function
    | Sentence sentence -> string_of_sentence sentence
    | Comment _ -> "(* comment *)"
    | ParsingError error -> string_of_error error
  
end
