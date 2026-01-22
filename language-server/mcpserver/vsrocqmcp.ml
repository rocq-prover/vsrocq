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

(* For Rocq 9.0/9.1, use Flags.load_vos_libraries *)
let load_vos = Flags.load_vos_libraries

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
