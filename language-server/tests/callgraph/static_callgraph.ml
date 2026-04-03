
open Cmt_format
open Typedtree

module StringSet = Set.Make(String)
module StringMap = Map.Make(String)
module StringListSet = Set.Make(struct
  type t = string list
  let compare = Stdlib.compare
end)

type analysis = {
  root_library : string;
  graph : StringSet.t StringMap.t;
  local_nodes : StringSet.t;
  display_names : string StringMap.t;
  latest_bindings : string StringMap.t;
  ident_bindings : string Ident.tbl;
}

let empty_analysis = {
  root_library = "";
  graph = StringMap.empty;
  local_nodes = StringSet.empty;
  display_names = StringMap.empty;
  latest_bindings = StringMap.empty;
  ident_bindings = Ident.empty;
}

let add_edge graph source target =
  let targets =
    match StringMap.find_opt source graph with
    | Some targets -> targets
    | None -> StringSet.empty
  in
  StringMap.add source (StringSet.add target targets) graph

let add_graph_node graph node =
  if StringMap.mem node graph then graph else StringMap.add node StringSet.empty graph

let split_on_char char text =
  String.split_on_char char text

let join_with_dot parts =
  String.concat "." parts

let normalize_name name =
  let parts = split_on_char '.' name in
  let trim_prefix part =
    match split_on_char '_' part with
    | prefix1 :: prefix2 :: rest when prefix1 <> "" && prefix2 = "" -> String.concat "_" rest
    | _ -> part
  in
  parts |> List.map trim_prefix |> join_with_dot

let module_prefix_of_modname modname =
  match String.split_on_char '_' modname with
  | [single] -> [single]
  | library :: "" :: rest when rest <> [] -> [library; String.concat "_" rest]
  | _ -> [modname]

let namespaced_name prefix name =
  match prefix with
  | [] -> name
  | _ -> String.concat "." (prefix @ [name])

let local_node_id ident =
  "local:" ^ Ident.unique_name ident

let external_node_id display_name =
  "external:" ^ display_name

let ensure_display_name display_names node display_name =
  if StringMap.mem node display_names then display_names
  else StringMap.add node display_name display_names

let add_external_node analysis display_name =
  let node = external_node_id display_name in
  let graph = add_graph_node analysis.graph node in
  let display_names = ensure_display_name analysis.display_names node display_name in
  { analysis with graph; display_names }, node

let add_local_binding analysis prefix ident =
  let node = local_node_id ident in
  let display_name = namespaced_name prefix (Ident.name ident) in
  let graph = add_graph_node analysis.graph node in
  let local_nodes = StringSet.add node analysis.local_nodes in
  let display_names = ensure_display_name analysis.display_names node display_name in
  let latest_bindings = StringMap.add display_name node analysis.latest_bindings in
  let ident_bindings = Ident.add ident node analysis.ident_bindings in
  { root_library = analysis.root_library; graph; local_nodes; display_names; latest_bindings; ident_bindings }, node

let path_display_name path =
  normalize_name (Path.name path)

let binding_for_display_name analysis display_name =
  let has_prefix prefix name =
    let prefix_length = String.length prefix in
    String.length name >= prefix_length && String.sub name 0 prefix_length = prefix
  in
  match StringMap.find_opt display_name analysis.latest_bindings with
  | Some node -> Some node
  | None ->
    if analysis.root_library = "" || has_prefix (analysis.root_library ^ ".") display_name then None
    else StringMap.find_opt (analysis.root_library ^ "." ^ display_name) analysis.latest_bindings

let resolve_path analysis path =
  let display_name = path_display_name path in
  match Path.flatten path with
  | `Ok (head, []) ->
    begin match Ident.find_same head analysis.ident_bindings with
    | node -> analysis, node
    | exception Not_found ->
      begin match binding_for_display_name analysis display_name with
      | Some node -> analysis, node
      | None -> add_external_node analysis display_name
      end
    end
  | _ ->
    begin match binding_for_display_name analysis display_name with
    | Some node -> analysis, node
    | None -> add_external_node analysis display_name
    end

let resolve_path_for_source analysis source path =
  let unresolved_display_name = path_display_name path in
  match Path.flatten path with
  | `Ok (head, []) ->
    begin match Ident.find_same head analysis.ident_bindings with
    | node -> analysis, node
    | exception Not_found ->
      begin match binding_for_display_name analysis unresolved_display_name with
      | Some node -> analysis, node
      | None ->
        let source_display_name =
          match StringMap.find_opt source analysis.display_names with
          | Some source_display_name -> source_display_name
          | None -> source
        in
        let display_name = source_display_name ^ "." ^ unresolved_display_name in
        add_external_node analysis display_name
      end
    end
  | _ -> resolve_path analysis path

