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

(** VSRocq-specific MCP tool definitions.
    This module defines the tools exposed by the VSRocq MCP server
    for interacting with Rocq proofs. *)

open Ppx_yojson_conv_lib.Yojson_conv.Primitives

module Args = struct
  (** Tool argument types - what the handlers receive *)

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

module Schema = struct
  (** Tool schemas - JSON Schema definitions for tool inputs *)

  open McpBase_lib.McpBase
  open JsonSchema

  let uri_prop = property ~type_:"string" ~description:"The URI/path of the document"

  let open_document = JsonSchema.make
    ~properties:[
      ("uri", uri_prop);
      ("text", property ~type_:"string"
        ~description:"The full text content of the document (optional - will be read from file if not provided)");
    ]
    ~required:["uri"]

  let close_document = JsonSchema.make
    ~properties:[("uri", property ~type_:"string" ~description:"The URI of the document to close")]
    ~required:["uri"]

  let interpret_to_point = JsonSchema.make
    ~properties:[
      ("uri", uri_prop);
      ("line", property ~type_:"integer" ~description:"The 0-indexed line number");
      ("character", property ~type_:"integer" ~description:"The 0-indexed character position");
    ]
    ~required:["uri"; "line"; "character"]

  let uri_only = JsonSchema.make
    ~properties:[("uri", uri_prop)]
    ~required:["uri"]

  let apply_edit = JsonSchema.make
    ~properties:[
      ("uri", uri_prop);
      ("startLine", property ~type_:"integer" ~description:"Start line of the range to replace (0-indexed)");
      ("startCharacter", property ~type_:"integer" ~description:"Start character of the range (0-indexed)");
      ("endLine", property ~type_:"integer" ~description:"End line of the range (0-indexed)");
      ("endCharacter", property ~type_:"integer" ~description:"End character of the range (0-indexed)");
      ("newText", property ~type_:"string" ~description:"The new text to insert");
    ]
    ~required:["uri"; "startLine"; "startCharacter"; "endLine"; "endCharacter"; "newText"]
end

module Definitions = struct
  (** Tool definitions - metadata and schemas for MCP *)

  open McpBase_lib.McpBase

  let open_document = Tool.make
    ~name:"open_document"
    ~description:"Open a Coq/Rocq document for proving. Must be called before any other operations on a document."
    ~inputSchema:Schema.open_document

  let close_document = Tool.make
    ~name:"close_document"
    ~description:"Close a previously opened document, freeing associated resources."
    ~inputSchema:Schema.close_document

  let interpret_to_point = Tool.make
    ~name:"interpret_to_point"
    ~description:"Execute the Coq/Rocq document up to a specific position. Returns the proof state at that position."
    ~inputSchema:Schema.interpret_to_point

  let interpret_to_end = Tool.make
    ~name:"interpret_to_end"
    ~description:"Execute the entire Coq/Rocq document to the end. Returns the final proof state."
    ~inputSchema:Schema.uri_only

  let step_forward = Tool.make
    ~name:"step_forward"
    ~description:"Execute the next sentence/command in the Coq/Rocq document. Returns the resulting proof state."
    ~inputSchema:Schema.uri_only

  let step_backward = Tool.make
    ~name:"step_backward"
    ~description:"Undo the last executed sentence/command, moving back one step. Returns the resulting proof state."
    ~inputSchema:Schema.uri_only

  let get_proof_state = Tool.make
    ~name:"get_proof_state"
    ~description:"Get the current proof state without executing any commands. Returns goals, hypotheses, and messages."
    ~inputSchema:Schema.uri_only

  let apply_edit = Tool.make
    ~name:"apply_edit"
    ~description:"Apply a text edit to the document. The edit replaces text in the specified range with new text."
    ~inputSchema:Schema.apply_edit

  let all : McpBase_lib.McpBase.Tool.t list = [
    open_document;
    close_document;
    interpret_to_point;
    interpret_to_end;
    step_forward;
    step_backward;
    get_proof_state;
    apply_edit;
  ]
end
