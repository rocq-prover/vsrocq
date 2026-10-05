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
(*                                                                        *)
(**************************************************************************)

open Ppx_yojson_conv_lib.Yojson_conv.Primitives
open Types

let Log log = Log.mk_log "duneInteraction"

(** A Dune dependency. Only the optional [File] entry matters for validating
    that a copy action reads the source file it reports. *)
type dependency = {
  file : (string * string) option [@yojson.key "File"];
} [@@deriving of_yojson] [@@yojson.allow_extra_fields]

(** A Dune action relevant to definition lookup. Actions other than a direct
    copy cannot establish a source-file mapping. *)
type action =
  | Copy of {source : string; target : string}
  | Other

let action_of_yojson = function
  | `List [`String "copy"; `String source; `String target] -> Copy {source; target}
  | _ -> Other

(** The part of a Dune rule used to map a build artifact back to a source
    file. Its decoder consumes the original Dune JSON rule directly. *)
type rule = {
  action : action;
  deps : dependency list;
} [@@deriving of_yojson] [@@yojson.allow_extra_fields]

(** Return the source copied to [file] when Dune returned one copy rule. *)
let source_of_rules ~file = function
  | `List [rule] ->
    begin try match rule_of_yojson rule with
    | {action = Copy {source; target}; deps} when String.equal file target ->
      let is_source_dependency {file} =
        match file with
        | Some ("In_source_tree", dependency) -> String.equal source dependency
        | _ -> false
      in
      if List.exists is_source_dependency deps then Some source else None
    | _ -> None
    with Ppx_yojson_conv_lib.Yojson_conv.Of_yojson_error _ -> None
    end
  | _ -> None

let path_relative_to_cwd file =
  if Filename.is_relative file then Some file else
  let cwd = Unix.getcwd () in
  let prefix = if cwd = Filename.dir_sep then cwd else cwd ^ Filename.dir_sep in
  let length = String.length prefix in
  if String.length file >= length && String.sub file 0 length = prefix
  then Some (String.sub file length (String.length file - length))
  else None

let path_to_absolute file =
  if Filename.is_relative file then Filename.concat (Unix.getcwd ()) file else file

(* Dune rules do not change while this language-server process is running. *)
let sources : (string, string option) Hashtbl.t = Hashtbl.create 7

(** Resolve Dune beside an absolute [vsrocqtop] executable, otherwise use the
    inherited [PATH] *)
let resolve_command () =
  let environment = Unix.environment () in
  if Filename.is_relative Sys.executable_name then
    "dune", environment
  else
  let directory = Filename.dirname Sys.executable_name in
  let dune = Filename.concat directory "dune" in
  if Sys.file_exists dune then begin
    let path =
      match Sys.getenv_opt "PATH" with
      | Some path when path <> "" -> directory ^ ":" ^ path
      | _ -> directory
    in
    let found_path = ref false in
    let environment =
      Array.map (fun variable ->
        if String.starts_with ~prefix:"PATH=" variable then begin
          found_path := true;
          "PATH=" ^ path
        end else
          variable)
        environment
    in
    let environment =
      if !found_path then environment else Array.append environment [| "PATH=" ^ path |]
    in
    dune, environment
  end else
    "dune", environment

(** Query Dune for the source copied to [file] *)
let source_of_file file =
  try
    let dune, environment = resolve_command () in
    let stdout_read, stdout_write = Unix.pipe () in
    let stderr = Unix.openfile Filename.null [Unix.O_WRONLY] 0 in
    let process =
      try Unix.create_process_env dune
        [| dune; "rules"; "--display=quiet"; "--format=json"; file |]
        environment Unix.stdin stdout_write stderr
      with error ->
        Unix.close stdout_read;
        Unix.close stdout_write;
        Unix.close stderr;
        raise error
    in
    Unix.close stdout_write;
    Unix.close stderr;
    let stdout = Unix.in_channel_of_descr stdout_read in
    let rules =
      Fun.protect ~finally:(fun () -> close_in_noerr stdout) (fun () ->
        try Some (Yojson.Safe.from_channel stdout) with
        | error ->
          log (fun () -> "Cannot decode Dune rules: " ^ Printexc.to_string error);
          None)
    in
    begin match snd (Unix.waitpid [] process), rules with
    | Unix.WEXITED 0, Some rules -> source_of_rules ~file rules
    | status, _ ->
      log (fun () -> "Dune rules failed for " ^ file ^ ": " ^
        match status with
        | Unix.WEXITED code -> "exit " ^ string_of_int code
        | Unix.WSIGNALED signal -> "signal " ^ string_of_int signal
        | Unix.WSTOPPED signal -> "stopped by signal " ^ string_of_int signal);
      None
    end
  with
  | Unix.Unix_error (error, function_name, argument) ->
    log (fun () -> "Cannot run Dune " ^ function_name ^ "(" ^ argument ^ "): " ^
      Unix.error_message error);
    None
  | Sys_error message ->
    log (fun () -> "Cannot read Dune rules: " ^ message);
    None

(** Return the source file Dune copied to [file], or [file] when Dune cannot
    provide a verified source mapping. *)
let prefer_source file =
  match Hashtbl.find_opt sources file with
  | Some (Some source) -> source
  | Some None -> file
  | None ->
    let source =
      match path_relative_to_cwd file with
      | None -> None
      | Some relative_file ->
        match source_of_file relative_file with
        | Some source ->
          let source = path_to_absolute source in
          if Sys.file_exists source then Some source else None
        | None -> None
    in
    Hashtbl.replace sources file source;
    Option.value ~default:file source

(** Parser details exposed only for focused unit tests. *)
module Internal = struct
  let source_of_rules = source_of_rules
end
