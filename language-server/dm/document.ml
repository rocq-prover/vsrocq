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

let sentences_after_w_ids parsed loc =
  let (_before,ov,after) = LM.split loc parsed.sentences_by_end in
  let after = Option.cata (fun v -> LM.add loc v after) after ov in
  let ids, l_rev = LM.fold (fun _ id (acc,l) -> Stateid.Set.add id acc, sentence_of_id parsed id :: l) after (Stateid.Set.empty,[]) in
  List.rev l_rev, ids

let sentences_strictly_after parsed loc =
  let (_before,_ov,after) = LM.split loc parsed.sentences_by_end in
  List.filter_map (fun (_,id) -> let s = sentence_of_id parsed id in if s.parsing_start > loc then Some s else None) @@ LM.bindings after

let parsing_errors_before parsed loc =
  LM.filter (fun stop _v -> stop <= loc) parsed.parsing_errors_by_end

let parsing_errors_after parsed loc =
  let (_before,ov,after) = LM.split loc parsed.parsing_errors_by_end in
  Option.cata (fun v -> LM.add loc v after) after ov

let comments_before parsed loc =
  LM.filter (fun stop _v -> stop <= loc) parsed.comments_by_end

let comments parsed =
  List.map snd @@ LM.bindings parsed.comments_by_end

let comments_after parsed loc =
  let (_before,ov,after) = LM.split loc parsed.comments_by_end in
  Option.cata (fun v -> LM.add loc v after) after ov

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

type o = Reparsed of pre_sentence | NotReparsed of int * sentence

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
  log_diff.debug (fun () -> Format.sprintf "Patching sentence %s , %s" (Stateid.to_string id) (string_of_sentence o));
  let parsing_start, ast, ast_shift, start, stop, synterp_state =
    match x with
    | Reparsed { parsing_start; ast; start; stop; synterp_state } -> parsing_start, ast, 0, start, stop, synterp_state
    | NotReparsed (shift,s) ->
      let { parsing_start; ast; start; stop; synterp_state } = shift_sentence shift s in
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
    let tok_pair_equal (_, t1) (_, t2) = tok_equal t1 t2 in
    CList.equal tok_pair_equal ast1.tokens ast2.tokens
  | _, _ -> false

let same_tokens2 (s1 : sentence) (s2 : sentence) =
  match s1.ast, s2.ast with
  | Error e1, Error e2 -> same_errors e1 e2
  | Parsed ast1, Parsed ast2 ->
    let tok_pair_equal (_, t1) (_, t2) = tok_equal t1 t2 in
    CList.equal tok_pair_equal ast1.tokens ast2.tokens
  | _, _ -> false

let identical (n:pre_sentence) _shift (s:sentence) =
  (* shift + s.stop = n.stop &&
  shift + s.start = n.start &&
  shift + s.parsing_start = n.parsing_start && *)
  same_tokens s n

let overlaps (n:pre_sentence) shift (s:sentence) =
    n.stop > s.parsing_start + shift

let len_of (s : sentence) = s.stop - s.parsing_start

(* How many new sentences an insertion may add before an old sentence that is
   still matched. Bounded so that a reparse of the whole document stays linear. *)
let insertion_lookahead = 16

let rec matches_soon o k = function
  | [] -> false
  | n :: news -> k > 0 && (same_tokens o n || matches_soon o (k - 1) news)

let rec diff olds news shift after =
  match olds, news, after with
  | [], [], _ :: _ -> log_diff.debug (fun () ->"end: all after");
    mkEqual (List.map (fun s -> s.id, NotReparsed (shift, s)) after)
  | [], [n], a :: after when identical n shift a -> log_diff.debug (fun () ->"step: drop after, unshift");
    diff [] [] (shift(*-len_of a*)) (a :: after)
  | [], [n], a :: after when overlaps n shift a -> log_diff.debug (fun () ->"step: del after overlap");
    Deleted [a.id] :: diff [] [n] shift after
  (* | [], [n], after -> log_diff.debug (fun () ->"d1");
    Added [n] :: diff [] [] shift after *)
  | [], n :: (_ as news), after -> log_diff.debug (fun () ->"step: add new");
    Added [n] :: diff [] news shift after

  | [old], [], a :: after when same_tokens2 a old -> log_diff.debug (fun () ->"end: eq o a, eq after");
    mkEqual [old.id, NotReparsed(0,a)] @ mkEqual (List.map (fun s -> s.id,NotReparsed(shift,s)) after)
  | olds, [], after -> log_diff.debug (fun () -> "end: del olds, eq after");
    mkDeleted (List.map (fun s -> s.id) olds) @ mkEqual (List.map (fun s -> s.id,NotReparsed(shift,s)) after)
  | o::olds, n::news, after when same_tokens o n -> log_diff.debug (fun () ->"step: eq old new");
      Equal [(o.id,Reparsed n)] :: diff olds news shift after
  | (o :: _ as olds), n::news, after when matches_soon o insertion_lookahead news -> log_diff.debug (fun () ->"step: add new before old");
      Added [n] :: diff olds news shift after
  | o::olds, news, after -> log_diff.debug (fun () ->"step: del old");
      Deleted [o.id] :: diff olds news shift after

