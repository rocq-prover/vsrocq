(**************************************************************************)
(*                                                                        *)
(*                                 VSRocq                                  *)
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

open Protocol.LspWrapper
open Protocol.Printing
open Types

let Log log = Log.mk_log "queryManager"

let context_of_vernac_state (st : Vernacstate.t) =
  let st = st.Vernacstate.interp in
  Vernacstate.Interp.unfreeze_interp_state st;
  begin match st.lemmas with
  | None ->
    let env = Global.env () in
    let sigma = Evd.from_env env in
    sigma, env
  | Some lemmas ->
    let open Declare in
    let open Vernacstate in
    lemmas |> LemmaStack.with_top ~f:Proof.get_current_context
  end


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
let parse_entry st entry pattern =
  let pa = Pcoq.Parsable.make (Gramlib.Stream.of_string pattern) in
  Vernacstate.Parser.parse (Utilities.vernacstate_synterp_parsing st) entry pa
[%%else]
let parse_entry st entry pattern =
  let pa = parsable_make (Gramlib.Stream.of_string pattern) in
  unfreeze (Utilities.vernacstate_synterp_parsing st);
  entry_parse entry pa
[%%endif]

[%%if rocq ="8.18" || rocq ="8.19" || rocq ="8.20"]
  let smart_global = Pcoq.Prim.smart_global
[%%else]
  let smart_global = Procq.Prim.smart_global
[%%endif]


[%%if rocq ="8.18" || rocq ="8.19" || rocq ="8.20"]
  let lconstr = Pcoq.Constr.lconstr
[%%else]
  let lconstr = Procq.Constr.lconstr
[%%endif]



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

[%%if rocq ="8.18" || rocq ="8.19"]
  let print_name = Prettyp.print_name
[%%else]
  let print_name =
    let access = Library.indirect_accessor[@@warning "-3"] in
    Prettyp.print_name access
[%%endif]

(**************************************************************************)

let about vs ~pattern =
  (* TODO: run in execmanager *)
  let sigma, env = context_of_vernac_state vs in
    try
      let ref_or_by_not = parse_entry vs (smart_global) pattern in
      let udecl = None (* TODO? *) in
      Ok (pp_of_rocqpp @@ Prettyp.print_about env sigma ref_or_by_not udecl)
    with e ->
      let e, info = Exninfo.capture e in
      let message = Pp.string_of_ppcmds @@ CErrors.iprint (e, info) in
      Error ({message; code=None})


(** Try to generate hover text from [pattern] the context of the given [sentence] *)
let hover_of_sentence pattern = function
  | None -> None
  | Some sentence ->
    match Utilities.get_vernac_state sentence.Document.checked with
    | None -> None
    | Some vs ->
      let sigma, env = context_of_vernac_state vs in
      try
        let ref_or_by_not = parse_entry vs (smart_global) pattern in
        Language.Hover.get_hover_contents env sigma ref_or_by_not
      with e ->
        let e, info = Exninfo.capture e in
        log (fun () -> "Exception while handling hover: " ^ (Pp.string_of_ppcmds @@ CErrors.iprint (e, info)));
        None

let hover document pos =
  (* Tries to get hover at three difference places:
     - At the start of the current sentence
     - At the start of the next sentence (for symbols defined in the current sentence)
       e.g. Definition, Inductive
     - At the next QED (for symbols defined after proof), if the next sentence 
       is in proof mode e.g. Lemmas, Definition with tactics *)
  let opattern = RawDocument.word_at_position (Document.raw_document document) pos in
  match opattern with
  | None -> log (fun () -> "hover: no word found at cursor"); None
  | Some pattern ->
    log (fun () -> "hover: found word at cursor: \"" ^ pattern ^ "\"");
    (* hover at previous sentence *)
    match hover_of_sentence pattern (Document.find_sentence_before_pos document pos) with
    | Some _ as x -> x
    | None -> 
    match Document.find_sentence_after_pos document pos with
    | None -> None (* Skip if no next sentence *)
    | Some sentence as opt ->
    (* hover at next sentence *)
    match hover_of_sentence pattern opt with
    | Some _ as x -> x
    | None -> 
    match sentence.ast with
    | Error _ -> None
    | Parsed ast -> 
      match ast.classification with
    (* next sentence in proof mode, hover at qed *)
      | VtProofStep _ | VtStartProof _ -> 
        hover_of_sentence pattern (Document.find_next_qed_pos document pos)
      | _ -> None

