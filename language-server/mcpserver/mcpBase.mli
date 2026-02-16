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

(** Pure MCP (Model Context Protocol) types and JSON-RPC definitions. This
      module contains protocol-level definitions for the subset of the mcp
      protocol used in vsrocqmcp. *)

(** JSON Schema *)

module JsonSchema : sig
  type property = {
    type_ : string;
    description : string;
  }

  type t = {
    type_ : string;
    properties : (string * property) list;
    required : string list;
  }

  val yojson_of_t : t -> Yojson.Safe.t
  val t_of_yojson : Yojson.Safe.t -> t

  val property : type_:string -> description:string -> property
  val make : properties:(string * property) list -> required:string list -> t
end

(** Tool Definition *)

module Tool : sig
  type t = {
    name : string;
    description : string;
    inputSchema : JsonSchema.t;
  }

  val yojson_of_t : t -> Yojson.Safe.t
  val t_of_yojson : Yojson.Safe.t -> t

  val make : name:string -> description:string -> inputSchema:JsonSchema.t -> t
end

(** Content Types *)

module Content : sig
  type t

  val yojson_of_t : t -> Yojson.Safe.t
  val t_of_yojson : Yojson.Safe.t -> t

  val text : string -> t
end

(** Server Types *)

module ServerCapabilities : sig
  type tools_capability = {
    listChanged : bool option;
  }

  type t = {
    tools : tools_capability option;
  }

  val yojson_of_t : t -> Yojson.Safe.t

  val with_tools : ?listChanged:bool -> unit -> t
  val empty : t
end

module ServerInfo : sig
  type t = {
    name : string;
    version : string;
  }

  val yojson_of_t : t -> Yojson.Safe.t
  val t_of_yojson : Yojson.Safe.t -> t

  val make : name:string -> version:string -> t
end

(** Initialize Protocol *)

module InitializeParams : sig
  type client_info = {
    name : string;
    version : string option;
  }

  type t = {
    protocolVersion : string;
    clientInfo : client_info;
    capabilities : Yojson.Safe.t option;
  }

  val t_of_yojson : Yojson.Safe.t -> t
end

module InitializeResult : sig
  type t = {
    protocolVersion : string;
    serverInfo : ServerInfo.t;
    capabilities : ServerCapabilities.t;
  }

  val yojson_of_t : t -> Yojson.Safe.t

  val make :
    protocolVersion:string ->
    serverInfo:ServerInfo.t ->
    capabilities:ServerCapabilities.t ->
    t
end

(** Tools Protocol *)

module ToolsListResult : sig
  type t = {
    tools : Tool.t list;
  }

  val yojson_of_t : t -> Yojson.Safe.t
  val make : Tool.t list -> t
end

module ToolsCallParams : sig
  type t = {
    name : string;
    arguments : Yojson.Safe.t option;
  }

  val t_of_yojson : Yojson.Safe.t -> t
end

module ToolsCallResult : sig
  type t = {
    content : Content.t list;
    isError : bool option;
  }

  val yojson_of_t : t -> Yojson.Safe.t

  val success : Content.t list -> t
  val error : string -> t
end

(** JSON-RPC *)

module Request : sig
  type t = {
    jsonrpc : string;
    id : Yojson.Safe.t;
    method_ : string;
    params : Yojson.Safe.t option;
  }

  val t_of_yojson : Yojson.Safe.t -> t
end

module Response : sig
  type error = {
    code : int;
    message : string;
    data : Yojson.Safe.t option;
  }

  type t = {
    jsonrpc : string;
    id : Yojson.Safe.t;
    result : Yojson.Safe.t option;
    error : error option;
  }

  val yojson_of_t : t -> Yojson.Safe.t

  val ok : Yojson.Safe.t -> Yojson.Safe.t -> t
  val err : Yojson.Safe.t -> int -> string -> t
end

module Notification : sig
  type t = {
    jsonrpc : string;
    method_ : string;
    params : Yojson.Safe.t option;
  }

  val t_of_yojson : Yojson.Safe.t -> t
end
