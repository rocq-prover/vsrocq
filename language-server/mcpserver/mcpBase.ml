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

(** Pure MCP (Model Context Protocol) types and JSON-RPC definitions.
    This module contains protocol-level definitions independent of any
    specific tool implementations. *)

open Ppx_yojson_conv_lib.Yojson_conv.Primitives

(** JSON Schema *)

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

  let property ~type_ ~description = { type_; description }

  let make ~properties ~required =
    { type_ = "object"; properties; required }
end

(** Tool Definition *)

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

  let make ~name ~description ~inputSchema = { name; description; inputSchema }
end

(** Content Types *)

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

(** Server Types *)

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

  let with_tools ?listChanged () =
    { tools = Some { listChanged } }

  let empty = { tools = None }
end

module ServerInfo = struct
  type t = {
    name : string;
    version : string;
  } [@@deriving yojson]

  let make ~name ~version = { name; version }
end

(** Initialize Protocol *)

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

  let make ~protocolVersion ~serverInfo ~capabilities =
    { protocolVersion; serverInfo; capabilities }
end

(** Tools Protocol *)

module ToolsListResult = struct
  type t = {
    tools : Tool.t list;
  }

  let yojson_of_t result =
    `Assoc [("tools", `List (List.map Tool.yojson_of_t result.tools))]

  let make tools = { tools }
end

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

(** JSON-RPC *)

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
