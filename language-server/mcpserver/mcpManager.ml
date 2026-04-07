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
open McpProtocol_lib.McpProtocol


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

(** Output a JSON message to stdout with content-length header *)
let output_json obj =
  let msg = Yojson.Safe.pretty_to_string ~std:true obj in
  let size = String.length msg in
  let s = Printf.sprintf "Content-Length: %d\r\n\r\n%s" size msg in
  log (fun () -> "sent: " ^ msg);
  ignore(Unix.write_substring Unix.stdout s 0 (String.length s))

(** Send a JSON-RPC response *)
let send_response resp =
  output_json (Response.yojson_of_t resp)

(** Process document manager events synchronously until stable *)
let rec process_events_until_stable (doc : doc_state) =
  match doc.pending_events with
  | [] -> ()
  | _ ->
    let todo = Sel.Todo.add Sel.Todo.empty doc.pending_events in
    doc.pending_events <- [];
    process_events_loop doc todo

and process_events_loop doc todo =
  if Sel.Todo.size todo = 0 then
    ()
  else begin
    let ready, todo = Sel.pop todo in
    let handled = Dm.DocumentManager.handle_event ready doc.st
      ~block:!block_on_first_error !check_mode !diff_mode !pretty_print_mode in
    begin match handled.state with
    | Some new_st -> doc.st <- new_st
    | None -> ()
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

(** Format proof state using PpProofState (string-based) for cleaner output *)
let format_pp_proof_state (ps : Protocol.PpProofState.t option) : string =
  match ps with
  | None -> "No proof in progress."
  | Some { goals; shelvedGoals; givenUpGoals; unfocusedGoals } ->
    let format_goal (g : Protocol.PpProofState.goal) =
      let hyps = List.map (fun (h : Protocol.PpProofState.hypothesis) ->
        let ids = String.concat ", " h.ids in
        let body = match h.body with
          | Some b -> " := " ^ b
          | None -> ""
        in
        Printf.sprintf "%s%s : %s" ids body h._type
      ) g.hypotheses in
      Printf.sprintf "Goal %d:\n  %s\n  ============================\n  %s"
        g.id
        (String.concat "\n  " hyps)
        g.goal
    in
    let goals_str =
      if goals = [] then "No more subgoals."
      else Printf.sprintf "%d goal(s):\n%s"
        (List.length goals)
        (String.concat "\n\n" (List.map format_goal goals))
    in
    let shelved_str =
      if shelvedGoals = [] then ""
      else Printf.sprintf "\n\nShelved goals: %d" (List.length shelvedGoals)
    in
    let given_up_str =
      if givenUpGoals = [] then ""
      else Printf.sprintf "\n\nGiven up goals: %d" (List.length givenUpGoals)
    in
    let unfocused_str =
      if unfocusedGoals = [] then ""
      else Printf.sprintf "\n\nUnfocused goals: %d" (List.length unfocusedGoals)
    in
    goals_str ^ shelved_str ^ given_up_str ^ unfocused_str

(** Get the current proof state for a document *)
let get_current_proof_state (doc : doc_state) : string =
  let observe_id = Dm.DocumentManager.Internal.observe_id doc.st in
  let ost = Option.bind observe_id
    (Dm.ExecutionManager.get_vernac_state (Dm.DocumentManager.Internal.execution_state doc.st)) in
  match ost with
  | None -> "No proof state available (document may not be executed to this point)."
  | Some vst -> format_pp_proof_state (Protocol.PpProofState.get_proof vst)

(** Get diagnostics/messages for the current state *)
let get_diagnostics (doc : doc_state) : string =
  let diags = Dm.DocumentManager.all_diagnostics doc.st in
  if diags = [] then "No diagnostics."
  else
    let format_diag (d : Diagnostic.t) =
      let severity = match d.severity with
        | Some DiagnosticSeverity.Error -> "Error"
        | Some DiagnosticSeverity.Warning -> "Warning"
        | Some DiagnosticSeverity.Information -> "Info"
        | Some DiagnosticSeverity.Hint -> "Hint"
        | None -> "Unknown"
      in
      let msg = match d.message with
        | `String s -> s
        | `MarkupContent m -> m.value
      in
      Printf.sprintf "[%s] Line %d: %s" severity (d.range.start.line + 1) msg
    in
    String.concat "\n" (List.map format_diag diags)

(** Initialize Coq for a document - Rocq >= 9.0 version *)
let init_document local_args vst =
  let () = Vernacstate.unfreeze_full_state vst in
  let () = Coqinit.init_document local_args in
  Vernacstate.freeze_full_state ()