let diff o n s a =
  log_diff.debug (fun () -> Printf.sprintf "diff: old:\n  %s" (String.concat "\n  " @@ List.map string_of_sentence o));
  log_diff.debug (fun () -> Printf.sprintf "diff: new:\n  %s" (String.concat "\n  " @@ List.map string_of_presentence n));
  log_diff.debug (fun () -> Printf.sprintf "diff: after (shift %d):\n  %s" s (String.concat "\n  " @@ List.map string_of_sentence a));
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

let handle_parse_error id ~start ~parsing_start msg qf ({stream; errors; parsed;} as parse_state) synterp_state =
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

let handle_parsed_sentence ~parsing_start ast comments
    ({ synterp_state; stream; raw; parsed; parsed_comments; parsing_request_range } as parse_state) =
  let id = Stateid.fresh () in
  let stop = Stream.count stream in
  let ast_loc = match ast.CAst.loc with
    | Some lc -> lc
    | None -> assert false
  in
  let start = ast_loc.bp in
  let tokens = get_raw_text_tokens raw start ast_loc.ep ast_loc in
  try
    log_parsing.debug (fun () -> "Parsed: " ^ Pp.string_of_ppcmds (Ppvernac.pr_vernac ast));
    Feedback.set_id_for_feedback parse_state.previous_document.doc_id id;
    let entry = get_entry ast in
    let classification = Vernac_classifier.classify_vernac ast in
    let synterp_state = Vernacstate.Synterp.freeze () in
    let parsed_ast = Parsed { ast = entry; classification; tokens } in
    let sentence = { id; parsing_start; ast = parsed_ast; start; stop; synterp_state } in
    let parsed = sentence :: parsed in
    let comments = List.map (fun ((start, stop), content) -> { start; stop; content }) comments in
    let parsed_comments = List.append comments parsed_comments in
    let loc = ast.loc in
    let parsing_request_range =
      if changes_grammar entry classification then { parsing_request_range with stop = max_int }
      else parsing_request_range in
    let parse_state =
      { parse_state with parsing_request_range; parsed_comments; parsed; loc; synterp_state } in
    true, parse_state
  with exn ->
    let e, info = Exninfo.capture exn in
    let loc = get_loc_from_info_or_exn e info in
    let qf = Result.value ~default:[] @@ Quickfix.from_exception e in
    handle_parse_error id ~start ~parsing_start (loc, CErrors.iprint_no_report (e, info)) (Some qf)
      parse_state synterp_state

let parse_more ({loc; synterp_state; stream; parsing_request_range} as parse_state) : bool * parse_state =
  let next_start = Stream.count stream in
  (* Skip parsing a sentence that's beyond the edit's impact range. The range
     is in the offsets of the last parsed text, the stream in the current one. *)
  let { stop = parse_stop; shift_after_stop } = parsing_request_range in
  if parse_stop <> max_int && next_start >= parse_stop + shift_after_stop then begin
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
      handle_parsed_sentence ~parsing_start:next_start ast comments parse_state
    | exception exn ->
      let id = Stateid.fresh () in
      let e, info = Exninfo.capture exn in
      let loc = get_loc_from_info_or_exn e info in
      let qf = Result.value ~default:[] @@ Quickfix.from_exception e in
      junk_sentence_end stream;
      handle_parse_error id ~start:next_start ~parsing_start:next_start (loc, CErrors.iprint_no_report (e,info)) (Some qf) parse_state synterp_state
  end

let create_parse_event ~doc_id parse_state =
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