[%%if rocq ="8.18" || rocq ="8.19" || rocq ="8.20"]
let jump_to_definition ~vs:_ _ = None
[%%else]
let jump_to_definition ~vs opattern  =
  let _side_effect_needed_ = context_of_vernac_state vs in
  match opattern with
  | None -> log (fun () -> "jumpToDef: no word found at cursor"); None
  | Some pattern ->
    log (fun () -> "jumpToDef: found word at cursor: \"" ^ pattern ^ "\"");
    try
    let qid = parse_entry vs (Procq.Prim.qualid) pattern in
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


let check ~vs ~pattern =
  let sigma, env = context_of_vernac_state vs in
  let rc = parse_entry vs lconstr pattern in
  try
    let redexpr = None in
    Ok (pp_of_rocqpp @@ Vernacentries.check_may_eval env sigma redexpr rc)
  with e ->
    let e, info = Exninfo.capture e in
    let message = Pp.string_of_ppcmds @@ CErrors.iprint (e, info) in
    Error ({message; code=None})

let locate ~vs ~pattern =
  let sigma, env = context_of_vernac_state vs in
  match parse_entry vs (smart_global) pattern with
  | { v = AN qid } -> Ok (pp_of_rocqpp @@ print_located_qualid env qid)
  | { v = ByNotation (ntn, sc)} ->
    Ok( pp_of_rocqpp @@ Notation.locate_notation
      (pr_glob_without_symbols env sigma) ntn sc)

let search ~vs ~id pattern =
  let sigma, env = context_of_vernac_state vs in
  let query, r = parse_entry vs (G_vernac.search_queries) pattern in
  SearchQuery.interp_search ~id env sigma query r

let print ~vs ~pattern = 
  let sigma, env = context_of_vernac_state vs in
  let qid = parse_entry vs (smart_global) pattern in
  let udecl = None in (*TODO*)
  Ok (pp_of_rocqpp @@ print_name env sigma qid udecl)

let get_completions ~vs =
  let settings = ExecutionManager.get_options () in
  match CompletionSuggester.get_completions settings.completion_options vs with
  | None -> 
      log (fun () -> "No completions available");
      []
  | Some lemmas -> lemmas

(**************************************************************************)

let to_types_error = function
  | Terminated (Ok x) -> Ok x
  | Terminated (Error x) -> (Error x)
  | Interrupted -> Error ({message = "Interrupted"; code=None})
  | Aborted message ->
      let message = Pp.string_of_ppcmds message in
      Error ({message; code=None})

let to_list = function
  | Terminated x -> x
  | Aborted _ | Interrupted -> []

let to_option = function
  | Terminated x -> Some x
  | Aborted _ | Interrupted -> None


(* how long a query can take *)
let timeout = 0.2

let check ~doc_id ~vs ~pattern =
  ProverThread.try_run ~doc_id ~timeout (fun () -> check ~vs ~pattern) |>
  to_types_error

let jump_to_definition ~doc_id ~vs opattern =
  ProverThread.try_run ~doc_id ~timeout (fun () -> jump_to_definition ~vs opattern) |>
  to_option |> Option.flatten

let locate ~doc_id ~vs ~pattern =
  ProverThread.try_run ~doc_id ~timeout (fun () -> locate ~vs ~pattern) |>
  to_types_error

let search ~doc_id ~vs ~id pattern =
  ProverThread.try_run ~doc_id ~timeout (fun () -> search ~vs ~id pattern) |>
  to_list

let print ~doc_id ~vs ~pattern = 
  ProverThread.try_run ~doc_id ~timeout (fun () -> print ~vs ~pattern) |>
  to_types_error

let hover document pos =
  ProverThread.try_run ~doc_id:(Document.id document) ~timeout
    (fun () -> hover document pos) |>
  to_option |> Option.flatten

let about ~doc_id ~vs ~pattern =
  ProverThread.try_run ~doc_id ~timeout (fun () -> about vs ~pattern) |>
  to_types_error

let get_completions ~doc_id ~vs =
  ProverThread.try_run ~doc_id ~timeout:0.5 (fun () -> get_completions ~vs) |>
  to_list
