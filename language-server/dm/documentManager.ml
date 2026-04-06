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

[%%import "vsrocq_config.mlh"]

open Lsp.Types
open Protocol
open Protocol.LspWrapper
open Protocol.Printing
open Types

let Log log = Log.mk_log "documentManager"

type blocking_error = {
  last_range: Range.t;
  error_range: Range.t
}

type document_state =
| Parsing
| Parsed
(* | Executing of sentence_id TODO: ADD EXEDCUTING STATE
| Executed of sentence_id *)

type state = {
  uri : DocumentUri.t;
  init_vs : Vernacstate.t;
  opts : Coqargs.injection_command list;
  document : Document.document;
  document_state: document_state;
  feedback_pipe : feedback_pipe;
  checking_state : CheckingManager.state;
}
type event =
  | ParseBegin
  | DocumentEvent of Document.event
  | InteractionManagerEvent of CheckingManager.event
  | LocalFeedback of feedback_data list

let pp_event fmt = function
  | ParseBegin -> Stdlib.Format.fprintf fmt "ParseBegin"
  | DocumentEvent event -> Stdlib.Format.fprintf fmt "DocumentEvent event: "; Document.pp_event fmt event
  | InteractionManagerEvent event -> Stdlib.Format.fprintf fmt "InteractionManagerEvent event: "; CheckingManager.pp_event fmt event
  | LocalFeedback _ -> Stdlib.Format.fprintf fmt "LocalFeedback"

let inject_im_event x = Sel.Event.map (fun e -> InteractionManagerEvent e) x
let inject_im_events events = List.map inject_im_event events

let inject_doc_event x = Sel.Event.map (fun e -> DocumentEvent e) x
let inject_doc_events events = List.map inject_doc_event events

  
type events = event Sel.Event.t list

let is_parsing st =  st.document_state = Parsing

[%%if lsp < (1,19,0) ]
let message_of_string x = x
[%%else]
let message_of_string x = `String x
[%%endif]

let make_diagnostic doc range oloc message severity code =
  let range =
    match oloc with
    | None -> range
    | Some loc ->
      RawDocument.range_of_loc (Document.raw_document doc) loc
  in
  let code, data =
    match code with
    | None -> None, None
    | Some (x,z) -> Some x, Some z in
  Diagnostic.create ?code ?data ~range ~message:(message_of_string message) ~severity ()

let mk_diag st (id,(lvl,oloc,qf,msg)) =
  let code = 
    match qf with
    | [] -> None
    | qf ->
      let code : Jsonrpc.Id.t * Lsp.Import.Json.t =
        let open Lsp.Import.Json in
        (`String "quickfix-replace",
        qf |> yojson_of_list
        (fun qf ->
            let s = Pp.string_of_ppcmds @@ Quickfix.pp qf in
            let loc = Quickfix.loc qf in
            let range = RawDocument.range_of_loc (Document.raw_document st.document) loc in
            QuickFixData.yojson_of_t (QuickFixData.{range; text = s})
        ))
        in
      Some code
    in
    let lvl = DiagnosticSeverity.of_feedback_level lvl in
    make_diagnostic st.document (Document.range_of_id st.document id) oloc (Pp.string_of_ppcmds msg) lvl code

let mk_error_diag st (id,(oloc,msg,qf)) = (* mk_diag st (id,(Feedback.Error,oloc, msg)) *)
  let code = 
    match qf with
    | None -> None
    | Some qf ->
      let code : Jsonrpc.Id.t * Lsp.Import.Json.t =
        let open Lsp.Import.Json in
        (`String "quickfix-replace",
        qf |> yojson_of_list
        (fun qf ->
            let s = Pp.string_of_ppcmds @@ Quickfix.pp qf in
            let loc = Quickfix.loc qf in
            let range = RawDocument.range_of_loc (Document.raw_document st.document) loc in
            QuickFixData.yojson_of_t (QuickFixData.{range; text = s})
        ))
        in
      Some code
  in
  let lvl = DiagnosticSeverity.of_feedback_level Feedback.Error in
  make_diagnostic st.document (Document.range_of_id st.document id) oloc (Pp.string_of_ppcmds msg) lvl code


let mk_parsing_error_diag st Document.{ msg = (oloc,msg); start; stop; qf } =
  let doc = Document.raw_document st.document in
  let severity = DiagnosticSeverity.Error in
  let start = RawDocument.position_of_loc doc start in
  let end_ = RawDocument.position_of_loc doc stop in
  let range = Range.{ start; end_ } in
  let code = 
    match qf with
    | None -> None
    | Some qf ->
      let code : Jsonrpc.Id.t * Lsp.Import.Json.t =
        let open Lsp.Import.Json in
        (`String "quickfix-replace",
         qf |> yojson_of_list
         (fun qf ->
            let s = Pp.string_of_ppcmds @@ Quickfix.pp qf in
            let loc = Quickfix.loc qf in
            let range = RawDocument.range_of_loc (Document.raw_document st.document) loc in
            QuickFixData.yojson_of_t (QuickFixData.{range; text = s})
        ))
        in
      Some code
  in
  make_diagnostic st.document range oloc (Pp.string_of_ppcmds msg) severity code

