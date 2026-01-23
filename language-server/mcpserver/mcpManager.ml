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
open McpBase_lib.McpBase
module ToolArgs = VsrocqTools_lib.VsrocqTools.Args


let init_state : Vernacstate.t option ref = ref None
let get_init_state () =
  match !init_state with
  | Some st -> st
  | None -> CErrors.anomaly Pp.(str "Initial state not available")

type doc_state = {
  mutable st : Dm.DocumentManager.state;
  mutable pending_events : Dm.DocumentManager.event Sel.Event.t list;
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
      let handled = Dm.DocumentManager.handle_event ready doc.st
        ~block:!block_on_first_error !check_mode !diff_mode !pretty_print_mode in
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

(** Format the interpretation result with position info *)
let format_interp_result (doc : doc_state) : string =
  McpPrinting.format_interp_result doc.st

(** Initialize Coq for a document - Rocq >= 9.0 version *)
let init_document local_args vst =
  let () = Vernacstate.unfreeze_full_state vst in
  let () = Coqinit.init_document local_args in
  Vernacstate.freeze_full_state ()

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
    let local_args = McpArgs.Args.get_local_args dir in
    let vst = init_document local_args vst in
    try
      let document_text = get_file_text uri text in
      let st, events = Dm.DocumentManager.init vst
      ~opts:(Coqargs.injection_commands local_args) doc_uri ~text:document_text in
      let doc = { st; pending_events = events } in
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

(* TODO: share common code between all the interpret* and step* handle functions *)
let handle_interpret_to_point args =
  let open ToolArgs in
  let ({ uri; line; character } : interpret_to_point) = interpret_to_point_of_yojson args in
  log (fun () -> Printf.sprintf "Interpret to point: %s:%d:%d" uri line character);

  match Hashtbl.find_opt states uri with
  | None -> ToolsCallResult.error (Printf.sprintf "Document %s is not open" uri)
  | Some doc ->
    wait_for_parsing doc;
    let pos = Position.create ~line ~character in
    let events = Dm.DocumentManager.interpret_to_position pos !check_mode ~point_interp_mode:!point_interp_mode in
    doc.pending_events <- doc.pending_events @ events;
    process_events_until_stable doc;
    ToolsCallResult.success [Content.text (format_interp_result doc)]

let handle_interpret_to_end args =
  let open ToolArgs in
  let ({ uri } : interpret_to_end) = interpret_to_end_of_yojson args in
  log (fun () -> Printf.sprintf "Interpret to end: %s" uri);

  match Hashtbl.find_opt states uri with
  | None -> ToolsCallResult.error (Printf.sprintf "Document %s is not open" uri)
  | Some doc ->
    wait_for_parsing doc;
    let events = Dm.DocumentManager.interpret_to_end !check_mode in
    doc.pending_events <- doc.pending_events @ events;
    process_events_until_stable doc;
    ToolsCallResult.success [Content.text (format_interp_result doc)]

let handle_step_forward args =
  let open ToolArgs in
  let ({ uri } : step_forward) = step_forward_of_yojson args in
  log (fun () -> Printf.sprintf "Step forward: %s" uri);

  match Hashtbl.find_opt states uri with
  | None -> ToolsCallResult.error (Printf.sprintf "Document %s is not open" uri)
  | Some doc ->
    wait_for_parsing doc;
    let events = Dm.DocumentManager.interpret_to_next !check_mode in
    doc.pending_events <- doc.pending_events @ events;
    process_events_until_stable doc;
    ToolsCallResult.success [Content.text (format_interp_result doc)]

let handle_step_backward args =
  let open ToolArgs in
  let ({ uri } : step_backward) = step_backward_of_yojson args in
  log (fun () -> Printf.sprintf "Step backward: %s" uri);

  match Hashtbl.find_opt states uri with
  | None -> ToolsCallResult.error (Printf.sprintf "Document %s is not open" uri)
  | Some doc ->
    wait_for_parsing doc;
    let events = Dm.DocumentManager.interpret_to_previous !check_mode in
    doc.pending_events <- doc.pending_events @ events;
    process_events_until_stable doc;
    ToolsCallResult.success [Content.text (format_interp_result doc)]

let handle_get_proof_state args =
  let open ToolArgs in
  let ({ uri } : get_proof_state) = get_proof_state_of_yojson args in
  log (fun () -> Printf.sprintf "Get proof state: %s" uri);

  match Hashtbl.find_opt states uri with
  | None -> ToolsCallResult.error (Printf.sprintf "Document %s is not open" uri)
  | Some doc ->
    wait_for_parsing doc;
    ToolsCallResult.success [Content.text (format_interp_result doc)]

let handle_apply_edit args =
  let open ToolArgs in
  let { uri; startLine; startCharacter; endLine; endCharacter; newText } = apply_edit_of_yojson args in
  log (fun () -> Printf.sprintf "Apply edit: %s" uri);

  match Hashtbl.find_opt states uri with
  | None -> ToolsCallResult.error (Printf.sprintf "Document %s is not open" uri)
  | Some doc ->
    let range = Range.create
      ~start:(Position.create ~line:startLine ~character:startCharacter)
      ~end_:(Position.create ~line:endLine ~character:endCharacter) in
    let st, events = Dm.DocumentManager.apply_text_edits doc.st [(range, newText)] in
    doc.st <- st;
    doc.pending_events <- doc.pending_events @ events;
    wait_for_parsing doc;
    let updated_text = Dm.RawDocument.text (Dm.DocumentManager.Internal.raw_document doc.st) in
    try
      write_file_text uri updated_text;
      ToolsCallResult.success [Content.text "Edit applied and file saved successfully."]
    with e ->
      let msg = Printf.sprintf "Edit applied but failed to save file: %s" (Printexc.to_string e) in
      log (fun () -> msg);
      ToolsCallResult.error msg

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
  | "apply_edit" -> handle_apply_edit args
  | _ -> ToolsCallResult.error (Printf.sprintf "Unknown tool: %s" name)

(** Handle MCP notifications *)
let handle_notification (notif : Notification.t) =
  log (fun () -> Printf.sprintf "Handling notification: %s" notif.method_);
  match notif.method_ with
  | "notifications/initialized" -> ()
  | _ ->
    log (fun () -> Printf.sprintf "Unhandled notification: %s" notif.method_);
    ()

(** Handle MCP requests *)
let handle_request (req : Request.t) =
  log (fun () -> Printf.sprintf "Handling request: %s" req.method_);
  match req.method_ with
  | "initialize" ->
    let params = Option.map InitializeParams.t_of_yojson req.params in
    log (fun () -> Printf.sprintf "Initialize from: %s"
      (match params with Some p -> p.clientInfo.name | None -> "unknown"));
    let result = InitializeResult.{
      protocolVersion = "2025-11-25";
      (* TODO: use version from vsrocq *)
      serverInfo = { name = "vsrocqmcp"; version = "0.1.0" };
      capabilities = { tools = Some { listChanged = None } };
    } in
    Response.ok req.id (InitializeResult.yojson_of_t result)

  | "tools/list" ->
    let result = ToolsListResult.{ tools = VsrocqTools_lib.VsrocqTools.Definitions.all } in
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