let callsite_node_id callee_target loc =
  let start = loc.Location.loc_start in
  let finish = loc.Location.loc_end in
  Printf.sprintf "callsite:%s:%d:%d:%d:%d"
    callee_target
    start.Lexing.pos_lnum
    (start.Lexing.pos_cnum - start.Lexing.pos_bol)
    finish.Lexing.pos_lnum
    (finish.Lexing.pos_cnum - finish.Lexing.pos_bol)

let add_callsite_node analysis callee_target loc =
  let node = callsite_node_id callee_target loc in
  let graph = add_graph_node analysis.graph node in
  let local_nodes = StringSet.add node analysis.local_nodes in
  let callee_display_name =
    match StringMap.find_opt callee_target analysis.display_names with
    | Some display_name -> display_name
    | None -> callee_target
  in
  let display_names = ensure_display_name analysis.display_names node callee_display_name in
  { analysis with graph; local_nodes; display_names }, node

let rec type_is_function ty =
  match Types.get_desc ty with
  | Types.Tarrow _ -> true
  | Types.Tlink ty -> type_is_function ty
  | Types.Tsubst (ty, _) -> type_is_function ty
  | Types.Tpoly (ty, _) -> type_is_function ty
  | _ -> false

let expression_is_function exp =
  type_is_function exp.exp_type

[%%if ocaml_version < (5, 0, 0)]
let function_argument_cases exp =
  match exp.exp_desc with
  | Texp_match (_, cases, _) -> Some cases
  | _ -> None
[%%else]
let function_argument_cases exp =
  match exp.exp_desc with
  | Texp_match (_, cases, _, _) -> Some cases
  | _ -> None
[%%endif]

[%%if ocaml_version < (5, 0, 0)]
let iter_apply_arguments args handle_argument =
  List.iter
    (fun (_, argument) ->
      match argument with
      | None -> ()
      | Some argument -> handle_argument argument)
    args
[%%else]
let iter_apply_arguments args handle_argument =
  List.iter
    (fun (_, argument) ->
      match argument with
      | Omitted () -> ()
      | Arg argument -> handle_argument argument)
    args
[%%endif]

let rec iter_function_calls analysis source expression =
  let analysis_ref = ref analysis in
  let record_call current_source path =
    let analysis, target = resolve_path_for_source !analysis_ref current_source path in
    let graph = add_edge analysis.graph current_source target in
    analysis_ref := { analysis with graph };
    target
  in
  let callback_source callee_target loc =
    let analysis, callsite_node = add_callsite_node !analysis_ref callee_target loc in
    let graph = add_edge analysis.graph source callsite_node in
    analysis_ref := { analysis with graph };
    callsite_node
  in
  let rec record_function_argument_call current_source exp =
    match exp.exp_desc with
    | Texp_ident (path, _, _) ->
      ignore (record_call current_source path)
    | Texp_let (_, _, body)
    | Texp_sequence (_, body) ->
      record_function_argument_call current_source body
    | Texp_ifthenelse (_, then_exp, else_exp) ->
      record_function_argument_call current_source then_exp;
      Option.iter (record_function_argument_call current_source) else_exp
    | Texp_function _
    | Texp_apply _ ->
      ()
    | _ ->
      begin match function_argument_cases exp with
      | Some cases -> List.iter (fun case -> record_function_argument_call current_source case.c_rhs) cases
      | None -> ()
      end
  in
  let iterator =
    { Tast_iterator.default_iterator with
      expr = (fun self exp ->
        begin
          match exp.exp_desc with
          | Texp_apply (callee, args) ->
            let callee_target =
              match callee.exp_desc with
              | Texp_ident (path, _, _) -> Some (record_call source path)
              | _ ->
                self.expr self callee;
                None
            in
            iter_apply_arguments args (fun argument ->
              if expression_is_function argument then begin
                let thunk_source =
                  match callee_target with
                  | Some callee_target -> callback_source callee_target exp.exp_loc
                  | None -> source
                in
                record_function_argument_call thunk_source argument;
                analysis_ref := iter_function_calls !analysis_ref thunk_source argument
              end else
                self.expr self argument)
          | _ -> ()
        end;
        match exp.exp_desc with
        | Texp_apply _ -> ()
        | _ -> Tast_iterator.default_iterator.expr self exp)
    }
  in
  iterator.expr iterator expression;
  !analysis_ref

