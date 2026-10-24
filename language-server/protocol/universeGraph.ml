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

open Lsp.Types

open Ppx_yojson_conv_lib.Yojson_conv.Primitives

(* The universes and constraints shown by [Show Universes] and
   [Print Universes], for the universe graph view of the client. *)

type level = {
  id : string; (* the raw name of the level, unique in a graph *)
  name : string; (* the level as Rocq prints it *)
  flexible : bool; (* a unification variable *)
  algebraic : bool; (* can be instantiated with an algebraic universe *)
  range : Range.t option; [@yojson.option] (* where it was introduced *)
} [@@deriving yojson]

type univ_constraint = {
  source : string;
  kind : string; (* "<", "<=" or "=" *)
  target : string;
} [@@deriving yojson]

type graph = {
  levels : level list;
  constraints : univ_constraint list;
} [@@deriving yojson]

type elimination = {
  from_quality : string;
  to_quality : string;
} [@@deriving yojson]

type quality_graph = {
  qualities : string list;
  eliminations : elimination list;
} [@@deriving yojson]

type t = {
  graph : graph;
  normalized : graph option; [@yojson.option] (* after minimization, for a proof *)
  qualities : quality_graph option; [@yojson.option] (* the sort elimination graph *)
} [@@deriving yojson]