let all_diagnostics st =
  let parse_errors = Document.parse_errors st.document in
  let all_exec_errors = Document.all_checking_errors st.document in
  let all_feedback = Document.all_feedback st.document in
  (* we are resilient to a state where invalidate was not called yet *)
  let exists (id,_) = Option.has_some (Document.get_sentence st.document id) in
  let not_info (_, (lvl, _, _, _)) = 
    match lvl with
    | Feedback.Info -> false
    | _ -> true
  in
  let exec_errors = all_exec_errors |> List.filter exists in
  let feedback = all_feedback |> List.filter not_info in
  List.map (mk_parsing_error_diag st) parse_errors @
    List.map (mk_error_diag st) exec_errors @
    List.map (mk_diag st) feedback


let get_info_messages st pos =
  match Option.append
    (Option.bind pos (Document.find_sentence_before_pos st.document) |> Option.map (fun ({ id } : Document.sentence) -> id))
    (CheckingManager.get_observe_id st.checking_state)
  with
  | None -> log (fun () -> "get_messages: Could not find id");[]
  | Some id -> log (fun () -> "get_messages: Found id");
    let info (lvl, _, _, _) = 
      match lvl with
      | Feedback.Info -> true
      | _ -> false
    in
    let feedback = Document.feedback st.document id in
    let feedback = feedback |> List.filter info in
    List.map (fun (lvl,_oloc,_,msg) -> DiagnosticSeverity.of_feedback_level lvl, pp_of_rocqpp msg) feedback


let get_document_proofs st =
  let outline = Document.outline st.document in
  let is_theorem Document.{ type_ } =
    match type_ with
    | TheoremKind -> true
    | _ -> false
    in
  let mk_proof_block Document.{statement; proof; range } =
    let statement = ProofState.mk_proof_statement statement range in
    match proof with
    | [] ->
      let steps = [] in
      ProofState.mk_proof_block statement steps range
    | _ ->
      let last_step = List.hd proof in
      let proof = List.rev proof in
      let fst_step = List.hd proof in
      let range = Range.create ~start:fst_step.range.start ~end_:last_step.range.end_ in
      let steps = List.map (fun Document.{tactic; range} -> ProofState.mk_proof_step tactic range) proof in
      ProofState.mk_proof_block statement steps range
  in
  let proofs, _  = List.partition is_theorem outline in
  List.map mk_proof_block proofs

let to_document_symbol elem =
  let Document.{name; statement; range; type_} = elem in
  let kind = begin match type_ with
  | TheoremKind -> SymbolKind.Function
  | DefinitionType -> SymbolKind.Variable
  | InductiveType -> SymbolKind.Struct
  | Other -> SymbolKind.Null
  | BeginSection | BeginModule -> SymbolKind.Class
  | End -> SymbolKind.Null
  end in
  DocumentSymbol.{name; detail=(Some statement); kind; range; selectionRange=range; children=None; deprecated=None; tags=None;}

