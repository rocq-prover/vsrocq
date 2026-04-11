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

(** MCP server manager for VSRocq - handles MCP protocol and coordinates with DocumentManager *)

open Lsp.Types
open Dm.Types
open McpBase
module ToolArgs = VsrocqTools.Args


let init_state : Vernacstate.t option ref = ref None
let get_init_state () =
  match !init_state with
  | Some st -> st
  | None -> CErrors.anomaly Pp.(str "Initial state not available")

type doc_state = {
  mutable st : Dm.DocumentManager.state;
  mutable pending_events : Dm.DocumentManager.event Sel.Event.t list;
  mutable current_position : Position.t;  (* Track current proof position for queries *)
}

let states : (string, doc_state) Hashtbl.t = Hashtbl.create 39

let check_mode = ref Protocol.Settings.Mode.Manual
let diff_mode = ref Protocol.Settings.Goals.Diff.Mode.Off
let pretty_print_mode = ref Protocol.Settings.Goals.PrettyPrint.String
let block_on_first_error = ref true
let point_interp_mode = ref Protocol.Settings.PointInterpretationMode.Cursor

let Log log = Dm.Log.mk_log "mcpManager"

(** Output a JSON message to stdout in MCP format (direct JSON) *)
let output_json obj =
  let msg = Yojson.Safe.to_string ~std:true obj in
  log (fun () -> "sent: " ^ msg);
  Printf.printf "%s\n%!" msg

(** Send a JSON-RPC response *)
let send_response resp =
  output_json (Response.yojson_of_t resp)

(** Process document manager events synchronously until stable (no more pending events) *)
let rec process_events_until_stable (doc : doc_state) =
  match doc.pending_events with
  | [] -> ()
  | _ ->
    let todo = Sel.Todo.add Sel.Todo.empty doc.pending_events in
    doc.pending_events <- [];
    process_events_loop doc todo;
and process_events_loop doc todo =
  if Sel.Todo.size todo = 0 then begin ()
  end else begin
    let ready, todo = Sel.pop_timeout ~stop_after_being_idle_for:0.1 todo in
    match ready with
    | None ->
      (* No more ready events - stop processing *)
      ()
    | Some ready ->
      let handled = Dm.DocumentManager.handle_event ready doc.st in
      begin match handled.state with
      | Some new_st ->
        doc.st <- new_st
      | None ->
        ()
      end;
      let todo = Sel.Todo.add todo handled.events in
      process_events_loop doc todo
  end

(** Wait for parsing to complete *)
let wait_for_parsing (doc : doc_state) =
  let rec loop () =
    if Dm.DocumentManager.is_parsing doc.st then begin
      process_events_until_stable doc;
      if Dm.DocumentManager.is_parsing doc.st then begin
        Unix.sleepf 0.01;
        loop ()
      end
    end
  in
  loop ()

let format_interp_result (doc : doc_state) : string =
  McpPrinting.format_interp_result doc.st

[%%if rocq = "8.18" || rocq = "8.19" || rocq = "8.20"]
(* in these rocq versions init_runtime called globally for the process includes init_document
   this means in these versions we do not support local _CoqProject except for the effect on injections
   (eg -noinit) *)
let init_document _ vst = vst
[%%else]
let init_document local_args vst =
  let () = Vernacstate.unfreeze_full_state vst in
  let () = Coqinit.init_document local_args in
  Vernacstate.freeze_full_state ()
[%%endif]

(** Tool handlers *)

let get_file_text uri text =
  match text with
  | Some t -> t
  | None ->
    try
      let ic = open_in uri in
      let text = really_input_string ic (in_channel_length ic) in
      close_in ic;
      text
    with e ->
      let msg = Printf.sprintf "Failed to read file %s: %s" uri (Printexc.to_string e) in
      failwith msg

let write_file_text uri text =
  let oc = open_out uri in
  output_string oc text;
  close_out oc;
  log (fun () -> Printf.sprintf "Written file %s" uri)

(** Ensure the in-memory document is synchronized with disk content.
    Automatically updates the state if the file has changed externally. *)
