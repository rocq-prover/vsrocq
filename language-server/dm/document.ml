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

let Log log_parsing = Log.mk_log "document.parsing"
let Log log_diff = Log.mk_log "document.diff"
let Log log_outline = Log.mk_log "document.outline"
let Log log_validate = Log.mk_log "document.validate"

module LM = struct
  include Map.Make (Int)
  let shift fk fv m = fold (fun k v m -> add (fk k) (fv v) m) m empty
end

module SM = Map.Make (Stateid)
module SS = Stateid.Set

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
}

type document = {
  sentences_by_id : sentence SM.t;
  sentences_by_end : sentence LM.t;
  parsing_errors_by_end : parsing_error LM.t;
  comments_by_end : comment LM.t;
  schedule : Scheduler.schedule;
  unparsed_range : RawDocument.edit_impact option;
  raw_doc : RawDocument.t;
  init_synterp_state : Vernacstate.Synterp.t;
  cancel_handle: Sel.Event.cancellation_handle option;
}

type parsing_request_range = {
    start : int; (* begin of edits *)
    stop : int;  (* end of edits *)
    shift_after_stop: int; (* size of edit, negative for removal *)
  }

type parse_state = {
  started: float;
  parsing_request_range: parsing_request_range;
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
| ParseEvent of parse_state
| Invalidate of { ps : parse_state; stopped_here : int option } (* stopped_here >= ps.parsing_range.stop_here, None = end of stream *)
let pp_event fmt = function
 | ParseEvent _ -> Format.fprintf fmt "ParseEvent _"
 | Invalidate _ -> Format.fprintf fmt "Invalidate _"

type events = event Sel.Event.t list

let create_parsing_event event =
  let priority = Some PriorityManager.parsing in
  Sel.now ?priority event

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
      | VernacSynterp (Synterp.EVernacBeginSection  _) -> log_outline (fun () -> Format.sprintf "BEGIN SECTION %s" (string_of_id document id)); Some BeginSection, ""
      | VernacSynterp (Synterp.EVernacDeclareModuleType  _) -> log_outline (fun () -> Format.sprintf "BEGIN MODULE %s" (string_of_id document id)); Some BeginModule, ""
      | VernacSynterp (Synterp.EVernacDefineModule  _) -> log_outline (fun () -> Format.sprintf "BEGIN MODULE %s" (string_of_id document id)); Some BeginModule, ""
      | VernacSynterp (Synterp.EVernacDeclareModule  _) -> log_outline (fun () -> Format.sprintf "BEGIN MODULE %s" (string_of_id document id)); Some BeginModule, ""
      | VernacSynterp (Synterp.EVernacEndSegment  _) -> log_outline (fun () -> Format.sprintf "END SEGMENT"); Some End, ""
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
    LM.fold (fun _ s -> record_outline document s) sentences_by_end []


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
  let sentence = { parsing_start; start; stop; ast; id; synterp_state; scheduler_state_before; scheduler_state_after } in
  let document = { 
    parsed with sentences_by_end = LM.add stop sentence parsed.sentences_by_end;
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
    (List.map (fun (_,x) -> Sentence x) @@ LM.bindings parsed.sentences_by_end) ;
    (List.map (fun (_,x) -> ParsingError x) @@ LM.bindings parsed.parsing_errors_by_end) ;
    []  (* todo comments *)
   ]

let sentences_sorted_by_loc parsed =
  List.sort (fun ({start = s1} : sentence) {start = s2} -> s1 - s2) @@ List.map snd @@ SM.bindings parsed.sentences_by_id

let sentences_before parsed loc =
  let (before,ov,_after) = LM.split loc parsed.sentences_by_end in
  let before = Option.cata (fun v -> LM.add loc v before) before ov in
  List.map (fun (_id,s) -> s) @@ LM.bindings before

let sentences_after_w_ids parsed loc =
  let (_before,ov,after) = LM.split loc parsed.sentences_by_end in
  let after = Option.cata (fun v -> LM.add loc v after) after ov in
  let ids, l_rev = LM.fold (fun _ s (acc,l) -> SS.add s.id acc, s::l) after (SS.empty,[]) in
  List.rev l_rev, ids

let sentences_strictly_after parsed loc =
  let (_before,_ov,after) = LM.split loc parsed.sentences_by_end in
  List.filter_map (fun (_id,s) -> if s.parsing_start > loc then Some s else None) @@ LM.bindings after

let parsing_errors_before parsed loc =
  LM.filter (fun stop _v -> stop <= loc) parsed.parsing_errors_by_end

let parsing_errors_after parsed loc =
  let (_before,ov,after) = LM.split loc parsed.parsing_errors_by_end in
  Option.cata (fun v -> LM.add loc v after) after ov

let comments_before parsed loc =
  LM.filter (fun stop _v -> stop <= loc) parsed.comments_by_end

let comments_after parsed loc =
  let (_before,ov,after) = LM.split loc parsed.comments_by_end in
  Option.cata (fun v -> LM.add loc v after) after ov

let get_sentence parsed id =
  SM.find_opt id parsed.sentences_by_id

let find_sentence parsed loc =
  match LM.find_first_opt (fun k -> loc <= k) parsed.sentences_by_end with
  | Some (_, sentence) when sentence.start < loc -> Some sentence
  | _ -> None

let find_sentence_before parsed loc =
  match LM.find_last_opt (fun k -> k <= loc) parsed.sentences_by_end with
  | Some (_, sentence) -> Some sentence
  | _ -> None

let find_sentence_strictly_before parsed loc =
  match LM.find_last_opt (fun k -> k < loc) parsed.sentences_by_end with
  | Some (_, sentence) -> Some sentence
  | _ -> None

let find_sentence_after parsed loc = 
  match LM.find_first_opt (fun k -> loc <= k) parsed.sentences_by_end with
  | Some (_, sentence) -> Some sentence
  | _ -> None

let find_next_qed parsed loc =
  let exception Found of sentence in
  let f k sentence =
    if loc <= k then
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

let get_first_sentence parsed = 
  Option.map snd @@ LM.find_first_opt (fun _ -> true) parsed.sentences_by_end

let get_last_sentence parsed = 
  Option.map snd @@ LM.find_last_opt (fun _ -> true) parsed.sentences_by_end

let state_after_sentence parsed = function
  | Some (stop, { synterp_state; scheduler_state_after }) ->
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

let string_of_parsed_ast { tokens } = 
  (* TODO implement printer for vernac_entry *)
  "Ok [" ^ String.concat "--" (List.map (Tok.extract_string false) tokens) ^ "]"

let string_of_parsed_ast = function
| Error e -> "Er [" ^ e.str ^ "]"
| Parsed ast -> string_of_parsed_ast ast

let string_of_sentence ({ ast; parsing_start; stop } : sentence) = string_of_parsed_ast ast ^ Printf.sprintf " %d-%d" parsing_start stop
let string_of_presentence ({ ast; parsing_start; stop } : pre_sentence) = string_of_parsed_ast ast ^ Printf.sprintf " %d-%d" parsing_start stop

type o = Reparsed of pre_sentence | NotReparsed of int * sentence

let shift_qf _ x = x
let shift_located _ x = x
let shift_parsed_ast _ (x : parsed_ast) = x

let shift_error i { qf; start; stop; msg; str } =
  { qf = Option.map (List.map (shift_qf i)) qf; start = start + i; stop = stop + i; msg = shift_located i msg; str }

let shift_ast i = function
  | Parsed x -> Parsed (shift_parsed_ast i x)
  | Error x -> Error (shift_error i x)
let shift_sentence i (x : sentence) = { x with start = x.start + i; stop = x.stop + i; parsing_start = x.parsing_start + i; ast = shift_ast i x.ast }

let shift_sentences i l = List.map (shift_sentence i) l

let shift_errors shift (errors : parsing_error LM.t) =
  LM.shift ((+) shift) (shift_error shift) errors

let shift_comment i {start; stop; content } = 
  {start = start + i; stop = stop + i; content }

let shift_comments shift (comments : comment LM.t) =
  LM.shift ((+) shift) (shift_comment shift) comments

let patch_sentence parsed scheduler_state_before id x =
  let o = SM.find id parsed.sentences_by_id in
  log_diff (fun () -> Format.sprintf "Patching sentence %s , %s" (Stateid.to_string id) (string_of_sentence o));
  let parsing_start, ast, start, stop, synterp_state =
    match x with
    | Reparsed { parsing_start; ast; start; stop; synterp_state } -> parsing_start, ast, start, stop, synterp_state
    | NotReparsed (shift,s) ->
      let { parsing_start; ast; start; stop; synterp_state } = shift_sentence shift s in
      log_diff (fun () -> Format.sprintf "Shifting it by %d" shift);
      parsing_start, ast, start, stop, synterp_state in
  let scheduler_state_after, schedule =
    match ast with
    | Error {msg} ->
      scheduler_state_before, Scheduler.schedule_errored_sentence id msg synterp_state parsed.schedule
    | Parsed ast ->
      let ast = (ast.ast, ast.classification, synterp_state) in
      Scheduler.schedule_sentence (id,ast) scheduler_state_before parsed.schedule
  in
  let n = { o with ast; parsing_start; start; stop; scheduler_state_before; scheduler_state_after } in
  let sentences_by_id = SM.add id n parsed.sentences_by_id in
  let sentences_by_end = match LM.find_opt o.stop parsed.sentences_by_end with
  | Some { id } when Stateid.equal id n.id ->
    LM.remove o.stop parsed.sentences_by_end 
  | _ -> parsed.sentences_by_end
  in
  let sentences_by_end = LM.add n.stop n sentences_by_end in
  { parsed with sentences_by_end; sentences_by_id; schedule }, scheduler_state_after


type diff =
  | Deleted of sentence_id list
  | Added of pre_sentence list
  | Equal of (sentence_id * o) list

let mkDeleted l = if l = [] then [] else [Deleted l]
let mkAdded l = if l = [] then [] else [Added l]
let mkEqual l = if l = [] then [] else [Equal l]


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
  
let same_tokens2 (s1 : sentence) (s2 : sentence) =
  match s1.ast, s2.ast with
  | Error e1, Error e2 -> same_errors e1 e2
  | Parsed ast1, Parsed ast2 ->
    CList.equal tok_equal ast1.tokens ast2.tokens
  | _, _ -> false

let identical (n:pre_sentence) _shift (s:sentence) =
  (* shift + s.stop = n.stop &&
  shift + s.start = n.start &&
  shift + s.parsing_start = n.parsing_start && *)
  same_tokens s n

let overlaps (n:pre_sentence) shift (s:sentence) =
    n.stop > s.parsing_start + shift

let len_of (s : sentence) = s.stop - s.parsing_start

(* TODO improve diff strategy (insertions,etc) *)
let rec diff olds news shift after =
  match olds, news, after with
  | [], [], _ :: _ -> log_diff (fun () ->"end: all after");
    mkEqual (List.map (fun s -> s.id,NotReparsed(shift,s)) after)
  | [], [n], a :: after when identical n shift a -> log_diff (fun () ->"step: drop after, unshift");
    diff [] [] (shift(*-len_of a*)) (a :: after)
  | [], [n], a :: after when overlaps n shift a -> log_diff (fun () ->"step: del after overlap");
    Deleted [a.id] :: diff [] [n] shift after
  (* | [], [n], after -> log_diff (fun () ->"d1");
    Added [n] :: diff [] [] shift after *)
  | [], n :: (_ as news), after -> log_diff (fun () ->"step: add new");
    Added [n] :: diff [] news shift after
  
  | [o], [], a :: after when same_tokens2 a o -> log_diff (fun () ->"end: eq o a, eq after");
    mkEqual [o.id, NotReparsed(0,a)] @ mkEqual (List.map (fun s -> s.id,NotReparsed(shift,s)) after)
  | olds, [], after -> log_diff (fun () -> "end: del olds, eq after");
    mkDeleted (List.map (fun s -> s.id) olds) @ mkEqual (List.map (fun s -> s.id,NotReparsed(shift,s)) after)
  | o::olds, n::news, after when same_tokens o n -> log_diff (fun () ->"step: eq old new");
      Equal [(o.id,Reparsed n)] :: diff olds news shift after
  | o::olds, news, after -> log_diff (fun () ->"step: del old");
      Deleted [o.id] :: diff olds news shift after

let diff o n s a =
  log_diff (fun () -> Printf.sprintf "diff: old:\n  %s" (String.concat "\n  " @@ List.map string_of_sentence o));
  log_diff (fun () -> Printf.sprintf "diff: new:\n  %s" (String.concat "\n  " @@ List.map string_of_presentence n));
  log_diff (fun () -> Printf.sprintf "diff: after (shift %d):\n  %s" s (String.concat "\n  " @@ List.map string_of_sentence a));
  diff o n s a

let string_of_diff_item doc = function
  | Deleted ids ->
      let get_str id = match get_sentence doc id with
      | None -> "missing from doc"
      | Some s -> string_of_sentence s
      in
       ids |> List.map (fun id -> Printf.sprintf "- (id: %d) %s" (Stateid.to_int id) (get_str id))
  | Added sentences ->
       sentences |> List.map (fun (s : pre_sentence) -> Printf.sprintf "+ %s" (string_of_presentence s))
  | Equal l ->
       l |> List.map (function
             | (id, Reparsed (s : pre_sentence)) -> Printf.sprintf "= (id: %d) %s" (Stateid.to_int id) (string_of_presentence s)
             | (id, NotReparsed (shift, (s : sentence))) -> Printf.sprintf "= (id: %d) %d >> %s" (Stateid.to_int id) shift (string_of_sentence s))

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


let handle_parse_error start parsing_start msg qf ({stream; errors; parsed;} as parse_state) synterp_state =
  let stop = Stream.count stream in
  log_parsing (fun () -> Printf.sprintf "handling parse error %d - %d" start stop);
  let str = String.sub (RawDocument.text parse_state.raw) parsing_start (stop - parsing_start) in
  let parsing_error = { msg; start; stop; qf; str} in
  let sentence = { parsing_start; ast = Error parsing_error; start; stop; synterp_state } in
  let parsed = sentence :: parsed in
  let errors = parsing_error :: errors in
  let parse_state = {parse_state with errors; parsed} in
  (* TODO: we could count the \n between start and stop and increase Loc.line_nb *)
  create_parsing_event (ParseEvent parse_state)

let changes_grammar entry classification =
  match entry.CAst.v.Vernacexpr.expr with
  | Vernacexpr.VernacSynPure _ -> false
  | _ -> 
    match classification with
    | Vernacextend.VtProofStep _ -> false
    | _ -> true

let handle_parse_more ({loc; synterp_state; stream; raw; parsed; parsed_comments; parsing_request_range} as parse_state) =
  let start = Stream.count stream in
  if start > parsing_request_range.stop then begin
    log_parsing (fun () -> "End of unparsed area");
    create_parsing_event (Invalidate { ps = parse_state; stopped_here = Some start })
  end else
    begin
    log_parsing (fun () -> Printf.sprintf "Start of parse is %d <= %d" start parsing_request_range.stop);
    (* FIXME should we save lexer state? *)
    match parse_one_sentence ?loc stream ~st:synterp_state with
    | None, _ (* EOI *) ->
        log_parsing (fun () -> "End of stream");
        create_parsing_event (Invalidate { ps = parse_state; stopped_here = None })
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
          log_parsing (fun () -> "Parsed: " ^ (Pp.string_of_ppcmds @@ Ppvernac.pr_vernac ast));
          let entry = get_entry ast in
          let classification = Vernac_classifier.classify_vernac ast in
          let synterp_state = Vernacstate.Synterp.freeze () in
          let parsed_ast = Parsed { ast = entry; classification; tokens } in
          let sentence = { parsing_start = start; ast = parsed_ast; start = begin_char; stop; synterp_state } in
          let parsed = sentence :: parsed in
          let comments = List.map (fun ((start, stop), content) -> {start; stop; content}) comments in
          let parsed_comments = List.append comments parsed_comments in
          let loc = ast.loc in
          let parsing_request_range = if changes_grammar entry classification then { parsing_request_range with stop = max_int } else parsing_request_range in
          let parse_state = {parse_state with parsing_request_range; parsed_comments; parsed; loc; synterp_state} in
          create_parsing_event (ParseEvent parse_state)
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

let ast_of = function Reparsed s -> s.ast | NotReparsed(_,s) -> s.ast

let rec unchanged_id id = function
  | [] -> id
  | Equal s :: diffs ->
    let get_id_ignore_error id_option (id, s) =
      match ast_of s with
        | Error _ -> id_option
        | Parsed _ ->  Some id
    in
    unchanged_id (List.fold_left get_id_ignore_error id s) diffs
  | (Added _ | Deleted _) :: _ -> id

let string_of_doc doc =
  let sentences = LM.bindings @@ LM.map (fun s -> Stateid.to_string s.id ^ ": " ^ string_of_sentence s) doc.sentences_by_end in
  let sentences = List.map snd sentences in
  String.concat "\n" sentences

let invalidate top_edit top_id parsed_doc olds news (shift,after) =
  let rec add_new_or_patch parsed_doc scheduler_state = function
    | [] -> parsed_doc
    | Deleted _ :: diffs -> add_new_or_patch parsed_doc scheduler_state diffs
    | Equal s :: diffs ->
      let patch_sentence (parsed_doc,scheduler_state) (id,new_s) =
        patch_sentence parsed_doc scheduler_state id new_s
      in
      let parsed_doc, scheduler_state = List.fold_left patch_sentence (parsed_doc, scheduler_state) s in
      add_new_or_patch parsed_doc scheduler_state diffs
    | Added news :: diffs ->
    (* FIXME could have side effect on the following, unchanged sentences *)
      let add_sentence (parsed_doc,scheduler_state) ({ parsing_start; start; stop; ast; synterp_state } : pre_sentence) =
        add_sentence parsed_doc parsing_start start stop ast synterp_state scheduler_state
      in
      let parsed_doc, scheduler_state = List.fold_left add_sentence (parsed_doc,scheduler_state) news in
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
  log_diff (fun () -> Format.sprintf "Top edit: %i, New sentences: %d" top_edit (List.length news));
  (* let olds = sentences_after parsed_doc top_edit in *)
  let t0 = Unix.gettimeofday () in
  let diff = diff olds news shift after in
  let t1 = Unix.gettimeofday () in
  log_diff (fun () -> "diff:\n" ^ string_of_diff parsed_doc diff);
  let parsed_doc, invalid_ids = remove_old parsed_doc Stateid.Set.empty diff in
  let t2 = Unix.gettimeofday () in
  let parsed_doc = add_new_or_patch parsed_doc scheduler_state diff in
  let t3 = Unix.gettimeofday () in
  log_diff ~force:true (fun () -> Format.sprintf "Time diff:%5.3f rem:%5.3f add/patch:%5.3f\n" (t1 -. t0) (t2 -. t1) (t3 -. t2));
  let unchanged_id = unchanged_id top_id diff in
  log_diff (fun () -> Format.sprintf "Updated document:\n%s" (string_of_doc parsed_doc));
  log_diff (fun () -> "unchanged id: " ^ Option.cata Stateid.to_string "none" unchanged_id);
  unchanged_id, invalid_ids, { parsed_doc with unparsed_range = None; }

(** Validate document when raw text has changed *)
let validate_document ({ unparsed_range; raw_doc; cancel_handle } as document) =
  match unparsed_range with
  | None -> document,[] (* already valid *)
  | Some { start; stop; shift_after_stop } ->
  (* Cancel any previous parsing event *)
  Option.iter Sel.Event.cancel cancel_handle;
  (* We take the state strictly before parsed_loc to cover the case when the
  end of the sentence is editted *)
  let (sentence_before_stop, synterp_state, _scheduler_state) = state_strictly_before document start in
  let sentence_after_stop =
    match find_sentence document stop with
    | Some x -> x.stop
    | None -> stop in
  (* let top_id = find_sentence_strictly_before document parsed_loc with None -> Top | Some sentence -> Id sentence.id in *)
  let top_id = Option.map (fun sentence -> sentence.id) (find_sentence_strictly_before document start) in
  let text = RawDocument.text raw_doc in
  let stream = Stream.of_string text in
  while Stream.count stream < sentence_before_stop do Stream.junk () stream done;
  log_validate (fun () -> Format.sprintf "Parsing more from pos %i to pos %i" sentence_before_stop sentence_after_stop);
  let started = Unix.gettimeofday () in
  let parsing_request_range = { shift_after_stop; start = sentence_before_stop; stop = sentence_after_stop; } in
  let parsed_state = { 
    parsing_request_range;
    top_id;synterp_state; stream; raw=raw_doc; parsed=[]; errors=[]; parsed_comments=[]; loc=None; started; previous_document=document} in
  let priority = Some PriorityManager.parsing in
  let event = Sel.now ?priority (ParseEvent parsed_state) in
  let cancel_handle = Some (Sel.Event.get_cancellation_handle event) in
  {document with cancel_handle}, [event]


  (* TODO : clarify what is previous doc vs doc *)
let handle_invalidate {parsed; errors; parsed_comments; parsing_request_range = { shift_after_stop; start; stop }; top_id; started; previous_document} parsing_stopped_here document =
  let end_ = Unix.gettimeofday ()in
  let time = end_ -. started in
  (* log_validate (fun () -> Format.sprintf "Parsing phase ended in %5.3f" time); *)
  log_validate ~force:true (fun () -> Format.sprintf "Parsing phase ended in %5.3f at %s (request was %d)\n%!"
    time (Option.cata string_of_int "EOF" parsing_stopped_here) stop);
  let news = List.rev parsed in
  let new_comments = List.rev parsed_comments in
  let new_errors = errors in
  log_validate (fun () -> Format.sprintf "%i new sentences" (List.length news));
  log_validate (fun () -> Format.sprintf "%i new errors" (List.length new_errors));
  log_validate (fun () -> Format.sprintf "%i new comments" (List.length new_comments));
  let top_edit = start+1 in
  let end1_ = Unix.gettimeofday ()in

  let olds, after =
    let olds, _ = sentences_after_w_ids document top_edit in
    if stop = max_int then
      olds, [] (* FIXME: this means we parsed a grammar changing command and we reparsed everything ... make this clear in the type *)
    else
      let after, after_set =
        match parsing_stopped_here with
        | None -> [], SS.empty
        | Some parsing_stopped_here -> sentences_after_w_ids (*previous_*)document parsing_stopped_here in
      (* TODO slow *)
      List.filter (fun x -> not(SS.mem x.id after_set)) olds, after in
  log_validate (fun () -> Format.sprintf "old stuff after shifted by %d" shift_after_stop);
  (* error = old + new *)
  (* let errors_before = parsing_errors_before document start_here in
  let errors_after = shift_errors shift @@ parsing_errors_after previous_document stop_here in
  let errors = LM.union (fun _ _ _ -> assert false) errors_before errors_after in
  let parsing_errors_by_end = List.fold_left (fun acc (error : parsing_error) -> LM.add error.stop error acc) errors new_errors in *)
  (* comments = old + new *)

  let comments_before = comments_before document start in
  let comments_after = shift_comments shift_after_stop @@ comments_after previous_document stop in
  let comments = LM.union (fun _ _ _ -> assert false) comments_before comments_after in
  let comments_by_end = List.fold_left (fun acc (comment : comment) -> LM.add comment.stop comment acc) comments new_comments in
  (* sentences = diff old new *)
  (* let after = shift_sentences shift after in *)
  log_validate (fun () -> 
    let sentence_string = String.concat " " @@ List.map (fun s -> string_of_sentence s) after in
    Format.sprintf "%i after %d: %s" (List.length after) stop sentence_string);
  let unchanged_id, invalid_ids, document = invalidate top_edit top_id document olds news (shift_after_stop,after) in
  let parsing_errors_by_end = LM.filter_map (fun _ x -> match x.ast with Parsed _ -> None | Error e -> Some e) document.sentences_by_end in
  let parsed_document = {document with parsing_errors_by_end; comments_by_end} in
  let end2_ = Unix.gettimeofday ()in
  log_validate ~force:true (fun () -> Printf.sprintf "valid: %5.3f" (end2_ -. end1_));
  Some {parsed_document; unchanged_id; invalid_ids; previous_document}

let handle_event document = function
| ParseEvent state -> 
  let event = handle_parse_more state in
  let cancel_handle = Some (Sel.Event.get_cancellation_handle event) in
  {document with cancel_handle}, [event], None
| Invalidate { ps = state; stopped_here } -> {document with cancel_handle=None}, [], handle_invalidate state stopped_here document

let create_document init_synterp_state text =
  let raw_doc = RawDocument.create text in
    { 
      unparsed_range = Some { start = 0; stop = String.length text; shift_after_stop = 0 };
      raw_doc;
      sentences_by_id = SM.empty;
      sentences_by_end = LM.empty;
      parsing_errors_by_end = LM.empty;
      comments_by_end = LM.empty;
      schedule = initial_schedule;
      init_synterp_state;
      cancel_handle = None;
    }

let apply_1edit ((shift, unparsed_start, unparsed_stop),raw_doc) edit =
  let raw_doc, { RawDocument.start; stop; shift_after_stop } = RawDocument.apply_text_edit raw_doc edit in
  log_validate (fun () -> Printf.sprintf "Text edits fom %i to %i shift %d atop (%d,%d,%d)" start stop shift_after_stop shift unparsed_start unparsed_stop);
  let shift = shift + shift_after_stop in
  let unparsed_start = min unparsed_start start in
  let unparsed_stop = max unparsed_stop stop in
  log_validate (fun () -> Printf.sprintf "Text edits result in unparsed %i - %i with shift %d" unparsed_start unparsed_stop shift);
  (shift, unparsed_start,unparsed_stop), raw_doc

let apply_text_edits document edits =
  let doc = (0,max_int,min_int), document.raw_doc in
  let (shift_after_stop, start,stop), raw_doc =
    List.fold_left apply_1edit doc edits in
  { document with raw_doc; unparsed_range = Some { shift_after_stop; start; stop} }

let apply_text_edit d e = apply_text_edits d [e]

let unparsed_range d = d.unparsed_range

module Internal = struct

  let string_of_sentence sentence =
    Format.sprintf "[%s] %s (%i -> %i)" (Stateid.to_string sentence.id)
    (string_of_sentence sentence)
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
