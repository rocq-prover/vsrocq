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

open Types
let lsp_initialization_done = ref false
let initialization_feedback_queue = Queue.create ()

let init_log =
  try Some (
    let oc = open_out @@ Filename.temp_file "vsrocq_init_log." ".txt" in
    output_string oc "command line:\n";
    output_string oc (String.concat " " (Sys.argv |> Array.to_list));
    output_string oc "\nstatic initialization:\n";
    oc)
  with _ -> None

let write_to_init_log str =
  Option.iter (fun oc ->
      output_string oc str;
      output_char oc '\n';
      flush oc)
    init_log

let rec is_enabled name = function
  | [] -> false
  | "-vsrocq-d" :: "all" :: _ -> true
  | "-vsrocq-d" :: v :: rest ->
    List.mem name (String.split_on_char ',' v) || is_enabled name rest
  | _ :: rest -> is_enabled name rest

let logs = ref []

let handle_event s = Printf.eprintf "%s\n" s

let mk_log name =
  logs := name :: !logs;
  let flag = is_enabled name (Array.to_list Sys.argv) in
  let flag_init = is_enabled "init" (Array.to_list Sys.argv) in
  write_to_init_log ("log fun () -> " ^ name ^ " is " ^ if flag then "on" else "off");
  Log (fun ?(force=false) msg ->
    let msg =
      try msg ()
      with
      | Sys.Break as e ->
        (* we let this escape since one may want to interrupt the printer *)
        let e = Exninfo.capture e in
        Exninfo.iraise e
      | e ->
        let e = Exninfo.capture e in
        let message = Pp.string_of_ppcmds @@ CErrors.iprint e in
        Format.asprintf "Error while printing: %s" message in
    let should_print_log = force || flag || (flag_init && not !lsp_initialization_done) in
    if should_print_log then begin
      let txt = Format.asprintf "[%-20s, %d, %f] %s" name (Unix.getpid ()) (Unix.gettimeofday ()) msg in
      if not !lsp_initialization_done then begin
        write_to_init_log txt;
        Queue.push txt initialization_feedback_queue (* Emission must be delayed as per LSP spec *)
      end else
        handle_event txt
    end else
      ())

let logs () = List.sort String.compare !logs