let rec get_document_symbols outline (sec_or_m: DocumentSymbol.t list) symbols =
  let add_child (s_father: DocumentSymbol.t) s_child =
    let children = match s_father.children with
      | None -> Some [s_child]
      | Some l -> Some (l @ [s_child])
    in
    {s_father with children} 
  in
  let record_in_outline outline symbol sec_or_m =
    match sec_or_m with
    | [] ->
      let symbols = symbols @ [symbol] in
      get_document_symbols outline sec_or_m symbols
    | s :: l ->
      let s = add_child s symbol in
      get_document_symbols outline (s::l) symbols
  in
  match outline with
  | [] -> symbols
  | e :: l ->
    let Document.{type_} = e in
    match type_ with
    | TheoremKind | DefinitionType | InductiveType  | Other ->
      let symbol = to_document_symbol e in
      record_in_outline l symbol sec_or_m
    | BeginSection ->
      let symbol = to_document_symbol e in
      get_document_symbols l (symbol :: sec_or_m) symbols
    | BeginModule ->
      let symbol = to_document_symbol e in
      get_document_symbols l (symbol :: sec_or_m) symbols
    | End ->
      match sec_or_m with
      | [] -> log(fun () -> "Trying to end a module or section with no begin"); get_document_symbols l [] symbols
      | symbol :: s_l ->
        match s_l with
        | [] ->
          get_document_symbols l s_l (symbols @ [symbol])
        | s_parent :: s_l ->
          let s = add_child s_parent symbol in
          get_document_symbols l (s :: s_l) symbols
          

let get_document_symbols st =
  let outline = List.rev @@ Document.outline st.document in
  get_document_symbols outline [] []

let get_next_range st pos =
  match Document.find_sentence_before_pos st.document pos with
  | None -> None
  | Some { stop; id } ->
      match Document.find_sentence_after st.document (stop+1) with
      | None -> Some (Document.range_of_id st.document id)
      | Some { id } -> Some (Document.range_of_id st.document id)

let get_previous_range st pos =
  match Document.find_sentence_before_pos st.document pos with
  | None -> None
  | Some { start; id } ->
      match Document.find_sentence_before st.document (start) with
      | None -> Some (Document.range_of_id st.document id)
      | Some { id } -> Some (Document.range_of_id st.document id)

let validate_document state (Document.{unchanged_id; invalid_ids; previous_document; parsed_document}) =
  let state = {state with document=parsed_document} in
  (* this should be made in Document *)
  let old_schedule = Document.schedule previous_document in
  let rec invalidate_checked id state =
    let checking_state = CheckingManager.invalidate state.checking_state id in
    let document = Document.set_unchecked state.document id in
    let state = { state with document; checking_state } in
    let deps = Scheduler.dependents old_schedule id in
    Stateid.Set.fold invalidate_checked deps state in
  let state = Stateid.Set.fold invalidate_checked invalid_ids state in
  let checking_state = CheckingManager.reset_overview state.checking_state previous_document unchanged_id in
  { state with checking_state; document_state = Parsed }

[%%if rocq ="8.18" || rocq ="8.19"]
let start_library top opts = Coqinit.start_library ~top opts
[%%else]
let start_library top opts =
  let intern = Vernacinterp.fs_intern in
  Coqinit.start_library ~intern ~top opts;
[%%endif]

[%%if rocq ="8.18" || rocq ="8.19" || rocq ="8.20"]
let dirpath_of_top = Coqargs.dirpath_of_top
[%%else]
let dirpath_of_top = Coqinit.dirpath_of_top
[%%endif]

let local_feedback feedback_queue : event Sel.Event.t =
  Sel.On.queue_all ~name:"feedback" ~priority:PriorityManager.feedback feedback_queue
    (fun x xs -> LocalFeedback(x :: xs))

let install_feedback_listener doc_id send =
  Log.feedback_add_feeder_on_Message (fun route span doc lvl loc qf msg ->
    if lvl != Feedback.Debug && doc = doc_id then send (route,span,(lvl,loc, qf, msg)))

let init_feedback_pipe () =
  let doc_id = Utilities.fresh_doc_id () in
  let sel_feedback_queue = Queue.create () in
  let rocq_feeder = install_feedback_listener doc_id (fun x -> Queue.push x sel_feedback_queue) in
  let feedback = local_feedback sel_feedback_queue in
  let sel_cancellation_handle = Sel.Event.get_cancellation_handle feedback in
  let feedback_pipe = {doc_id;sel_feedback_queue;rocq_feeder;sel_cancellation_handle;} in
  feedback_pipe, feedback

