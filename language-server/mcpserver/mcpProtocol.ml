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

(** MCP (Model Context Protocol) definitions for VSRocq *)

open Ppx_yojson_conv_lib.Yojson_conv.Primitives

(** Tool input schema following JSON Schema *)
module JsonSchema = struct
  type property = {
    type_ : string [@key "type"];
    description : string;
  } [@@deriving yojson]

  type t = {
    type_ : string;
    properties : (string * property) list;
    required : string list;
  }

  let yojson_of_t schema =
    `Assoc [
      ("type", `String schema.type_);
      ("properties", `Assoc (List.map (fun (k, v) -> (k, yojson_of_property v)) schema.properties));
      ("required", `List (List.map (fun s -> `String s) schema.required));
    ]

  let t_of_yojson _ = failwith "JsonSchema.t_of_yojson not implemented"
end

(** Tool definition *)
module Tool = struct
  type t = {
    name : string;
    description : string;
    inputSchema : JsonSchema.t;
  }

  let yojson_of_t tool =
    `Assoc [
      ("name", `String tool.name);
      ("description", `String tool.description);
      ("inputSchema", JsonSchema.yojson_of_t tool.inputSchema);
    ]

  let t_of_yojson _ = failwith "Tool.t_of_yojson not implemented"
end

(** Content types for tool results *)
module Content = struct
  type text_content = {
    type_ : string [@key "type"];
    text : string;
  } [@@deriving yojson]

  type t = TextContent of text_content

  let yojson_of_t = function
    | TextContent tc -> yojson_of_text_content tc

  let t_of_yojson json = TextContent (text_content_of_yojson json)

  let text s = TextContent { type_ = "text"; text = s }
end

(** Server capabilities *)
module ServerCapabilities = struct
  type tools_capability = {
    listChanged : bool option;
  }

  let yojson_of_tools_capability tc =
    let fields = match tc.listChanged with
      | Some b -> [("listChanged", `Bool b)]
      | None -> []
    in
    `Assoc fields

  type t = {
    tools : tools_capability option;
  }

  let yojson_of_t caps =
    let fields = match caps.tools with
      | Some tc -> [("tools", yojson_of_tools_capability tc)]
      | None -> []
    in
    `Assoc fields
end

(** Server info *)
module ServerInfo = struct
  type t = {
    name : string;
    version : string;
  } [@@deriving yojson]
end

(** Initialize request params *)
module InitializeParams = struct
  type client_info = {
    name : string;
    version : string option;
  }

  let client_info_of_yojson json =
    let open Yojson.Safe.Util in
    {
      name = json |> member "name" |> to_string;
      version = json |> member "version" |> to_string_option;
    }

  type t = {
    protocolVersion : string;
    clientInfo : client_info;
    capabilities : Yojson.Safe.t option;
  }

  let t_of_yojson json =
    let open Yojson.Safe.Util in
    {
      protocolVersion = json |> member "protocolVersion" |> to_string;
      clientInfo = json |> member "clientInfo" |> client_info_of_yojson;
      capabilities = (try Some (json |> member "capabilities") with _ -> None);
    }
end

(** Initialize result *)
module InitializeResult = struct
  type t = {
    protocolVersion : string;
    serverInfo : ServerInfo.t;
    capabilities : ServerCapabilities.t;
  }

  let yojson_of_t result =
    `Assoc [
      ("protocolVersion", `String result.protocolVersion);
      ("serverInfo", ServerInfo.yojson_of_t result.serverInfo);
      ("capabilities", ServerCapabilities.yojson_of_t result.capabilities);
    ]
end

(** Tools/list result *)
module ToolsListResult = struct
  type t = {
    tools : Tool.t list;
  }

  let yojson_of_t result =
    `Assoc [("tools", `List (List.map Tool.yojson_of_t result.tools))]
end

(** Tools/call params *)
module ToolsCallParams = struct
  type t = {
    name : string;
    arguments : Yojson.Safe.t option;
  }

  let t_of_yojson json =
    let open Yojson.Safe.Util in
    {
      name = json |> member "name" |> to_string;
      arguments = (match json |> member "arguments" with `Null -> None | x -> Some x);
    }
end

(** Tools/call result *)
module ToolsCallResult = struct
  type t = {
    content : Content.t list;
    isError : bool option;
  }

  let yojson_of_t result =
    let base = [
      ("content", `List (List.map Content.yojson_of_t result.content));
    ] in
    let fields = match result.isError with
      | Some true -> ("isError", `Bool true) :: base
      | _ -> base
    in
    `Assoc fields

  let success contents = { content = contents; isError = None }
  let error msg = { content = [Content.text msg]; isError = Some true }
end

(** Our specific tool argument types *)
module ToolArgs = struct
  type open_document = {
    uri : string;
    text : string option [@yojson.option];
  } [@@deriving yojson]

  type close_document = {
    uri : string;
  } [@@deriving yojson]

  type interpret_to_point = {
    uri : string;
    line : int;
    character : int;
  } [@@deriving yojson]

  type interpret_to_end = {
    uri : string;
  } [@@deriving yojson]

  type step_forward = {
    uri : string;
  } [@@deriving yojson]

  type step_backward = {
    uri : string;
  } [@@deriving yojson]

  type get_proof_state = {
    uri : string;
  } [@@deriving yojson]

  type apply_edit = {
    uri : string;
    startLine : int;
    startCharacter : int;
    endLine : int;
    endCharacter : int;
    newText : string;
  } [@@deriving yojson]
end

(** Tool definitions for our prover *)
let tool_definitions : Tool.t list = [
  {
    name = "open_document";
    description = "Open a Coq/Rocq document for proving. Must be called before any other operations on a document.";
    inputSchema = {
      type_ = "object";
      properties = [
        ("uri", { JsonSchema.type_ = "string"; description = "The URI/path of the document" });
        ("text", { JsonSchema.type_ = "string"; description = "The full text content of the document (optional - will be read from file if not provided)" });
      ];
      required = ["uri"];
    };
  };
  {
    name = "close_document";
    description = "Close a previously opened document, freeing associated resources.";
    inputSchema = {
      type_ = "object";
      properties = [
        ("uri", { JsonSchema.type_ = "string"; description = "The URI of the document to close" });
      ];
      required = ["uri"];
    };
  };
  {
    name = "interpret_to_point";
    description = "Execute the Coq/Rocq document up to a specific position. Returns the proof state at that position.";
    inputSchema = {
      type_ = "object";
      properties = [
        ("uri", { JsonSchema.type_ = "string"; description = "The URI of the document" });
        ("line", { JsonSchema.type_ = "integer"; description = "The 0-indexed line number" });
        ("character", { JsonSchema.type_ = "integer"; description = "The 0-indexed character position" });
      ];
      required = ["uri"; "line"; "character"];
    };
  };
  {
    name = "interpret_to_end";
    description = "Execute the entire Coq/Rocq document to the end. Returns the final proof state.";
    inputSchema = {
      type_ = "object";
      properties = [
        ("uri", { JsonSchema.type_ = "string"; description = "The URI of the document" });
      ];
      required = ["uri"];
    };
  };
  {
    name = "step_forward";
    description = "Execute the next sentence/command in the Coq/Rocq document. Returns the resulting proof state.";
    inputSchema = {
      type_ = "object";
      properties = [
        ("uri", { JsonSchema.type_ = "string"; description = "The URI of the document" });
      ];
      required = ["uri"];
    };
  };
  {
    name = "step_backward";
    description = "Undo the last executed sentence/command, moving back one step. Returns the resulting proof state.";
    inputSchema = {
      type_ = "object";
      properties = [
        ("uri", { JsonSchema.type_ = "string"; description = "The URI of the document" });
      ];
      required = ["uri"];
    };
  };
  {
    name = "get_proof_state";
    description = "Get the current proof state without executing any commands. Returns goals, hypotheses, and messages.";
    inputSchema = {
      type_ = "object";
      properties = [
        ("uri", { JsonSchema.type_ = "string"; description = "The URI of the document" });
      ];
      required = ["uri"];
    };
  };
  {
    name = "apply_edit";
    description = "Apply a text edit to the document. The edit replaces text in the specified range with new text.";
    inputSchema = {
      type_ = "object";
      properties = [
        ("uri", { JsonSchema.type_ = "string"; description = "The URI of the document" });
        ("startLine", { JsonSchema.type_ = "integer"; description = "Start line of the range to replace (0-indexed)" });
        ("startCharacter", { JsonSchema.type_ = "integer"; description = "Start character of the range (0-indexed)" });
        ("endLine", { JsonSchema.type_ = "integer"; description = "End line of the range (0-indexed)" });
        ("endCharacter", { JsonSchema.type_ = "integer"; description = "End character of the range (0-indexed)" });
        ("newText", { JsonSchema.type_ = "string"; description = "The new text to insert" });
      ];
      required = ["uri"; "startLine"; "startCharacter"; "endLine"; "endCharacter"; "newText"];
    };
  };
]

(** JSON-RPC request structure *)
module Request = struct
  type t = {
    jsonrpc : string;
    id : Yojson.Safe.t;
    method_ : string;
    params : Yojson.Safe.t option;
  }

  let t_of_yojson json =
    let open Yojson.Safe.Util in
    {
      jsonrpc = json |> member "jsonrpc" |> to_string;
      id = json |> member "id";
      method_ = json |> member "method" |> to_string;
      params = (match json |> member "params" with `Null -> None | x -> Some x);
    }
end

(** JSON-RPC response structure *)
module Response = struct
  type error = {
    code : int;
    message : string;
    data : Yojson.Safe.t option;
  }

  let yojson_of_error e =
    let base = [("code", `Int e.code); ("message", `String e.message)] in
    let fields = match e.data with
      | Some d -> ("data", d) :: base
      | None -> base
    in
    `Assoc fields

  type t = {
    jsonrpc : string;
    id : Yojson.Safe.t;
    result : Yojson.Safe.t option;
    error : error option;
  }

  let yojson_of_t resp =
    let fields = [("jsonrpc", `String resp.jsonrpc); ("id", resp.id)] in
    let fields = match resp.result with
      | Some r -> ("result", r) :: fields
      | None -> fields
    in
    let fields = match resp.error with
      | Some e -> ("error", yojson_of_error e) :: fields
      | None -> fields
    in
    `Assoc (List.rev fields)

  let ok id result = { jsonrpc = "2.0"; id; result = Some result; error = None }
  let err id code message = { jsonrpc = "2.0"; id; result = None; error = Some { code; message; data = None } }
end

(** JSON-RPC notification structure *)
module Notification = struct
  type t = {
    jsonrpc : string;
    method_ : string;
    params : Yojson.Safe.t option;
  }

  let t_of_yojson json =
    let open Yojson.Safe.Util in
    {
      jsonrpc = json |> member "jsonrpc" |> to_string;
      method_ = json |> member "method" |> to_string;
      params = (match json |> member "params" with `Null -> None | x -> Some x);
    }
end
