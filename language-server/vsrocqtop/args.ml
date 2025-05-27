(**************************************************************************)
(*                                                                        *)
(*                                 VsRocq                                 *)
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

let Host_common.Types.Log log = Host_common.Log.mk_log "args"

let rec skip_xd acc = function
| [] -> (), List.rev acc
| "-vsrocq-d" :: _ :: rest -> skip_xd acc rest
| x :: rest -> skip_xd (x::acc) rest

let vsrocqtop_specific_usage () = {
  Boot.Usage.executable_name = "vsrocqtop";
  extra_args = "";
  extra_options = {|
VSRocq options are:
  -vsrocq-d c1,..,cn      enable debugging for vsrocq components c1 ... cn.
                         Known components:
                           all (shorthand for all components)
                           init (all components but only during initialization)
|} ^ "\t\t\t   " ^ String.concat "\n\t\t\t   " (Host_common.Log.logs ()) ^ {|
  
|}
}

let usage () = vsrocqtop_specific_usage ()

[%%if  rocq = "8.18" || rocq = "8.19" || rocq = "8.20"]

  let parse_extra x =
    skip_xd [] x  

  let parse_args_default () =
    let initial_args = Coqargs.default in
    let usage = vsrocqtop_specific_usage () in
    fst @@ Coqinit.parse_arguments ~usage ~initial_args ~parse_extra ()

  let parse_args_with_rocq_project args =
    let usage = vsrocqtop_specific_usage () in
    let initial_args = fst @@ Coqargs.parse_args ~init:Coqargs.default ~usage args in
    fst @@ Coqinit.parse_arguments ~usage ~initial_args ~parse_extra ()

[%%else]

let parse_extra _ x =
  skip_xd [] x

  let parse_args_default () =
    let initial_args = Coqargs.default in
    fst @@ Coqinit.parse_arguments ~initial_args ~parse_extra (List.tl (Array.to_list Sys.argv))
  
  let parse_args_with_rocq_project args =
    let initial_args = fst @@ Coqargs.parse_args ~init:Coqargs.default args in
    fst @@ Coqinit.parse_arguments ~initial_args ~parse_extra (List.tl (Array.to_list Sys.argv))
[%%endif]

let get_local_args dir =
  match CoqProject_file.find_project_file ~from:dir ~projfile_name:"_CoqProject" with
  | None ->
    log (fun () -> Printf.sprintf "No project file found for %s" dir);
    parse_args_default ()
  | Some f ->
    let project = CoqProject_file.read_project_file ~warning_fn:(fun _ -> ()) f in
    let args = CoqProject_file.coqtop_args_from_project project in
    log (fun () -> Printf.sprintf "Arguments from project file %s: %s" f (String.concat " " args));
    parse_args_with_rocq_project args