let init init_vs ~opts uri ~text =
  Vernacstate.unfreeze_full_state init_vs;
  let top = try (dirpath_of_top (TopPhysical (DocumentUri.to_path uri))) with
    e -> raise e
  in
  start_library top opts;
  let init_vs = Vernacstate.freeze_full_state () in
  let document = Document.create_document init_vs.Vernacstate.synterp text in
  let feedback_pipe, feedback_event = init_feedback_pipe () in
  let checking_state = CheckingManager.init init_vs ~feedback_pipe in
  let parsebegin_event = Sel.now ~priority:PriorityManager.launch_parsing ParseBegin in
  let state = { uri; opts; init_vs; document; document_state = Parsing; feedback_pipe; checking_state } in
  state, [parsebegin_event;feedback_event]

let reset { uri; opts; init_vs; document; checking_state; feedback_pipe } =
  Utilities.feedback_pipe_cleanup feedback_pipe;
  let text = RawDocument.text @@ Document.raw_document document in
  Vernacstate.unfreeze_full_state init_vs; (* Why? *)
  let document = Document.create_document init_vs.synterp text in
  let feedback_pipe, feedback_event = init_feedback_pipe () in
  let checking_state = CheckingManager.reset checking_state init_vs ~feedback_pipe in
  let state = { uri; opts; init_vs; document; checking_state; document_state = Parsing; feedback_pipe } in
  let parsebegin_event = Sel.now ~priority:PriorityManager.launch_parsing ParseBegin in
  state, [parsebegin_event;feedback_event]

let apply_text_edits state edits =
  let apply_edit_and_shift_diagnostics_locs_and_overview state (range, new_text as edit) =
    let document = Document.apply_text_edit state.document edit in
    let edit_start = RawDocument.loc_of_position (Document.raw_document state.document) range.Range.start in
    let edit_stop = RawDocument.loc_of_position (Document.raw_document state.document) range.Range.end_ in
    let edit_length = edit_stop - edit_start in
    let start = edit_stop in
    let offset = String.length new_text - edit_length in
    let document = Document.shift_feedbacks_and_checking_errors ~start ~offset document in
    let checking_state = CheckingManager.shift_overview state.checking_state ~before:state.document ~after:document ~start:edit_stop ~offset:(String.length new_text - edit_length) in
    {state with checking_state; document}
  in
  let state = List.fold_left apply_edit_and_shift_diagnostics_locs_and_overview state edits in
  let priority = Some PriorityManager.launch_parsing in
  let sel_event = Sel.now ?priority ParseBegin in
  state, [sel_event]

let handle_feedback_event state (_, id, msg) =
  { state with document = Document.append_feedback state.document id msg }

let handle_event ev st =
  match ev with
  | LocalFeedback l ->
     let state = List.fold_left handle_feedback_event st l in
     make_handled_event ~state ~update_view:true ~events:[local_feedback state.feedback_pipe.sel_feedback_queue] ()
  | ParseBegin ->
    let document, events = Document.validate_document st.document in
    let state = {st with document} in
    let events = inject_doc_events events in
    make_handled_event ~state ~update_view:true ~events ()
  | DocumentEvent ev ->
    let document, events, parsing_end_info = Document.handle_event st.document ev in
    begin match parsing_end_info with
    | None ->
      let state = {st with document} in
      let events = inject_doc_events events in
      make_handled_event ~state ~update_view:false ~events ()
    | Some parsing_end_info ->
      let st = validate_document st parsing_end_info in
      let checking_state, events = CheckingManager.validate_document st.document st.checking_state in
      make_handled_event ~state:{st with checking_state} ~events:(inject_im_events events) ~update_view:true ()
    end
  | InteractionManagerEvent ev ->
    let updates, he = CheckingManager.handle_event ~uri:st.uri st.document st.checking_state ev in
    let st = { st with document = List.fold_left Document.update_checked st.document updates } in
    lift_handled_event (function None -> Some st | Some checking_state -> Some { st with checking_state })
      inject_im_events he


let context_of_sentence st (s : Document.sentence option) =
  match s with
  | None ->
      Utilities.context_of_vernac_state st.init_vs
  | Some { checked } ->
      match Utilities.get_proof_context checked with
      | Some x -> x
      | None -> 
         Utilities.context_of_vernac_state st.init_vs