(** Tool handlers *)

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
      let st, events = Dm.DocumentManager.init vst
        ~opts:(Coqargs.injection_commands local_args) doc_uri ~text in
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

    let proof_state = get_current_proof_state doc in
    let diagnostics = get_diagnostics doc in
    ToolsCallResult.success [
      Content.text (Printf.sprintf "Proof state:\n%s\n\nDiagnostics:\n%s" proof_state diagnostics)
    ]

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

    let proof_state = get_current_proof_state doc in
    let diagnostics = get_diagnostics doc in
    ToolsCallResult.success [
      Content.text (Printf.sprintf "Proof state:\n%s\n\nDiagnostics:\n%s" proof_state diagnostics)
    ]

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

    let proof_state = get_current_proof_state doc in
    let diagnostics = get_diagnostics doc in
    ToolsCallResult.success [
      Content.text (Printf.sprintf "Proof state:\n%s\n\nDiagnostics:\n%s" proof_state diagnostics)
    ]

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

    let proof_state = get_current_proof_state doc in
    let diagnostics = get_diagnostics doc in
    ToolsCallResult.success [
      Content.text (Printf.sprintf "Proof state:\n%s\n\nDiagnostics:\n%s" proof_state diagnostics)
    ]

let handle_get_proof_state args =
  let open ToolArgs in
  let ({ uri } : get_proof_state) = get_proof_state_of_yojson args in
  log (fun () -> Printf.sprintf "Get proof state: %s" uri);

  match Hashtbl.find_opt states uri with
  | None -> ToolsCallResult.error (Printf.sprintf "Document %s is not open" uri)
  | Some doc ->
    wait_for_parsing doc;
    let proof_state = get_current_proof_state doc in
    let diagnostics = get_diagnostics doc in
    ToolsCallResult.success [
      Content.text (Printf.sprintf "Proof state:\n%s\n\nDiagnostics:\n%s" proof_state diagnostics)
    ]

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
    ToolsCallResult.success [Content.text "Edit applied successfully."]

let handle_query args =
  let open ToolArgs in
  let { uri; line; character; command; pattern } = query_of_yojson args in
  log (fun () -> Printf.sprintf "Query %s: %s" command pattern);

  match Hashtbl.find_opt states uri with
  | None -> ToolsCallResult.error (Printf.sprintf "Document %s is not open" uri)
  | Some doc ->
    wait_for_parsing doc;
    let pos = Position.create ~line ~character in
    let result =
      match command with
      | "about" -> Dm.DocumentManager.about doc.st pos ~pattern
      | "check" -> Dm.DocumentManager.check doc.st pos ~pattern
      | "print" -> Dm.DocumentManager.print doc.st pos ~pattern
      | "locate" -> Dm.DocumentManager.locate doc.st pos ~pattern
      | _ -> Error { message = Printf.sprintf "Unknown query command: %s" command; code = None }
    in
    match result with
    | Ok pp ->
      (* Convert Protocol.Printing.pp to JSON and extract text *)
      let json = Protocol.Printing.yojson_of_pp pp in
      let rec extract_strings json =
        match json with
        | `String s -> s
        | `List l -> String.concat "" (List.map extract_strings l)
        | `Assoc fields ->
          (match List.assoc_opt "Ppcmd_string" fields with
           | Some (`List [`String s]) -> s
           | _ ->
             List.fold_left (fun acc (_, v) -> acc ^ extract_strings v) "" fields)
        | _ -> ""
      in
      ToolsCallResult.success [Content.text (extract_strings json)]
    | Error { message; _ } ->
      ToolsCallResult.error message

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
  | "query" -> handle_query args
  | _ -> ToolsCallResult.error (Printf.sprintf "Unknown tool: %s" name)

(** Handle MCP requests *)
let handle_request (req : Request.t) =
  log (fun () -> Printf.sprintf "Handling request: %s" req.method_);
  match req.method_ with
  | "initialize" ->
    let params = Option.map InitializeParams.t_of_yojson req.params in
    log (fun () -> Printf.sprintf "Initialize from: %s"
      (match params with Some p -> p.clientInfo.name | None -> "unknown"));
    let result = InitializeResult.{
      protocolVersion = "2024-11-05";
      serverInfo = { name = "vsrocq-mcp-server"; version = "0.1.0" };
      capabilities = { tools = Some { listChanged = None } };
    } in
    Response.ok req.id (InitializeResult.yojson_of_t result)

  | "notifications/initialized" ->
    Response.ok req.id `Null

  | "tools/list" ->
    let result = ToolsListResult.{ tools = tool_definitions } in
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

(** Read a JSON-RPC message from stdin *)
let read_message () =
  let header = input_line stdin in
  log (fun () -> "Header: " ^ header);
  let content_length =
    if String.length header >= 16 && String.sub header 0 16 = "Content-Length: " then
      int_of_string (String.trim (String.sub header 16 (String.length header - 16)))
    else
      failwith "Expected Content-Length header"
  in
  let _ = input_line stdin in
  let content = Bytes.create content_length in
  really_input stdin content 0 content_length;
  let json_str = Bytes.to_string content in
  log (fun () -> "Received: " ^ json_str);
  Yojson.Safe.from_string json_str

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
      log (fun () -> Printf.sprintf "Received notification: %s" notif.method_);
      ()
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