let ensure_document_sync (doc: doc_state) uri =
  try
    let disk_text = get_file_text uri None in
    let raw = Dm.DocumentManager.Internal.raw_document doc.st in
    if disk_text = Dm.RawDocument.text raw then
      log (fun () -> "Document already in sync")
    else begin
      log (fun () -> "Document changed on disk, syncing...");
      let end_pos = Dm.RawDocument.position_of_loc raw (Dm.RawDocument.end_loc raw) in
      let range = Range.create
        ~start:(Position.create ~line:0 ~character:0)
        ~end_:end_pos in
      let st, events = Dm.DocumentManager.apply_text_edits doc.st [(range, disk_text)] in
      doc.st <- st;
      doc.pending_events <- doc.pending_events @ events;
      wait_for_parsing doc;
      process_events_until_stable doc;
      log (fun () -> "Document synced successfully")
    end
  with e ->
    log (fun () -> Printf.sprintf "Failed to sync document: %s" (Printexc.to_string e))

let handle_open_document args =
  let open ToolArgs in
  let { uri; text } = open_document_of_yojson args in
  log (fun () -> Printf.sprintf "Opening document: %s" uri);

  if Hashtbl.mem states uri then
    ToolsCallResult.error (Printf.sprintf "Document %s is already open" uri)
  else begin
    let vst = get_init_state () in
    let doc_uri = DocumentUri.of_path uri in
    let dir = Filename.dirname uri in
    let local_args = Args.get_local_args dir in
    let vst = init_document local_args vst in
    try
      let document_text = get_file_text uri text in
      let st, events = Dm.DocumentManager.init vst
      ~opts:(Coqargs.injection_commands local_args) doc_uri ~text:document_text in
      let doc = { st; pending_events = events; current_position = Position.create ~line:0 ~character:0 } in
      Hashtbl.add states uri doc;
      wait_for_parsing doc;
      ToolsCallResult.success [Content.text (Printf.sprintf "Document %s opened successfully." uri)]
    with e ->
      let info = Exninfo.capture e in
      let msg = Pp.string_of_ppcmds @@ CErrors.iprint_no_report info in
      ToolsCallResult.error (Printf.sprintf "Failed to open document: %s" msg)
  end

let handle_close_document args =
  let open ToolArgs in
  let ({ uri } : close_document) = close_document_of_yojson args in
  log (fun () -> Printf.sprintf "Closing document: %s" uri);

  if Hashtbl.mem states uri then begin
    Hashtbl.remove states uri;
    ToolsCallResult.success [Content.text (Printf.sprintf "Document %s closed." uri)]
  end else
    ToolsCallResult.error (Printf.sprintf "Document %s is not open" uri)

(** Look up an open document by URI and apply a function to it *)
let with_document uri ~f =
  match Hashtbl.find_opt states uri with
  | None -> ToolsCallResult.error (Printf.sprintf "Document %s is not open" uri)
  | Some doc -> f doc

let handle_interpret_to_point args =
  let open ToolArgs in
  let ({ uri; line; character } : interpret_to_point) = interpret_to_point_of_yojson args in
  log (fun () -> Printf.sprintf "Interpret to point: %s:%d:%d" uri line character);
  let pos = Position.create ~line ~character in
  with_document uri ~f:(fun doc ->
    ensure_document_sync doc uri;
    (* Update current position for future queries *)
    doc.current_position <- pos;
    wait_for_parsing doc;
    let events = Dm.DocumentManager.interpret_to_position pos in
    doc.pending_events <- doc.pending_events @ events;
    process_events_until_stable doc;
    ToolsCallResult.success [Content.text (format_interp_result doc)])

let handle_interpret_to_end args =
  let open ToolArgs in
  let ({ uri } : interpret_to_end) = interpret_to_end_of_yojson args in
  log (fun () -> Printf.sprintf "Interpret to end: %s" uri);
  with_document uri ~f:(fun doc ->
    ensure_document_sync doc uri;
    wait_for_parsing doc;
    let events = Dm.DocumentManager.interpret_to_end () in
    doc.pending_events <- doc.pending_events @ events;
    process_events_until_stable doc;
    (* Update current position to end of document after interpretation to end *)
    let raw_doc = Dm.DocumentManager.Internal.raw_document doc.st in
    let end_loc = Dm.RawDocument.end_loc raw_doc in
    doc.current_position <- Dm.RawDocument.position_of_loc raw_doc end_loc;
    ToolsCallResult.success [Content.text (format_interp_result doc)])