(** Get context at the start of the sentence containing [pos] *)
let get_context st pos =
    context_of_sentence st (Document.find_sentence_before_pos st.document pos)

let get_completions st pos =
  match Document.find_sentence_before_pos st.document pos with
  | None -> 
      log (fun () -> "Can't get completions, no sentence found before the cursor");
      []
  | Some { checked } ->
    let ost = Utilities.get_vernac_state checked in
    let settings = ExecutionManager.get_options () in
    match Option.bind ost @@ CompletionSuggester.get_completions settings.completion_options with
    | None -> 
        log (fun () -> "No completions available");
        []
    | Some lemmas -> lemmas

[%%if rocq ="8.18" || rocq ="8.19"]
[%%elif rocq ="8.20"]
  let parsable_make = Pcoq.Parsable.make
  let unfreeze = Pcoq.unfreeze
  let entry_parse = Pcoq.Entry.parse
[%%else]
  let parsable_make = Procq.Parsable.make
  let unfreeze = Procq.unfreeze
  let entry_parse = Procq.Entry.parse
[%%endif]

[%%if rocq ="8.18" || rocq ="8.19"]
let parse_entry st pos entry pattern =
  let pa = Pcoq.Parsable.make (Gramlib.Stream.of_string pattern) in
  let st = match Document.find_sentence_before st.document pos with
  | None -> st.init_vs.Vernacstate.synterp.parsing
  | Some { synterp_state } -> synterp_state.Vernacstate.Synterp.parsing
  in
  Vernacstate.Parser.parse st entry pa
[%%else]
let parse_entry st pos entry pattern =
  let pa = parsable_make (Gramlib.Stream.of_string pattern) in
  let st = match Document.find_sentence_before st.document pos with
  | None -> Vernacstate.(Synterp.parsing st.init_vs.synterp)
  | Some { synterp_state } -> Vernacstate.Synterp.parsing synterp_state
  in  
  unfreeze st;
  entry_parse entry pa
[%%endif]

[%%if rocq ="8.18" || rocq ="8.19" || rocq ="8.20"]
  let smart_global = Pcoq.Prim.smart_global
[%%else]
  let smart_global = Procq.Prim.smart_global
[%%endif]

let about st pos ~pattern =
  let loc = RawDocument.loc_of_position (Document.raw_document st.document) pos in
  let sigma, env = get_context st pos in
    try
      let ref_or_by_not = parse_entry st loc (smart_global) pattern in
      let udecl = None (* TODO? *) in
      Ok (pp_of_rocqpp @@ Prettyp.print_about env sigma ref_or_by_not udecl)
    with e ->
      let e, info = Exninfo.capture e in
      let message = Pp.string_of_ppcmds @@ CErrors.iprint (e, info) in
      Error ({message; code=None})

let search st ~id pos pattern =
  let loc = RawDocument.loc_of_position (Document.raw_document st.document) pos in
  let sigma, env = get_context st pos in
    let query, r = parse_entry st loc (G_vernac.search_queries) pattern in
    SearchQuery.interp_search ~id env sigma query r

(** Try to generate hover text from [pattern] the context of the given [sentence] *)
let hover_of_sentence st loc pattern sentence = 
  let sigma, env = context_of_sentence st sentence in
    try
      let ref_or_by_not = parse_entry st loc (smart_global) pattern in
      Language.Hover.get_hover_contents env sigma ref_or_by_not
    with e ->
      let e, info = Exninfo.capture e in
      log (fun () -> "Exception while handling hover: " ^ (Pp.string_of_ppcmds @@ CErrors.iprint (e, info)));
      None

