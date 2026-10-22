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

let log = Log.mk_log "document"
let log_parsing = Log.mk_log "document.parsing"
let log_diff = Log.mk_log "document.diff"
let log_validate = Log.mk_log "document.validate"

module LM = struct
  include Map.Make (Int)
  let shift fk fv m = fold (fun k v m -> add (fk k) (fv v) m) m empty
end

module SM = Map.Make (Stateid)

type parsed_ast = {
  ast: Synterp.vernac_control_entry;
  classification: Vernacextend.vernac_classification;
  tokens: (Loc.t * Tok.t) list
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
  id : sentence_id;
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
  ast_shift : int; (* how far the sentence moved since [ast] was parsed; the
                      locations inside [ast] are behind by this amount *)
  id : sentence_id;
  messages : feedback_message list;
  checked : sentence_checking_result option;
}

(* The range of the last parsed text that is touched by the edits since then.
   [start, stop) is a range of offsets in the last parsed text, and
   [shift_after_stop] is how far the text from [stop] on has moved. *)
type pending_edits_range = {
  start : int;
  stop : int;
  shift_after_stop : int;
}

type document = {
  sentences_by_id : sentence SM.t;
  sentences_by_end : sentence_id LM.t;
  parsing_errors_by_end : parsing_error LM.t;
  comments_by_end : comment LM.t;
  schedule : Scheduler.schedule;
  pending_edits_range : pending_edits_range option; (* [None] when nothing changed since the last parse *)
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

(* The range to parse again, widened from the pending edits range to whole
   sentences. [start] and [stop] are offsets in the last parsed text. *)
type parsing_request_range = {
  start : int; (* the end of the last sentence before the edits, where parsing starts, or -1 if there is none *)
  stop : int; (* parsing stops at the first sentence that starts at or after it, [max_int] to parse to the end of the text *)
  shift_after_stop : int; (* how far the text after the edits has moved *)
}

type parse_state = {
  started: float;
  parsing_request_range: parsing_request_range;
  stopped_here: int option; (* where parsing stopped before EOF; None = reached end of stream *)
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

let range_of_sentence_with_blank_space raw (sentence : sentence) =
  let start = RawDocument.position_of_loc raw sentence.parsing_start in
  let end_ = RawDocument.position_of_loc raw sentence.stop in
  Range.{ start; end_ }

let tokens_of_sentence (sentence: sentence) =
  match sentence.ast with
  (* TODO: we could collect (best-effort) tokens for failed parsing too *)
  | Error _ -> []
  | Parsed { tokens } -> tokens

let token_at_loc sentence loc =
  let contains (Loc.{ bp; ep }) = bp <= loc && loc <= ep in
  List.find_opt (fun (token_loc, _) -> contains token_loc) (tokens_of_sentence sentence) |> Option.map snd

let ast_shift document id =
  match SM.find_opt id document.sentences_by_id with
  | Some { ast_shift } -> ast_shift
  | None -> 0

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

let range_of_document document : Range.t =
  let raw = document.raw_doc in
  let start : Position.t = { line = 0; character = 0 } in
  let end_ = RawDocument.position_of_loc raw (RawDocument.end_loc raw) in
  Range.create ~end_ ~start

let schedule doc = doc.schedule

let raw_document doc = doc.raw_doc

let parse_errors parsed =
  List.map snd (LM.bindings parsed.parsing_errors_by_end)

let add_sentence parsed id parsing_start start stop (ast: sentence_state) synterp_state scheduler_state_before =
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
  let sentence = { parsing_start; start; stop; ast; id; synterp_state; scheduler_state_before; scheduler_state_after; ast_shift = 0; messages = []; checked = None } in
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

let comments parsed =
  List.map snd @@ LM.bindings parsed.comments_by_end

let get_sentence parsed id =
  SM.find_opt id parsed.sentences_by_id

let find_sentence document loc =
  match LM.find_first_opt (fun k -> loc <= k) document.sentences_by_end with
  | Some (_, sentence_id) ->
      let sentence = sentence_of_id document sentence_id in
      if sentence.start < loc then Some sentence else None
  | _ -> None

let find_sentence_before parsed loc =
  match LM.find_last_opt (fun k -> k <= loc) parsed.sentences_by_end with
  | Some (_, sentence_id) -> Some (sentence_of_id parsed sentence_id)
  | _ -> None

let find_sentence_before_pos document pos =
  let loc = RawDocument.loc_of_position (raw_document document) pos in
  find_sentence_before document loc

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

let find_sentence_at_pos document pos : sentence option =
  let raw = raw_document document in
  let loc = RawDocument.loc_of_position raw pos in
  find_sentence_after document loc

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
      | _ -> log.error (fun () -> Printf.sprintf "sentence %s is already checked, ignoring its new status (possibly a bug)" (Stateid.to_string id)); parsed

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
    log.debug (fun () -> "Received feedback on non-existing state id " ^ Stateid.to_string id ^ ": " ^ Pp.string_of_ppcmds msg);
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
  "[" ^ String.concat "--" (List.map (fun (_, tok) -> Tok.extract_string false tok) tokens) ^ "]"

let string_of_parsed_ast = function
| Error e -> "Er [" ^ e.str ^ "]"
| Parsed ast -> string_of_parsed_ast ast

let string_of_sentence ({ ast; parsing_start; stop } : sentence) = string_of_parsed_ast ast ^ Printf.sprintf " %d-%d" parsing_start stop
let string_of_presentence ({ ast; parsing_start; stop } : pre_sentence) = string_of_parsed_ast ast ^ Printf.sprintf " %d-%d" parsing_start stop

type sentence_update = Reparsed of pre_sentence | NotReparsed of int * sentence

let shift_qf i x = Quickfix.make ~loc:(Loc.shift_loc i i (Quickfix.loc x)) (Quickfix.pp x)
let shift_located i (loc, x) = Option.map (Loc.shift_loc i i) loc, x
(* The locations inside [x.ast] cannot be shifted, the sentence records the
   shift instead, see [ast_shift] *)
let shift_parsed_ast i (x : parsed_ast) =
  { x with tokens = List.map (fun (loc, tok) -> Loc.shift_loc i i loc, tok) x.tokens }

let shift_error i { qf; start; stop; msg; str } =
  { qf = Option.map (List.map (shift_qf i)) qf; start = start + i; stop = stop + i; msg = shift_located i msg; str }

let shift_ast i = function
  | Parsed x -> Parsed (shift_parsed_ast i x)
  | Error x -> Error (shift_error i x)
let shift_sentence_locations i (x : sentence) = { x with start = x.start + i; stop = x.stop + i; parsing_start = x.parsing_start + i; ast = shift_ast i x.ast }

let shift_comment i {start; stop; content } =
  {start = start + i; stop = stop + i; content }

let patch_sentence parsed scheduler_state_before id x =
  let o = SM.find id parsed.sentences_by_id in
  log_diff.debug (fun () -> Format.sprintf "Patching sentence %s , %s" (Stateid.to_string id) (string_of_sentence o));
  let parsing_start, ast, ast_shift, start, stop, synterp_state =
    match x with
    | Reparsed { parsing_start; ast; start; stop; synterp_state } -> parsing_start, ast, 0, start, stop, synterp_state
    | NotReparsed (shift,s) ->
      let { parsing_start; ast; start; stop; synterp_state } = shift_sentence_locations shift s in
      log_diff.debug (fun () -> Format.sprintf "Shifting it by %d" shift);
      let ast_shift = match ast with Parsed _ -> s.ast_shift + shift | Error _ -> 0 in
      parsing_start, ast, ast_shift, start, stop, synterp_state in
  let scheduler_state_after, schedule =
    match ast with
    | Error {msg} ->
      scheduler_state_before, Scheduler.schedule_errored_sentence id msg synterp_state parsed.schedule
    | Parsed ast ->
      let ast = (ast.ast, ast.classification, synterp_state) in
      Scheduler.schedule_sentence (id,ast) scheduler_state_before parsed.schedule
  in
  let n = { o with ast; ast_shift; parsing_start; start; stop; scheduler_state_before; scheduler_state_after } in
  let sentences_by_id = SM.add id n parsed.sentences_by_id in
  let sentences_by_end = match LM.find_opt o.stop parsed.sentences_by_end with
  | Some id when Stateid.equal id n.id ->
    LM.remove o.stop parsed.sentences_by_end
  | _ -> parsed.sentences_by_end
  in
  let sentences_by_end = LM.add n.stop id sentences_by_end in
  { parsed with sentences_by_end; sentences_by_id; schedule }, scheduler_state_after


type diff =
  | Deleted of sentence_id list
  | Added of pre_sentence list
  | Equal of (sentence_id * sentence_update) list

let mk_deleted ids = if ids = [] then [] else [Deleted ids]
let mk_equal updates = if updates = [] then [] else [Equal updates]


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

let same_tokens (ast1 : sentence_state) (ast2 : sentence_state) =
  match ast1, ast2 with
  | Error e1, Error e2 -> same_errors e1 e2
  | Parsed parsed1, Parsed parsed2 ->
    let tok_pair_equal (_, t1) (_, t2) = tok_equal t1 t2 in
    CList.equal tok_pair_equal parsed1.tokens parsed2.tokens
  | _, _ -> false

(* How many new sentences an insertion may add before an old sentence that is
   still matched. Bounded so that a reparse of the whole document stays linear. *)
let insertion_lookahead = 16

let rec matches_soon (reparsed : sentence) lookahead = function
  | [] -> false
  | (new_sentence : pre_sentence) :: new_sentences ->
    lookahead > 0
    && (same_tokens reparsed.ast new_sentence.ast
        || matches_soon reparsed (lookahead - 1) new_sentences)

let equal_kept shift_after_stop kept_sentences =
  mk_equal
    (List.map
       (fun kept -> kept.id, NotReparsed (shift_after_stop, kept))
       kept_sentences)

(* Computes the changes from the old sentences to the new ones, in text order.
   [reparsed_sentences] are the old sentences that the new parse replaced, and
   they are compared with [new_sentences]. [kept_sentences] are the old
   sentences that the parse did not reach. They stay, moved by
   [shift_after_stop]. *)
let rec diff (reparsed_sentences : sentence list)
    (new_sentences : pre_sentence list) shift_after_stop
    (kept_sentences : sentence list) =
  match reparsed_sentences, new_sentences, kept_sentences with
  (* Only kept sentences are left. They stay, moved by the shift. *)
  | [], [], _ :: _ ->
    equal_kept shift_after_stop kept_sentences
  (* No reparsed sentence is left, so the new sentence is added. *)
  | [], new_sentence :: new_sentences, _ ->
    Added [new_sentence]
    :: diff [] new_sentences shift_after_stop kept_sentences

  (* No new sentence is left, so the remaining reparsed sentences are
     deleted. *)
  | _, [], _ ->
    mk_deleted (List.map (fun reparsed -> reparsed.id) reparsed_sentences)
    @ equal_kept shift_after_stop kept_sentences
  (* The new sentence has the same tokens as the reparsed one, so it keeps the
     old id. *)
  | reparsed :: reparsed_sentences, new_sentence :: new_sentences, _
    when same_tokens reparsed.ast new_sentence.ast ->
    Equal [reparsed.id, Reparsed new_sentence]
    :: diff reparsed_sentences new_sentences shift_after_stop kept_sentences
  (* The reparsed sentence matches one of the next new sentences, so this new
     sentence is added before it. *)
  | reparsed :: _, new_sentence :: new_sentences, _
    when matches_soon reparsed insertion_lookahead new_sentences ->
    Added [new_sentence]
    :: diff reparsed_sentences new_sentences shift_after_stop kept_sentences
  (* The reparsed sentence matches none of the next new sentences, so it is
     deleted. *)
  | reparsed :: reparsed_sentences, _, _ ->
    Deleted [reparsed.id]
    :: diff reparsed_sentences new_sentences shift_after_stop kept_sentences

let string_of_diff_item doc = function
  | Deleted ids ->
    List.map
      (fun id ->
        let sentence_string =
          match get_sentence doc id with
          | None -> "missing from doc"
          | Some sentence -> string_of_sentence sentence
        in
        Printf.sprintf "- (id: %d) %s" (Stateid.to_int id) sentence_string)
      ids
  | Added new_sentences ->
    List.map
      (fun new_sentence ->
        Printf.sprintf "+ %s" (string_of_presentence new_sentence))
      new_sentences
  | Equal updates ->
    List.map
      (function
        | id, Reparsed new_sentence ->
          Printf.sprintf "= (id: %d) %s" (Stateid.to_int id)
            (string_of_presentence new_sentence)
        | id, NotReparsed (shift, sentence) ->
          Printf.sprintf "= (id: %d) %d >> %s" (Stateid.to_int id) shift
            (string_of_sentence sentence))
      updates

let string_of_diff doc diff =
  String.concat "\n" (List.concat_map (string_of_diff_item doc) diff)

[%%if rocq = "8.18" || rocq = "8.19" || rocq = "8.20"]
  let get_keyword_state = Pcoq.get_keyword_state
[%%else]
  let get_keyword_state = Procq.get_keyword_state
[%%endif]

[%%if rocq = "8.18" || rocq = "8.19" || rocq = "8.20" || rocq = "9.0" || rocq = "9.1"]
let rec stream_tok acc str (start_loc: Loc.t) =
  let e = LStream.next (get_keyword_state ()) str in
  match e with
  | Tok.EOI ->
    List.rev acc
  | _ ->
    let tok_loc = LStream.current_loc str in
    let loc = Loc.shift_loc start_loc.bp start_loc.bp tok_loc in
    stream_tok ((loc, e)::acc) str start_loc
[%%else]
let rec stream_tok acc str (start_loc: Loc.t) =
  let e = LStream.next (get_keyword_state ()) str in
  match e with
  | Some Tok.EOI ->
    List.rev acc
  | Some e ->
    let tok_loc = LStream.current_loc str in
    let loc = Loc.shift_loc start_loc.bp start_loc.bp tok_loc in
    stream_tok ((loc, e)::acc) str start_loc
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

let get_raw_text_tokens raw_doc begin_char end_char ast_loc =
  let str = String.sub (RawDocument.text raw_doc) begin_char (end_char - begin_char) in
  let sstr = Stream.of_string str in
  let lex = CLexer.Lexer.tok_func sstr in
  stream_tok [] lex ast_loc

let changes_grammar entry classification =
  match entry.CAst.v.Vernacexpr.expr with
  | Vernacexpr.VernacSynPure _ -> false        (* Lemma, Definition, Check, ...: no synterp effect *)
  | _ -> match classification with
         | Vernacextend.VtProofStep _ -> false
         | _ -> true                           (* Notation, Require, Import, Section, Module, ... *)

let rec handle_parse_error id start parsing_start msg qf ({stream; errors; parsed;} as parse_state) synterp_state =
  let stop = Stream.count stream in
  log_parsing.debug (fun () -> Printf.sprintf "handling parse error %d - %d" start stop);
  let str = String.sub (RawDocument.text parse_state.raw) parsing_start (stop - parsing_start) in
  let parsing_error = { msg; start; stop; qf; str} in
  let sentence = { id; parsing_start; ast = Error parsing_error; start; stop; synterp_state } in
  let parsed = sentence :: parsed in
  let errors = parsing_error :: errors in
  let parse_state = {parse_state with errors; parsed} in
  (* TODO: we could count the \n between start and stop and increase Loc.line_nb *)
  true, parse_state

and parse_more ({loc; synterp_state; stream; raw; parsed; parsed_comments; parsing_request_range} as parse_state) : bool * parse_state =
  let next_start = Stream.count stream in
  (* Stops parsing past the edit's impact range, at a location where an old
     sentence ended. The old sentences after it then start where the new ones
     end, so they can be kept. The range and the old sentences are in the
     offsets of the last parsed text, the stream in the current one. *)
  let { stop = parse_stop; shift_after_stop } = parsing_request_range in
  let next_start_before_edits = next_start - shift_after_stop in
  if parse_stop <> max_int && next_start_before_edits >= parse_stop
     && LM.mem next_start_before_edits parse_state.previous_document.sentences_by_end
  then begin
    log_parsing.debug (fun () -> "End of unparsed area");
    false, { parse_state with stopped_here = Some next_start }
  end else
    begin
    log_parsing.debug (fun () -> Printf.sprintf "Start of parse is %d <= %d" next_start parse_stop);
    (* FIXME should we save lexer state? *)
    match parse_one_sentence ?loc stream ~st:synterp_state with
    | None, _ (* EOI *) ->
        log_parsing.debug (fun () -> "End of stream");
        false, parse_state
    | Some ast, comments ->
      let id = Stateid.fresh () in
      let stop = Stream.count stream in
      let ast_loc = match ast.loc with
        | Some lc -> lc
        | None -> assert false
      in
      let start = ast_loc.bp in
      let tokens = get_raw_text_tokens raw start ast_loc.ep ast_loc in
      begin
        try
          log_parsing.debug (fun () -> "Parsed: " ^ (Pp.string_of_ppcmds @@ Ppvernac.pr_vernac ast));
          Feedback.set_id_for_feedback parse_state.previous_document.doc_id id;
          let entry = get_entry ast in
          let classification = Vernac_classifier.classify_vernac ast in
          let synterp_state = Vernacstate.Synterp.freeze () in
          let parsed_ast = Parsed { ast = entry; classification; tokens } in
          let sentence = { id; parsing_start = next_start; ast = parsed_ast; start; stop; synterp_state } in
          let parsed = sentence :: parsed in
          let comments = List.map (fun ((start, stop), content) -> {start; stop; content}) comments in
          let parsed_comments = List.append comments parsed_comments in
          let loc = ast.loc in
          let parsing_request_range = if changes_grammar entry classification then { parsing_request_range with stop = max_int } else parsing_request_range in
          let parse_state = {parse_state with parsing_request_range; parsed_comments; parsed; loc; synterp_state} in
          true, parse_state
        with exn ->
          let e, info = Exninfo.capture exn in
          let loc = get_loc_from_info_or_exn e info in
          let qf = Result.value ~default:[] @@ Quickfix.from_exception e in
          handle_parse_error id next_start start (loc, CErrors.iprint_no_report (e,info)) (Some qf) parse_state synterp_state
        end
    | exception (E _ as exn) ->
      let id = Stateid.fresh () in
      let e, info = Exninfo.capture exn in
      let loc = get_loc_from_info_or_exn e info in
      let qf = Result.value ~default:[] @@ Quickfix.from_exception e in
      junk_sentence_end stream;
      handle_parse_error id next_start next_start (loc, CErrors.iprint_no_report (e, info)) (Some qf) {parse_state with stream} synterp_state
    | exception (CLexer.Error.E _ as exn) -> (* May be more problematic to handle for the diff *)
      let id = Stateid.fresh () in
      let e, info = Exninfo.capture exn in
      let loc = get_loc_from_info_or_exn e info in
      let qf = Result.value ~default:[] @@ Quickfix.from_exception exn in
      junk_sentence_end stream;
      handle_parse_error id next_start next_start (loc,CErrors.iprint_no_report (e, info)) (Some qf) {parse_state with stream} synterp_state
    | exception exn ->
      let id = Stateid.fresh () in
      let e, info = Exninfo.capture exn in
      let loc = Loc.get_loc @@ info in
      let qf = Result.value ~default:[] @@ Quickfix.from_exception exn in
      junk_sentence_end stream;
      handle_parse_error id next_start next_start (loc, CErrors.iprint_no_report (e,info)) (Some qf) {parse_state with stream} synterp_state
  end
and create_parse_event ~doc_id parse_state =
  let priority = Some PriorityManager.parsing in
  Sel.On.promise ~name:"Parse" ?priority (ProverThread.eventually_run ~doc_id ~name:"create_parse_event" (fun () -> parse_more parse_state)) (fun x -> Parse x)

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

let rec add_new_or_patch parsed_doc scheduler_state = function
  | [] -> parsed_doc
  | Deleted _ :: diffs -> add_new_or_patch parsed_doc scheduler_state diffs
  | Equal s :: diffs ->
    let parsed_doc, scheduler_state =
      List.fold_left
        (fun (parsed_doc, scheduler_state) (id, new_s) ->
          patch_sentence parsed_doc scheduler_state id new_s)
        (parsed_doc, scheduler_state) s
    in
    add_new_or_patch parsed_doc scheduler_state diffs
  | Added news :: diffs ->
    (* FIXME could have side effect on the following, unchanged sentences *)
    let parsed_doc, scheduler_state =
      List.fold_left
        (fun (parsed_doc, scheduler_state)
             ({ id; parsing_start; start; stop; ast; synterp_state } : pre_sentence) ->
          add_sentence parsed_doc id parsing_start start stop ast synterp_state
            scheduler_state)
        (parsed_doc, scheduler_state) news
    in
    add_new_or_patch parsed_doc scheduler_state diffs

(* [after_deletion] tells whether the additions being walked follow a
   deletion, whose dependents include the sentence kept after them. *)
let rec remove_old ~after_deletion parsed_doc invalid_ids = function
  | [] -> parsed_doc, invalid_ids
  | Deleted ids :: diffs ->
    let invalid_ids =
      List.fold_left (fun ids id -> Stateid.Set.add id ids) invalid_ids ids
    in
    let parsed_doc = List.fold_left remove_sentence parsed_doc ids in
    (* FIXME update scheduler state, maybe invalidate after diff zone *)
    remove_old ~after_deletion:true parsed_doc invalid_ids diffs
  | Added _ :: (Equal ((id, _) :: _) :: _ as diffs) when not after_deletion ->
    (* The first sentence kept after an insertion runs from another state;
       invalidating it also invalidates its dependents. *)
    let invalid_ids = Stateid.Set.add id invalid_ids in
    remove_old ~after_deletion:false parsed_doc invalid_ids diffs
  | Added _ :: diffs -> remove_old ~after_deletion parsed_doc invalid_ids diffs
  | Equal _ :: diffs ->
    remove_old ~after_deletion:false parsed_doc invalid_ids diffs

let log_diff_inputs reparsed_sentences new_sentences ~shift_after_stop
    ~kept_sentences =
  log_diff.debug (fun () ->
      Printf.sprintf "diff: reparsed:\n  %s"
        (String.concat "\n  " @@ List.map string_of_sentence reparsed_sentences));
  log_diff.debug (fun () ->
      Printf.sprintf "diff: new:\n  %s"
        (String.concat "\n  " @@ List.map string_of_presentence new_sentences));
  log_diff.debug (fun () ->
      Printf.sprintf "diff: kept, shifted by %d:\n  %s" shift_after_stop
        (String.concat "\n  " @@ List.map string_of_sentence kept_sentences))

let invalidate top_edit top_id parsed_doc reparsed_sentences new_sentences
    ~shift_after_stop ~kept_sentences =
  let _, _, scheduler_state = state_at_pos parsed_doc top_edit in
  log_diff_inputs reparsed_sentences new_sentences ~shift_after_stop
    ~kept_sentences;
  let diff =
    diff reparsed_sentences new_sentences shift_after_stop kept_sentences
  in
  log_diff.debug (fun () ->
      Printf.sprintf "diff:\n%s" (string_of_diff parsed_doc diff));
  let parsed_doc, invalid_ids =
    remove_old ~after_deletion:false parsed_doc Stateid.Set.empty diff
  in
  let parsed_doc = add_new_or_patch parsed_doc scheduler_state diff in
  let unchanged_id = unchanged_id top_id diff in
  unchanged_id, invalid_ids, { parsed_doc with pending_edits_range = None }

let sentence_changes_grammar document id =
  match (sentence_of_id document id).ast with
  | Parsed { ast; classification } -> changes_grammar ast classification
  | Error _ -> false

(* Whether an old sentence touched by an edit of [start, stop] changes the
   grammar. Once edited it may be gone, so the sentences after it must be parsed
   again even if no new sentence changes the grammar. The touched sentences
   are the ones ending in [start, stop] and the first one ending after it,
   whose parsing starts at or before [stop]. *)
let edits_grammar_change document start stop =
  let _, at_start, after_start = LM.split start document.sentences_by_end in
  let inside, at_stop, after_stop = LM.split stop after_start in
  Option.cata (fun id -> sentence_changes_grammar document id) false at_start
  || LM.exists (fun _ id -> sentence_changes_grammar document id) inside
  || Option.cata (fun id -> sentence_changes_grammar document id) false at_stop
  || match LM.min_binding_opt after_stop with
     | Some (_, id) -> (sentence_of_id document id).parsing_start <= stop && sentence_changes_grammar document id
     | None -> false

let stream_from raw_doc parse_start =
  let text = RawDocument.text raw_doc in
  let stream = Stream.of_string text in
  while Stream.count stream < parse_start do Stream.junk () stream done;
  stream

(* Returns the end of the sentence that the edit ending at [loc] touches, or
   [loc] if it touches none. A sentence spans from its [parsing_start], so the
   blank before it counts as part of it. *)
let extend_to_sentence_end document loc =
  match LM.find_first_opt (fun k -> loc <= k) document.sentences_by_end with
  | Some (stop, id) when (sentence_of_id document id).parsing_start < loc -> stop
  | _ -> loc

let get_pending_edits_range = function
  | None -> CErrors.anomaly Pp.(str "validate_document called without pending edits")
  | Some range -> range

(* Widens the pending edits range to the range to parse again. Parsing may go
   past its end, but never stops before it. Also returns the synterp state that
   parsing starts from and the id of the sentence it resumes after, if any.
   [document] already has the new text, but its sentences are still those of
   the last parse, so every offset here is an offset in the last parsed text. *)
let range_to_reparse document ({ start; stop; shift_after_stop } : pending_edits_range) =
  (* We take the state strictly before the [start] of the edit, to cover the case when the
     edit starts right where a sentence ends, for example Qed.<new_edit>. A period followed by
     text no longer ends the sentence (Qed.x), so that sentence has to be parsed again. *)
  let sentence_before_edit = LM.find_last_opt (fun k -> k < start) document.sentences_by_end in
  let parse_start, synterp_state, _ = state_after_sentence document sentence_before_edit in
  let top_id = Option.map snd sentence_before_edit in
  let parse_stop =
    if edits_grammar_change document start stop then max_int
    else extend_to_sentence_end document stop in
  { shift_after_stop; start = parse_start; stop = parse_stop }, synterp_state, top_id

let validate_document ({ pending_edits_range; raw_doc; cancel_handle; doc_id } as document) =
  let pending_edits_range = get_pending_edits_range pending_edits_range in
  (* Cancel any previous parsing event *)
  Option.iter Sel.Event.cancel cancel_handle;
  let parsing_request_range, synterp_state, top_id = range_to_reparse document pending_edits_range in
  let { start = parse_start; stop = parse_stop; _ } = parsing_request_range in
  log_validate.debug (fun () ->
    Format.sprintf "Parsing more from pos %i to pos %i" parse_start parse_stop);
  let stream = stream_from raw_doc parse_start in
  let started = Unix.gettimeofday () in
  let parse_state = {
    started;
    parsing_request_range;
    stopped_here = None;
    top_id;
    loc = None;
    synterp_state;
    stream;
    raw = raw_doc;
    parsed = [];
    errors = [];
    parsed_comments = [];
    previous_document = document;
  } in
  let event = create_parse_event ~doc_id parse_state in
  let cancel_handle = Some (Sel.Event.get_cancellation_handle event) in
  { document with cancel_handle }, [event]


(* Gets the sentences of [document] listed in [ids], a map from sentence ends
   to ids, sorted by end. *)
let sentences_of_ids document ids =
  List.map (fun (_, id) -> sentence_of_id document id) (LM.bindings ids)

(* Separates the old sentences that the new parse replaced from the ones it
   did not reach. Only the first ones are compared with the new sentences,
   and the others are kept as they were, moved by [shift_after_stop]. *)
let split_reparsed_sentences document ~parse_start ~shift_after_stop stopped_here =
  (* The old sentences we consider are those that end *after* where parsing started. *)
  let _, _, sentences_from_parse_start = LM.split parse_start document.sentences_by_end in
  match stopped_here with
  | None ->
    (* parsing reached the end of the text, so all old sentences were reparsed. *)
    sentences_of_ids document sentences_from_parse_start, []
  | Some stopped_here ->
    (* [stopped_here] is a location in the text *after* the edits, while the old
       sentences use locations in the text *before* the edits, so we subtract
       the shift. If an old sentence ends exactly there, the new parse read it
       again, so it goes with the replaced ones. *)
    let stop_before_edits = stopped_here - shift_after_stop in
    let reparsed, sentence_at_stop, kept = LM.split stop_before_edits sentences_from_parse_start in
    let reparsed = Option.cata (fun id -> LM.add stop_before_edits id reparsed) reparsed sentence_at_stop in
    sentences_of_ids document reparsed, sentences_of_ids document kept

(* Merges the comments that the new parse found with the old comments it did
   not read again. Old comments before [parse_start] keep their location, and
   those after [stopped_here] move by [shift_after_stop] to their location in
   the text *after* the edits. *)
let merge_comments document ~parse_start ~shift_after_stop stopped_here new_comments =
  let comments_before = LM.filter (fun end_ _ -> end_ <= parse_start) document.comments_by_end in
  let comments_after = match stopped_here with
    | None -> LM.empty
    | Some stopped_here ->
      let stop_before_edits = stopped_here - shift_after_stop in
      LM.filter (fun end_ _ -> end_ > stop_before_edits) document.comments_by_end in
  let comments_after = LM.shift ((+) shift_after_stop) (shift_comment shift_after_stop) comments_after in
  (* A comment before the edits never ends where one after them does. *)
  let kept_comments = LM.union (fun _ _ _ -> assert false) comments_before comments_after in
  (* A new comment overwrites an old one with the same end. *)
  List.fold_left (fun acc (comment : comment) -> LM.add comment.stop comment acc) kept_comments new_comments

let collect_parsing_errors document =
  LM.filter_map (fun _ id ->
      match (sentence_of_id document id).ast with
      | Parsed _ -> None
      | Error e -> Some e)
    document.sentences_by_end

(* Applies the result of a parse to [document]. [document] has the text *after*
   the edits, but its sentences and comments are still those of the last
   parse, at locations in the text *before* the edits. The new sentences and
   comments are at locations in the text *after* the edits. [previous_document]
   is the document as it was when parsing started. Its sentence locations and
   comments are the same as those of [document]. *)
let handle_invalidate {parsed; parsed_comments; parsing_request_range = { shift_after_stop; start }; top_id; previous_document; stopped_here = parsing_stopped_here } document =
  let reparsed_sentences, kept_sentences = split_reparsed_sentences document ~parse_start:start ~shift_after_stop parsing_stopped_here in
  let new_sentences = List.rev parsed in
  let unchanged_id, invalid_ids, document_with_new_sentences = invalidate (start + 1) top_id document reparsed_sentences new_sentences ~shift_after_stop ~kept_sentences in
  let new_comments = List.rev parsed_comments in
  let comments_by_end = merge_comments document ~parse_start:start ~shift_after_stop parsing_stopped_here new_comments in
  let parsing_errors_by_end = collect_parsing_errors document_with_new_sentences in
  let parsed_document = { document_with_new_sentences with parsing_errors_by_end; comments_by_end } in
  Some { parsed_document; unchanged_id; invalid_ids; previous_document }

let log_parsing_ended { parsed; errors; parsed_comments; started; parsing_request_range = { stop }; stopped_here } =
  log_validate.debug (fun () -> Format.sprintf "Parsing phase ended in %5.3f at %s (request was %d)"
    (Unix.gettimeofday () -. started) (Option.cata string_of_int "EOF" stopped_here) stop);
  log_validate.debug (fun () -> Format.sprintf "%i new sentences" (List.length parsed));
  log_validate.debug (fun () -> Format.sprintf "%i new errors" (List.length errors));
  log_validate.debug (fun () -> Format.sprintf "%i new comments" (List.length parsed_comments))

let handle_event document = function
| Parse (Sel.Promise.Rejected e) -> raise e
| Parse (Sel.Promise.Fulfilled Interrupted) -> assert false
| Parse (Sel.Promise.Fulfilled (Aborted e)) -> CErrors.user_err e
| Parse (Sel.Promise.Fulfilled (Terminated (true, parse_state))) ->
  let event = create_parse_event ~doc_id:document.doc_id parse_state in
  let cancel_handle = Some (Sel.Event.get_cancellation_handle event) in
  { document with cancel_handle }, [event], None
| Parse (Sel.Promise.Fulfilled (Terminated (false, parse_state))) ->
  log_parsing_ended parse_state;
  { document with cancel_handle = None }, [], handle_invalidate parse_state document

let create_document ~doc_id init_synterp_state text =
  let raw_doc = RawDocument.create text in
    {
      (* Nothing is parsed yet, so the whole text is pending. *)
      pending_edits_range = Some { start = 0; stop = String.length text; shift_after_stop = 0 };
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

(* Converts [x], an offset in the current text, to an offset in the last parsed
   text, which the pending edits range uses. An offset before the range stays
   as is, and one after it moves back by [shift]. An offset inside the range
   has no counterpart in the last parsed text, so the function returns
   [inside]. *)
let to_parsed_offset (shift, pending_start, pending_stop) inside x =
  if x < pending_start then x
  else if x >= pending_stop + shift then x - shift
  else inside

(* Merges [edit], whose offsets are in the current text, into the pending edits
   range [pending]. *)
let apply_1edit (shift, pending_start, pending_stop as pending) ({ RawDocument.start; stop } as edit) =
  let shift_after_stop = RawDocument.shift_after_stop edit in
  log_validate.debug (fun () -> Printf.sprintf "Text edits from %i to %i shift %d atop (%d,%d,%d)" start stop shift_after_stop shift pending_start pending_stop);
  let pending_start = min pending_start (to_parsed_offset pending pending_start start) in
  let pending_stop = max pending_stop (to_parsed_offset pending pending_stop stop) in
  let shift = shift + shift_after_stop in
  log_validate.debug (fun () -> Printf.sprintf "Text edits result in pending edits range %i - %i with shift %d" pending_start pending_stop shift);
  (shift, pending_start,pending_stop)

let apply_text_edit document edit =
  let raw_doc, edit = RawDocument.apply_text_edit document.raw_doc edit in
  let pending = match document.pending_edits_range with
    (* An empty range, so the bounds of the first edit win the min and max. *)
    | None -> (0, max_int, min_int)
    | Some { shift_after_stop; start; stop } -> (shift_after_stop, start, stop) in
  let shift_after_stop, start, stop = apply_1edit pending edit in
  { document with raw_doc; pending_edits_range = Some { shift_after_stop; start; stop} }, edit

let apply_text_edits document edits =
  List.fold_left (fun document edit -> fst (apply_text_edit document edit)) document edits

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