let handle_step_forward args =
  let open ToolArgs in
  let ({ uri } : step_forward) = step_forward_of_yojson args in
  log (fun () -> Printf.sprintf "Step forward: %s" uri);
  with_document uri ~f:(fun doc ->
    ensure_document_sync doc uri;
    wait_for_parsing doc;
    let events = Dm.DocumentManager.interpret_to_next () in
    doc.pending_events <- doc.pending_events @ events;
    process_events_until_stable doc;
    ToolsCallResult.success [Content.text (format_interp_result doc)])

let handle_step_backward args =
  let open ToolArgs in
  let ({ uri } : step_backward) = step_backward_of_yojson args in
  log (fun () -> Printf.sprintf "Step backward: %s" uri);
  with_document uri ~f:(fun doc ->
    ensure_document_sync doc uri;
    wait_for_parsing doc;
    let events = Dm.DocumentManager.interpret_to_previous () in
    doc.pending_events <- doc.pending_events @ events;
    process_events_until_stable doc;
    ToolsCallResult.success [Content.text (format_interp_result doc)])

let handle_get_proof_state args =
  let open ToolArgs in
  let ({ uri } : get_proof_state) = get_proof_state_of_yojson args in
  log (fun () -> Printf.sprintf "Get proof state: %s" uri);
  with_document uri ~f:(fun doc ->
    ensure_document_sync doc uri;
    process_events_until_stable doc;
    let proof_state = McpPrinting.format_proof_state_response doc.st in
    ToolsCallResult.success [Content.text proof_state]
    ) (* Close the with_document call *)

let wrap_search_pattern pattern = "(" ^ pattern ^ ")"

let collect_search_results notif_events : Protocol.LspWrapper.query_result list =
  let rec loop todo results =
    let ready, new_todo = Sel.pop_timeout ~stop_after_being_idle_for:0.1 todo in
    match ready with
    | None -> results
    | Some (Protocol.LspWrapper.QueryResultNotification qr) ->
      loop (Sel.Todo.add new_todo [Dm.SearchQuery.query_feedback]) (qr :: results)
  in
  let results = loop (Sel.Todo.add Sel.Todo.empty notif_events) [] in
  List.rev results

let execute_pattern_query (doc : doc_state) (pos : Position.t)
    (query_fn : Dm.DocumentManager.state -> Position.t -> pattern:string -> (Protocol.Printing.pp, Dm.Types.error) Result.t)
    (pattern : string)
    : ToolsCallResult.t =
  let result = query_fn doc.st pos ~pattern:pattern in
  match result with
  | Ok pp -> ToolsCallResult.success [Content.text (Protocol.Printing.string_of_pp pp)]
  | Error e -> ToolsCallResult.error e.message

let handle_query args =
  let open ToolArgs in
  let ({ uri; line; character; query_type; pattern } : query) = query_of_yojson args in

  (* Use current document position if not provided, otherwise use specified position *)
  let pos = match line, character with
    | Some l, Some c -> Position.create ~line:l ~character:c
    | _, _ -> (
        match Hashtbl.find_opt states uri with
        | Some doc -> doc.current_position  (* Use current proof position *)
        | None -> Position.create ~line:0 ~character:0  (* Fallback *)
      )
  in
  log (fun () -> Printf.sprintf "Query: %s at %s:%d:%d" query_type uri pos.line pos.character);

  with_document uri ~f:(fun doc ->
    ensure_document_sync doc uri;
    wait_for_parsing doc;
    process_events_until_stable doc;
    let query_type = String.lowercase_ascii query_type in
    try
      match query_type with
      | qt when String.equal qt "search" ->
          (* Search expects the pattern to be wrapped in parentheses *)
          let wrapped_pat = wrap_search_pattern pattern in
          let notif_events = Dm.DocumentManager.search doc.st ~id:"mcp_query" pos wrapped_pat in
          let results = collect_search_results notif_events in
          if results = [] then
            ToolsCallResult.success [Content.text "No results found."]
          else begin
            let result_strings = List.rev_map (fun (qr : Protocol.LspWrapper.query_result) ->
              Printf.sprintf "%s : %s"
                (Protocol.Printing.string_of_pp qr.name)
                (Protocol.Printing.string_of_pp qr.statement)
            ) results in
            ToolsCallResult.success [Content.text (String.concat "\n" result_strings)]
          end
      | qt when String.equal qt "print" -> execute_pattern_query doc pos Dm.DocumentManager.print pattern
      | qt when String.equal qt "locate" -> execute_pattern_query doc pos Dm.DocumentManager.locate pattern
      | qt when String.equal qt "about" -> execute_pattern_query doc pos Dm.DocumentManager.about pattern
      | _ -> ToolsCallResult.error (Printf.sprintf "Unknown query type: %s" query_type)
    with e ->
      let info = Exninfo.capture e in
      let message = Pp.string_of_ppcmds @@ CErrors.iprint_no_report info in
      ToolsCallResult.error (Printf.sprintf "Query failed: %s" message)
  )

