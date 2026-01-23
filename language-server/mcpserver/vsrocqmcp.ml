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

(** This executable implements an MCP-based server for interacting with
    Coq/Rocq proofs, designed for use with AI assistants and LLM tools. *)

let Dm.Types.Log log = Dm.Log.mk_log "mcptop"

(* TODO: share common parts with vsrocqtop *)
[%%if rocq = "9.0" || rocq = "9.1"]
let load_vos = Flags.load_vos_libraries
[%%else]
let load_vos = Loadpath.load_vos_libraries
[%%endif]

(* let load_vos = ref true *)

let () =
  Coqinit.init_ocaml ();
  log (fun () -> "------------------ MCP server begin ---------------");
  let cwd = Unix.getcwd () in
  let opts = McpArgs.Args.get_local_args cwd in
  let () = Coqinit.init_runtime ~usage:(McpArgs.Args.usage ()) opts in
  Safe_typing.allow_delayed_constants := true;
  load_vos := true;
  Sys.(set_signal sigint Signal_ignore);
  Mcpserver.McpManager.init ();
  Mcpserver.McpManager.main_loop ()