let hover st pos =
  (* Tries to get hover at three difference places:
     - At the start of the current sentence
     - At the start of the next sentence (for symbols defined in the current sentence)
       e.g. Definition, Inductive
     - At the next QED (for symbols defined after proof), if the next sentence 
       is in proof mode e.g. Lemmas, Definition with tactics *)
  let opattern = RawDocument.word_at_position (Document.raw_document st.document) pos in
  match opattern with
  | None -> log (fun () -> "hover: no word found at cursor"); None
  | Some pattern ->
    log (fun () -> "hover: found word at cursor: \"" ^ pattern ^ "\"");
    let loc = RawDocument.loc_of_position (Document.raw_document st.document) pos in
    (* hover at previous sentence *)
    match hover_of_sentence st loc pattern (Document.find_sentence_before st.document loc) with
    | Some _ as x -> x
    | None -> 
    match Document.find_sentence_after st.document loc with
    | None -> None (* Skip if no next sentence *)
    | Some sentence as opt ->
    (* hover at next sentence *)
    match hover_of_sentence st loc pattern opt with
    | Some _ as x -> x
    | None -> 
    match sentence.ast with
    | Error _ -> None
    | Parsed ast -> 
      match ast.classification with
    (* next sentence in proof mode, hover at qed *)
      | VtProofStep _ | VtStartProof _ -> 
        hover_of_sentence st loc pattern (Document.find_next_qed st.document loc)
      | _ -> None

[%%if rocq ="8.18" || rocq ="8.19" || rocq ="8.20"]
  let lconstr = Pcoq.Constr.lconstr
[%%else]
  let lconstr = Procq.Constr.lconstr
[%%endif]


[%%if rocq ="8.18" || rocq ="8.19" || rocq ="8.20"]
let jump_to_definition _  _ = None
[%%else]
let jump_to_definition st pos =
  let raw_doc = Document.raw_document st.document in
  let loc = RawDocument.loc_of_position raw_doc pos in
  let opattern = RawDocument.word_at_position raw_doc pos in
  match opattern with
  | None -> log (fun () -> "jumpToDef: no word found at cursor"); None
  | Some pattern ->
    log (fun () -> "jumpToDef: found word at cursor: \"" ^ pattern ^ "\"");
    try
    let qid = parse_entry st loc (Procq.Prim.qualid) pattern in
      let ref = Nametab.locate_extended qid in
        match Nametab.cci_src_loc ref with
          | None -> None
          | Some loc ->
            begin match loc.Loc.fname with
              | Loc.ToplevelInput | InFile  { dirpath = None } -> None
              | InFile { dirpath = Some dp } ->
                  let f = Loadpath.locate_absolute_library @@ Libnames.dirpath_of_string dp in
                  begin match f with
                    | Ok f ->
                      let f =  Filename.remove_extension f ^ ".v" in
                      (if Sys.file_exists f then
                        let b_pos = Position.create ~character:(loc.bp - loc.bol_pos) ~line:(loc.line_nb - 1) in
                        let e_pos = Position.create ~character:(loc.ep - loc.bol_pos) ~line:(loc.line_nb - 1) in
                        let range = Range.create ~end_:b_pos ~start:e_pos in
                        Some (range, f)
                      else
                        None
                      )
                    | Error _ -> None
                  end
            end
        with e ->
          let e, info = Exninfo.capture e in
          log (fun () -> Pp.string_of_ppcmds @@ CErrors.iprint (e, info)); None

[%%endif]

let check st pos ~pattern =
  let loc = RawDocument.loc_of_position (Document.raw_document st.document) pos in
  let sigma, env = get_context st pos in
    let rc = parse_entry st loc lconstr pattern in
    try
      let redexpr = None in
      Ok (pp_of_rocqpp @@ Vernacentries.check_may_eval env sigma redexpr rc)
    with e ->
      let e, info = Exninfo.capture e in
      let message = Pp.string_of_ppcmds @@ CErrors.iprint (e, info) in
      Error ({message; code=None})

[%%if rocq ="8.18" || rocq ="8.19"]
let print_located_qualid _ qid = Prettyp.print_located_qualid qid
[%%else]
let print_located_qualid = Prettyp.print_located_qualid
[%%endif]

[%%if rocq ="8.18" || rocq ="8.19" || rocq = "8.20" || rocq = "9.0" || rocq = "9.1"]
let pr_glob_without_symbols env sigma c =
  Constrextern.without_symbols (Printer.pr_glob_constr_env env sigma) c
[%%else]
let pr_glob_without_symbols env sigma c =
  let flags = PrintingFlags.Extern.current() in
  let flags = { flags with notations = false } in
  Printer.pr_glob_constr_env ~flags env sigma c
[%%endif]