let module_name module_binding =
  match module_binding.mb_name.txt with
  | Some name -> Some name
  | None -> Option.map Ident.name module_binding.mb_id

let bound_idents pattern =
  Typedtree.pat_bound_idents pattern

[%%if ocaml_version < (5, 0, 0)]
let collect_module_expr_desc collect_structure collect_module_expr prefix analysis = function
  | Tmod_structure structure -> collect_structure prefix analysis structure
  | Tmod_functor (_, body) -> collect_module_expr prefix analysis body
  | Tmod_apply (module_expr, argument, _) ->
    let analysis = collect_module_expr prefix analysis module_expr in
    collect_module_expr prefix analysis argument
  | Tmod_constraint (module_expr, _, _, _) -> collect_module_expr prefix analysis module_expr
  | Tmod_unpack (_, _) -> analysis
  | Tmod_ident _ -> analysis
[%%else]
let collect_module_expr_desc collect_structure collect_module_expr prefix analysis = function
  | Tmod_structure structure -> collect_structure prefix analysis structure
  | Tmod_functor (_, body) -> collect_module_expr prefix analysis body
  | Tmod_apply (module_expr, argument, _) ->
    let analysis = collect_module_expr prefix analysis module_expr in
    collect_module_expr prefix analysis argument
  | Tmod_apply_unit module_expr -> collect_module_expr prefix analysis module_expr
  | Tmod_constraint (module_expr, _, _, _) -> collect_module_expr prefix analysis module_expr
  | Tmod_unpack (_, _) -> analysis
  | Tmod_ident _ -> analysis
[%%endif]

let rec collect_structure prefix analysis structure =
  List.fold_left (collect_structure_item prefix) analysis structure.str_items

and collect_structure_item prefix analysis item =
  match item.str_desc with
  | Tstr_value (_, bindings) ->
    List.fold_left (collect_value_binding prefix) analysis bindings
  | Tstr_module module_binding ->
    begin match module_name module_binding with
    | Some name -> collect_module_expr (prefix @ [name]) analysis module_binding.mb_expr
    | None -> analysis
    end
  | Tstr_recmodule module_bindings ->
    List.fold_left
      (fun analysis module_binding ->
        match module_name module_binding with
        | Some name -> collect_module_expr (prefix @ [name]) analysis module_binding.mb_expr
        | None -> analysis)
      analysis module_bindings
  | _ -> analysis

and collect_value_binding prefix analysis binding =
  let idents = bound_idents binding.vb_pat in
  match idents with
  | [] -> analysis
  | _ ->
    let analysis, sources =
      List.fold_left
        (fun (analysis, sources) ident ->
          let analysis, source = add_local_binding analysis prefix ident in
          analysis, source :: sources)
        (analysis, []) idents
    in
    List.fold_left (fun analysis source -> iter_function_calls analysis source binding.vb_expr) analysis sources

and collect_module_expr prefix analysis module_expr =
  collect_module_expr_desc collect_structure collect_module_expr prefix analysis module_expr.mod_desc

let maybe_read_cmt file_path =
  try Some (read_cmt file_path) with
  | Error _ -> None

let cmt_files_in_directory directory =
  Sys.readdir directory
  |> Array.to_list
  |> List.filter (fun file_name -> Filename.check_suffix file_name ".cmt")
  |> List.map (Filename.concat directory)
  |> List.sort String.compare

