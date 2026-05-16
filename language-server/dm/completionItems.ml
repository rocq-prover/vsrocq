open Constr
open Libnames
open Nametab
open Printer

open Ppx_yojson_conv_lib.Yojson_conv.Primitives

type completion_level =
  Fully
  | Partially
  | No_completion

let symbol_prefix (completes: completion_level option) =
  match completes with
  | None -> ""
  | Some level -> match level with
    | Fully -> "★ "
    | Partially -> "☆ "
    | No_completion -> ""

type completion_item = {
  ref : Names.GlobRef.t;
  path : full_path;
  typ : types;
  env : Environ.env;
  sigma : Evd.evar_map;
  completes : completion_level option;
  mutable debug_info : string;
}

let mk_completion_item sigma ref env (c : constr) : completion_item =
  {
    ref = ref;
    path = path_of_global ref;
    typ = c;
    env = env;
    sigma = sigma;
    completes = None;
    debug_info = "";
  }

let pp_completion_item (item : completion_item) : (string * string * string * string) =
  let pr = pr_global item.ref in
  let name = Pp.string_of_ppcmds pr in
  let path = string_of_path item.path ^ "\n" ^ item.debug_info in
  let typ = Pp.string_of_ppcmds (pr_ltype_env item.env item.sigma item.typ) in
  (Printf.sprintf "%s%s" (symbol_prefix item.completes) name, name, typ, path)

(** Builtin commands, options, and tactics *)

(*
  Some vernacular is implemented internally in Rocq and not visible as a normal definition
  that could be added to a completion database through standard scraping. Same goes for
  Ltac1 tactics.

  To remedy this, we scrape the official documentation of Rocq and create indices of all
  of the built-in tactics, commands, and options. These indices are then loaded into
  vsrocqtop to serve these completions to the user.
*)

(* The grammar of the builtin item as defined in the official grammar *)
type builtin_syntax =
  | Literal of {
      value: string;
      subscript: string option;
    }
  | Reference of {
      value: string;
      subscript: string option;
    }
  | Alternative of {
      children: builtin_syntax list;
    }
  | Repeat of {
      min: int;
      max: int option;
      separator: string option;
      children: builtin_syntax list;
    }
[@@deriving of_yojson]

type builtin_item = {
  (* documentation file where this builtin is documented *)
  documentation_path: string;
  (* page anchor for this builtin in the documentation *)
  documentation_anchor: string;
  (* grammar *)
  syntax: builtin_syntax list;
  (* simplified documentation *)
  documentation: string;
} [@@deriving of_yojson]

type builtin_index = (string, builtin_item) Hashtbl.t

let load_builtin_index (json_str: string) : builtin_index =
  let json = Yojson.Safe.from_string json_str in
  let pairs = Yojson.Safe.Util.to_assoc json in
  let tbl = Hashtbl.create (List.length pairs) in
  List.iter (fun (key, json_value) ->
    Hashtbl.add tbl key (builtin_item_of_yojson json_value)
  ) pairs;
  tbl

[%%if rocq = "9.2"]
let opt_index = load_builtin_index [%blob "indices/9.2/optindex.json"]
let cmd_index = load_builtin_index [%blob "indices/9.2/cmdindex.json"]
let tac_index = load_builtin_index [%blob "indices/9.2/tacindex.json"]
[%%else]
let opt_index = load_builtin_index "{}"
let cmd_index = load_builtin_index "{}"
let tac_index = load_builtin_index "{}"
[%%endif]
