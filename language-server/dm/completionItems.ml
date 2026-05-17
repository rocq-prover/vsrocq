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

(* Pretty print of the builtin syntax item *)
let rec pp_builtin_syntax (syntax: builtin_syntax) : string =
  match syntax with
  | Literal { value; subscript } ->
      (match subscript with
      | Some sub -> Printf.sprintf "%s_%s" value sub
      | None -> value)
  | Reference { value; subscript } ->
      (match subscript with
      | Some sub -> Printf.sprintf "%s_%s" value sub
      | None -> value)
  | Alternative { children } ->
      String.concat "|" (List.map pp_builtin_syntax children)
  | Repeat { min; max; separator; children } ->
      let quant = match (min, max) with
        | (0, Some 1) -> "?"
        | (0, None) -> "*"
        | (1, None) -> "+"
        | (m, Some n) when m = n -> Printf.sprintf "{%d}" m
        | (m, Some n) -> Printf.sprintf "{%d,%d}" m n
        | (m, None) -> Printf.sprintf "{%d,}" m
      in
      let sep = Option.map (Printf.sprintf "[%s]") separator in
      let children_str = String.concat " " (List.map pp_builtin_syntax children) in
      Printf.sprintf "(%s)%s%s" children_str (Option.default "" sep) quant

(* folds over a list by gathering a list while keeping track of an accumulator *)
let fold_gather f acc items =
    let (final_acc, mapped) = List.fold_left (fun acc item ->
      let (next_acc, mapped) = f (fst acc) item in
      (next_acc, mapped :: snd acc)
    ) (acc, []) items in
    (final_acc, List.rev mapped)

(* Snippet syntax following https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#snippet_syntax *)
let rec builtin_syntax_to_snippet (tabstop: int) (syntax: builtin_syntax) : int * string =
  match syntax with
  | Literal { value; subscript } ->
      (tabstop, match subscript with
      | Some sub -> Printf.sprintf "%s_%s" value sub
      | None -> value)
  | Reference { value; subscript } ->
      let default = (match subscript with
      | Some sub -> Printf.sprintf "%s_${%s}" value sub
      | None -> value) in
      (tabstop + 1, Printf.sprintf "${%d:%s}" tabstop default)
  | Alternative { children } ->
      (* snippet syntax for alternatives is not recursive, so we just show the pretty print of the syntax *)
      (tabstop+1, Printf.sprintf "${%d|%s|}" tabstop (String.concat "," (List.map pp_builtin_syntax children)))
  | Repeat { min; max=_; separator; children } ->
      (* build `min` times carrying on the tabstop *)
      let (next_tabstop, child_snippets) = fold_gather (fun tabstop _ ->
        let (next_tabstop, snippets) = fold_gather builtin_syntax_to_snippet tabstop children in
        (next_tabstop, String.concat " " snippets)
      ) tabstop (List.init min Fun.id) in
      let repeat_snippet = String.concat (Option.default "" separator) child_snippets in
      (next_tabstop, repeat_snippet)

let builtin_syntax_list_to_snippet (syntax_list: builtin_syntax list) : string =
  let top = snd (fold_gather builtin_syntax_to_snippet 1 syntax_list) in
  (* we assume all grammars have an implicit "." at the end *)
  String.concat " " (List.filter (fun s -> s <> "") top) ^ "."

(* This is what is stored in the JSON index *)
type builtin_item_raw = {
  (* documentation file where this builtin is documented *)
  documentation_path: string;
  (* page anchor for this builtin in the documentation *)
  documentation_anchor: string;
  (* grammar *)
  syntax: builtin_syntax list;
  (* simplified documentation *)
  documentation: string;
} [@@deriving of_yojson]


(* We extend the raw item with additional computed fields *)
type builtin_item = {
  raw: builtin_item_raw;
  (* snippet syntax *)
  snippet: string;
  (* URL to the documentation page *)
  documentation_url: string;
}

[%%if rocq = "9.2"]
let doc_version = "V9.2.0"
[%%else]
let doc_version = ""
[%%endif]

let documentation_url_of_item (item: builtin_item_raw) : string =
  Printf.sprintf "https://rocq-prover.org/doc/%s/refman/%s.html#%s" doc_version item.documentation_path item.documentation_anchor

type builtin_index = (string * builtin_item) list

let load_builtin_index (json_str: string) : builtin_index =
  let json = Yojson.Safe.from_string json_str in
  let pairs = Yojson.Safe.Util.to_assoc json in
  List.map (fun (key, json_value) ->
    let raw = builtin_item_raw_of_yojson json_value in
    (key, {
      raw;
      snippet = builtin_syntax_list_to_snippet raw.syntax;
      documentation_url = documentation_url_of_item raw;
    })
  ) pairs


[%%if rocq = "9.2"]
let opt_index = load_builtin_index [%blob "indices/9.2/optindex.json"]
let cmd_index = load_builtin_index [%blob "indices/9.2/cmdindex.json"]
let tac_index = load_builtin_index [%blob "indices/9.2/tacindex.json"]
[%%else]
let opt_index = load_builtin_index "{}"
let cmd_index = load_builtin_index "{}"
let tac_index = load_builtin_index "{}"
[%%endif]