let locate st pos ~pattern = 
  let loc = RawDocument.loc_of_position (Document.raw_document st.document) pos in
  let sigma, env = get_context st pos in
    match parse_entry st loc (smart_global) pattern with
    | { v = AN qid } -> Ok (pp_of_rocqpp @@ print_located_qualid env qid)
    | { v = ByNotation (ntn, sc)} ->
      Ok( pp_of_rocqpp @@ Notation.locate_notation
        (pr_glob_without_symbols env sigma) ntn sc)

[%%if rocq ="8.18" || rocq ="8.19"]
  let print_name = Prettyp.print_name
[%%else]
  let print_name =
    let access = Library.indirect_accessor[@@warning "-3"] in
    Prettyp.print_name access
[%%endif]

let print st pos ~pattern = 
  let loc = RawDocument.loc_of_position (Document.raw_document st.document) pos in
  let sigma, env = get_context st pos in
    try
      let qid = parse_entry st loc (smart_global) pattern in
      let udecl = None in (*TODO*)
      Ok ( pp_of_rocqpp @@ print_name env sigma qid udecl )
    with e ->
      let e, info = Exninfo.capture e in
      let message = Pp.string_of_ppcmds @@ CErrors.iprint (e, info) in
      Error ({message; code=None})

(* Ignore nested proofs option (lives in STM) instead of failing with
   anomaly when it is set in a .vo we Require.
   cf #1060 *)

let warn_nested_proofs_opt =
  CWarnings.create ~name:"vsrocq-nested-proofs-flag"
    Pp.(fun () -> str "Flag \"Nested Proofs Allowed\" is ignored by VsRocq.")

let () =
  Goptions.declare_bool_option
    { optstage = Summary.Stage.Interp;
      optdepr  = None;
      optkey   = Vernac_classifier.stm_allow_nested_proofs_option_name;
      optread  = (fun () -> false);
      optwrite = (fun b -> if b then warn_nested_proofs_opt ()) }


let interpret_to_position pos =
  CheckingManager.interpret_to_position pos |> inject_im_events

let interpret_to_previous () = CheckingManager.interpret_to_previous () |> inject_im_events
let interpret_to_next () = CheckingManager.interpret_to_next () |> inject_im_events
let interpret_to_end () = CheckingManager.interpret_to_end () |> inject_im_events

let interpret_in_background st =
  let checking_state, events =
    CheckingManager.interpret_in_background st.document st.checking_state in
  {st with checking_state}, inject_im_events events

let executed_ranges st =
  CheckingManager.executed_ranges st.document st.checking_state

let observe_id_range st = CheckingManager.observe_id_range st.document st.checking_state

let get_messages st id = CheckingManager.get_messages st.document id
let get_proof st id = CheckingManager.get_proof st.document st.checking_state id
let reset_to_top st =
  { st with checking_state = CheckingManager.reset_to_top st.checking_state }

module Internal = struct
          
  let document st = st.document
          
  let raw_document st = 
    Document.raw_document st.document

  let observe_id st = CheckingManager.get_observe_id st.checking_state

  let validate_document st parsing_end_info = validate_document st parsing_end_info

  let is_locally_executed st id =
    match Document.get_sentence st.document id with
    | Some { checked = Some (Success (Some _) | Failure (_,_,Some _)) } -> true
    | _ -> false

  let string_of_state st =
    let code_lines_by_id = Document.code_lines_sorted_by_loc st.document in
    let code_lines_by_end = Document.code_lines_by_end_sorted_by_loc st.document in
    let string_of_state id =
      if is_locally_executed st id then "(executed)"
      else if CheckingManager.Internal.is_remotely_executed st.checking_state id then "(executed in worker)"
      else "(not executed)"
    in
    let string_of_item item =
      Document.Internal.string_of_item item ^ " " ^
        match item with
        | Sentence { id } -> string_of_state id
        | ParsingError _ -> "(error)"
        | Comment _ -> "(comment)"
    in
    let string_by_id = String.concat "\n" @@ List.map string_of_item code_lines_by_id in
    let string_by_end = String.concat "\n" @@ List.map string_of_item code_lines_by_end in
    String.concat "\n" ["Document using sentences_by_id map\n"; string_by_id; "\nDocument using sentences_by_end map\n"; string_by_end]
    let inject_doc_events = inject_doc_events

end