let string_of_doc doc =
  let sentences = LM.bindings @@ LM.map (fun id -> Stateid.to_string id ^ ": " ^ string_of_sentence (sentence_of_id doc id)) doc.sentences_by_end in
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
      let add_sentence (parsed_doc,scheduler_state) ({ id; parsing_start; start; stop; ast; synterp_state } : pre_sentence) =
        add_sentence parsed_doc id parsing_start start stop ast synterp_state scheduler_state
      in
      let parsed_doc, scheduler_state = List.fold_left add_sentence (parsed_doc,scheduler_state) news in
      add_new_or_patch parsed_doc scheduler_state diffs
  in
  (* [after_deletion] tells whether the additions being walked follow a
     deletion, whose dependents include the sentence kept after them. *)
  let rec remove_old ~after_deletion parsed_doc invalid_ids = function
    | [] -> parsed_doc, invalid_ids
    | Deleted ids :: diffs ->
      let invalid_ids = List.fold_left (fun ids id -> Stateid.Set.add id ids) invalid_ids ids in
      let parsed_doc = List.fold_left remove_sentence parsed_doc ids in
      (* FIXME update scheduler state, maybe invalidate after diff zone *)
      remove_old ~after_deletion:true parsed_doc invalid_ids diffs
    | Added _ :: (Equal ((id, _) :: _) :: _ as diffs) when not after_deletion ->
      (* The first sentence kept after an insertion runs from another state;
         invalidating it also invalidates its dependents. *)
      remove_old ~after_deletion:false parsed_doc (Stateid.Set.add id invalid_ids) diffs
    | Added _ :: diffs -> remove_old ~after_deletion parsed_doc invalid_ids diffs
    | Equal _ :: diffs -> remove_old ~after_deletion:false parsed_doc invalid_ids diffs in
  let (_,_synterp_state,scheduler_state) = state_at_pos parsed_doc top_edit in
  log_diff.debug (fun () -> Format.sprintf "Top edit: %i, New sentences: %d" top_edit (List.length news));
  (* let olds = sentences_after parsed_doc top_edit in *)
  let t0 = Unix.gettimeofday () in
  let diff = diff olds news shift after in
  let t1 = Unix.gettimeofday () in
  log_diff.debug (fun () -> "diff:\n" ^ string_of_diff parsed_doc diff);
  let parsed_doc, invalid_ids = remove_old ~after_deletion:false parsed_doc Stateid.Set.empty diff in
  let t2 = Unix.gettimeofday () in
  let parsed_doc = add_new_or_patch parsed_doc scheduler_state diff in
  let t3 = Unix.gettimeofday () in
  log_diff.info (fun () -> Format.sprintf "Time diff:%5.3f rem:%5.3f add/patch:%5.3f\n" (t1 -. t0) (t2 -. t1) (t3 -. t2));
  let unchanged_id = unchanged_id top_id diff in
  log_diff.debug (fun () -> Format.sprintf "Updated document:\n%s" (string_of_doc parsed_doc));
  log_diff.debug (fun () -> "unchanged id: " ^ Option.cata Stateid.to_string "none" unchanged_id);
  unchanged_id, invalid_ids, { parsed_doc with pending_edits_range = None; }

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


  (* TODO : clarify what is previous doc vs doc *)
let handle_invalidate {parsed; errors; parsed_comments; parsing_request_range = { shift_after_stop; start; stop }; top_id; started; previous_document} parsing_stopped_here document =
  let end_ = Unix.gettimeofday ()in
  let time = end_ -. started in
  log_validate.info (fun () -> Format.sprintf "Parsing phase ended in %5.3f at %s (request was %d)\n%!"
    time (Option.cata string_of_int "EOF" parsing_stopped_here) stop);
  let new_sentences = List.rev parsed in
  let new_comments = List.rev parsed_comments in
  let new_errors = errors in
  log_validate.debug (fun () -> Format.sprintf "%i new sentences" (List.length new_sentences));
  log_validate.debug (fun () -> Format.sprintf "%i new errors" (List.length new_errors));
  log_validate.debug (fun () -> Format.sprintf "%i new comments" (List.length new_comments));
  let top_edit = start+1 in
  let end1_ = Unix.gettimeofday ()in

  let olds, after =
    let old_sentences, _ = sentences_after_w_ids document top_edit in
    if stop = max_int then
      old_sentences, [] (* FIXME: this means we parsed a grammar changing command and we reparsed everything ... make this clear in the type *)
    else
      let after, after_set =
        match parsing_stopped_here with
        | None -> [], Stateid.Set.empty
        (* [document] is still in the offsets of the last parsed text, and the
           old sentence ending where parsing stopped has been parsed again *)
        | Some parsing_stopped_here -> sentences_after_w_ids document (parsing_stopped_here - shift_after_stop + 1) in
      (* TODO slow *)
      List.filter (fun x -> not(Stateid.Set.mem x.id after_set)) old_sentences, after in
  log_validate.debug (fun () -> Format.sprintf "old stuff after shifted by %d" shift_after_stop);
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
  log_validate.debug (fun () ->
    let sentence_string = String.concat " " @@ List.map (fun s -> string_of_sentence s) after in
    Format.sprintf "%i after %d: %s" (List.length after) stop sentence_string);
  let unchanged_id, invalid_ids, document = invalidate top_edit top_id document olds new_sentences (shift_after_stop,after) in
  let parsing_errors_by_end = LM.filter_map (fun _ id -> match (sentence_of_id document id).ast with Parsed _ -> None | Error e -> Some e) document.sentences_by_end in
  let parsed_document = {document with parsing_errors_by_end; comments_by_end} in
  let end2_ = Unix.gettimeofday ()in
  log_validate.info (fun () -> Printf.sprintf "valid: %5.3f" (end2_ -. end1_));
  Some {parsed_document; unchanged_id; invalid_ids; previous_document}

let handle_event document = function
| Parse (Sel.Promise.Rejected e) -> raise e
| Parse (Sel.Promise.Fulfilled Interrupted) -> assert false
| Parse (Sel.Promise.Fulfilled (Aborted e)) -> CErrors.user_err e
| Parse (Sel.Promise.Fulfilled (Terminated (true, parse_state))) ->
  let event = create_parse_event ~doc_id:document.doc_id parse_state in
  let cancel_handle = Some (Sel.Event.get_cancellation_handle event) in
  {document with cancel_handle}, [event], None
| Parse (Sel.Promise.Fulfilled (Terminated (false,parse_state))) ->
  {document with cancel_handle = None}, [], handle_invalidate parse_state parse_state.stopped_here document

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