let load_workspace_graph input_cmt_path =
  let directory = Filename.dirname input_cmt_path in
  let root_cmt = read_cmt input_cmt_path in
  let root_prefix = module_prefix_of_modname root_cmt.cmt_modname in
  let root_library = List.hd root_prefix in
  let initial_analysis = { empty_analysis with root_library } in
  let collect_file analysis file_path =
    match maybe_read_cmt file_path with
    | None -> analysis
    | Some cmt ->
      begin match cmt.cmt_annots with
      | Implementation structure ->
        let prefix = module_prefix_of_modname cmt.cmt_modname in
        if List.hd prefix <> root_library then analysis
        else collect_structure prefix analysis structure
      | _ -> analysis
      end
  in
  let analysis = List.fold_left collect_file initial_analysis (cmt_files_in_directory directory) in
  root_prefix, analysis

let is_prefix prefix name =
  let prefix_length = String.length prefix in
  String.length name >= prefix_length && String.sub name 0 prefix_length = prefix

let starts_with_parts prefix parts =
  let rec loop prefix parts =
    match prefix, parts with
    | [], _ -> true
    | _, [] -> false
    | prefix_head :: prefix_tail, part_head :: part_tail ->
      prefix_head = part_head && loop prefix_tail part_tail
  in
  loop prefix parts

let display_name analysis node =
  match StringMap.find_opt node analysis.display_names with
  | Some display_name -> display_name
  | None -> node

let roots_for_prefix root_prefix analysis =
  StringSet.filter
    (fun node ->
      starts_with_parts root_prefix (split_on_char '.' (display_name analysis node)))
    analysis.local_nodes

let is_filtered_target analysis target =
  is_prefix "Stdlib" (display_name analysis target)

let rec collect_chains analysis visited path source chains =
  let callees =
    match StringMap.find_opt source analysis.graph with
    | Some callees -> callees
    | None -> StringSet.empty
  in
  StringSet.fold
    (fun callee chains ->
      let callee =
        if StringSet.mem callee analysis.local_nodes then callee
        else
          match binding_for_display_name analysis (display_name analysis callee) with
          | Some local_callee -> local_callee
          | None -> callee
      in
      let next_path = path @ [callee] in
      if StringSet.mem callee analysis.local_nodes then
        if StringSet.mem callee visited then chains
        else collect_chains analysis (StringSet.add callee visited) next_path callee chains
      else if is_filtered_target analysis callee then chains
      else StringListSet.add next_path chains)
    callees chains

let call_chains roots analysis =
  StringSet.fold
    (fun source chains ->
      collect_chains analysis (StringSet.singleton source) [source] source chains)
    roots StringListSet.empty

let read_lines file_path =
  let channel = open_in file_path in
  Fun.protect
    ~finally:(fun () -> close_in channel)
    (fun () ->
      let rec loop lines =
        match input_line channel with
        | line -> loop (line :: lines)
        | exception End_of_file -> List.rev lines
      in
      loop [])

let sanitize_pattern_line line =
  let line =
    match String.index_opt line '#' with
    | Some comment_start -> String.sub line 0 comment_start
    | None -> line
  in
  String.trim line

let compile_component_regexp pattern =
  Str.regexp ("^" ^ pattern)

let load_regexps file_path =
  read_lines file_path
  |> List.map sanitize_pattern_line
  |> List.filter (fun line -> line <> "")
  |> List.map compile_component_regexp

let load_whitelist file_path =
  read_lines file_path
  |> List.map sanitize_pattern_line
  |> List.filter (fun line -> line <> "")
  |> List.map (fun line ->
       line
       |> Str.split (Str.regexp_string " -> ")
       |> List.map String.trim
       |> List.map compile_component_regexp)

let load_safe_barriers = load_regexps

let strip_root_prefix root_prefix display_name =
  let root = join_with_dot root_prefix in
  let root_with_dot = root ^ "." in
  if is_prefix root_with_dot display_name then
    String.sub display_name (String.length root_with_dot) (String.length display_name - String.length root_with_dot)
  else display_name

let compress_display_chain chain =
  let rec loop acc remaining =
    match remaining with
    | callee :: host :: repeated :: tail when callee = repeated ->
      loop ("[thunk]" :: host :: callee :: acc) tail
    | head :: tail -> loop (head :: acc) tail
    | [] -> List.rev acc
  in
  loop [] chain

let display_chain analysis root_prefix chain =
  chain
  |> List.map (fun node -> strip_root_prefix root_prefix (display_name analysis node))
  |> compress_display_chain