(** Dispatch tool calls *)
let dispatch_tool name args =
  let args = match args with Some a -> a | None -> `Null in
  match name with
  | "open_document" -> handle_open_document args
  | "close_document" -> handle_close_document args
  | "interpret_to_point" -> handle_interpret_to_point args
  | "interpret_to_end" -> handle_interpret_to_end args
  | "step_forward" -> handle_step_forward args
  | "step_backward" -> handle_step_backward args
  | "get_proof_state" -> handle_get_proof_state args
  | "query" -> handle_query args
  | _ -> ToolsCallResult.error (Printf.sprintf "Unknown tool: %s" name)

(** Handle MCP notifications *)
let handle_notification (notif : Notification.t) =
  log (fun () -> Printf.sprintf "Handling notification: %s" notif.method_);
  match notif.method_ with
  | "notifications/initialized" -> ()
  | _ ->
    log (fun () -> Printf.sprintf "Unhandled notification: %s" notif.method_);
    ()

let protocol_version = "2025-11-25"
let server_info =
  ServerInfo.make
    ~name:"vsrocq-model-context-server"
    ~version:VsrocqSettings.version

(** Handle MCP requests *)
let handle_request (req : Request.t) =
  log (fun () -> Printf.sprintf "Handling request: %s" req.method_);
  try
    match req.method_ with
    | "initialize" ->
      let params = Option.map InitializeParams.t_of_yojson req.params in
      log (fun () -> Printf.sprintf "Initialize from: %s"
        (match params with Some p -> p.clientInfo.name | None -> "unknown"));
      let result = InitializeResult.{
        protocolVersion = protocol_version;
        serverInfo = server_info;
        capabilities = { tools = Some { listChanged = None } };
      } in
      Response.ok req.id (InitializeResult.yojson_of_t result)

    | "tools/list" ->
      let result = ToolsListResult.{ tools = VsrocqTools.Definitions.all } in
      Response.ok req.id (ToolsListResult.yojson_of_t result)

    | "tools/call" ->
      begin match req.params with
      | None -> Response.err req.id (-32602) "Missing params for tools/call"
      | Some params ->
        let call_params = ToolsCallParams.t_of_yojson params in
        let result = dispatch_tool call_params.name call_params.arguments in
        Response.ok req.id (ToolsCallResult.yojson_of_t result)
      end

    | "ping" ->
      Response.ok req.id (`Assoc [])

    | _ ->
      Response.err req.id (-32601) (Printf.sprintf "Method not found: %s" req.method_)
  with e ->
    let info = Exninfo.capture e in
    let message = Pp.string_of_ppcmds @@ CErrors.iprint_no_report info in
    log (fun () -> Printf.sprintf "Exception in handle_request: %s" message);
    Response.err req.id (-32603) (Printf.sprintf "Internal error: %s" message)

(** Read a JSON-RPC message from stdin in MCP format (direct JSON) *)
let read_message () =
  let json_line = input_line stdin in
  log (fun () -> "Received: " ^ json_line);
  Yojson.Safe.from_string json_line

(** Main event loop *)
let rec main_loop () =
  try
    let json = read_message () in
    let has_id =
      match json with
      | `Assoc fields -> List.mem_assoc "id" fields
      | _ -> false
    in
    if has_id then begin
      let req = Request.t_of_yojson json in
      let resp = handle_request req in
      send_response resp
    end else begin
      let notif = Notification.t_of_yojson json in
      handle_notification notif
    end;
    main_loop ()
  with
  | End_of_file ->
    log (fun () -> "Client disconnected");
    ()
  | e ->
    let info = Exninfo.capture e in
    log (fun () -> "Error: " ^ Pp.string_of_ppcmds @@ CErrors.iprint_no_report info);
    main_loop ()

(** Initialize the MCP server *)
let init () =
  init_state := Some (Vernacstate.freeze_full_state ());
  log (fun () -> "MCP server initialized")