let matches_regexp regexp entry =
  Str.string_match regexp entry 0

let whitelist_matches_chain_suffix whitelist rendered_chain =
  List.exists
    (fun pattern ->
      let pattern_length = List.length pattern in
      let chain_length = List.length rendered_chain in
      if pattern_length > chain_length then false
      else
        let rec drop count items =
          if count <= 0 then items
          else
            match items with
            | [] -> []
            | _ :: tail -> drop (count - 1) tail
        in
        let suffix = drop (chain_length - pattern_length) rendered_chain in
        List.for_all2 matches_regexp pattern suffix)
    whitelist

let string_ends_with ~suffix text =
  let suffix_length = String.length suffix in
  let text_length = String.length text in
  text_length >= suffix_length
  && String.sub text (text_length - suffix_length) suffix_length = suffix

let safe_barrier_index safe_barriers rendered_chain =
  let rec loop index = function
    | [] -> None
    | entry :: tail ->
      if List.exists (fun regexp -> matches_regexp regexp entry) safe_barriers then Some index
      else loop (index + 1) tail
  in
  loop 0 rendered_chain

let truncate_at_safe_barrier safe_barriers rendered_chain =
  match safe_barrier_index safe_barriers rendered_chain with
  | None -> rendered_chain
  | Some barrier_index ->
    let keep_until_index =
      if List.length rendered_chain > barrier_index + 1 && List.nth rendered_chain (barrier_index + 1) = "[thunk]" then
        barrier_index + 1
      else barrier_index
    in
    let prefix, _suffix = List.fold_left
        (fun (prefix, index) entry ->
          if index <= keep_until_index then (entry :: prefix, index + 1)
          else (prefix, index + 1))
        ([], 0) rendered_chain
    in
    List.rev ("*" :: prefix)

let write_report whitelist safe_barriers analysis root_prefix channel chains =
  let rendered_lines = ref StringSet.empty in
  StringListSet.iter
    (fun chain ->
      let rendered_chain =
        chain
        |> display_chain analysis root_prefix
        |> truncate_at_safe_barrier safe_barriers
      in
      if whitelist_matches_chain_suffix whitelist rendered_chain then ()
      else
        let rendered_line = String.concat " -> " rendered_chain in
        rendered_lines := StringSet.add rendered_line !rendered_lines)
    chains;
  let rendered_lines =
    StringSet.filter
      (fun rendered_line ->
        if string_ends_with ~suffix:" -> [thunk] -> *" rendered_line then true
        else if string_ends_with ~suffix:" -> *" rendered_line then
          let prefix_length = String.length rendered_line - String.length " -> *" in
          let prefix = String.sub rendered_line 0 prefix_length in
          not (StringSet.mem (prefix ^ " -> [thunk] -> *") !rendered_lines)
        else true)
      !rendered_lines
  in
  StringSet.iter
    (fun rendered_line ->
      output_string channel rendered_line;
      output_char channel '\n')
    rendered_lines

let usage () =
  prerr_endline "usage: static_callgraph [--whitelist path/to/file] [--safe-barriers path/to/file] path/to/file.cmt";
  exit 2

let () =
  let rec parse_args whitelist_file safe_barriers_file = function
    | [input_cmt_path] -> whitelist_file, safe_barriers_file, input_cmt_path
    | "--whitelist" :: whitelist_path :: tail ->
      parse_args (Some whitelist_path) safe_barriers_file tail
    | "--safe-barriers" :: safe_barriers_path :: tail ->
      parse_args whitelist_file (Some safe_barriers_path) tail
    | _ -> usage ()
  in
  let whitelist_file, safe_barriers_file, input_cmt_path =
    match Array.to_list Sys.argv with
    | _program :: args -> parse_args None None args
    | [] -> usage ()
  in
  let whitelist =
    match whitelist_file with
    | Some whitelist_file -> load_whitelist whitelist_file
    | None -> []
  in
  let safe_barriers =
    match safe_barriers_file with
    | Some safe_barriers_file -> load_safe_barriers safe_barriers_file
    | None -> []
  in
  let root_prefix, analysis = load_workspace_graph input_cmt_path in
  let roots = roots_for_prefix root_prefix analysis in
  let chains = call_chains roots analysis in
  write_report whitelist safe_barriers analysis root_prefix stdout chains
