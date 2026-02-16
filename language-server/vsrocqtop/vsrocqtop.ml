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

(** This toplevel implements an LSP-based server language for VsCode, used by
      the VsRocq extension.

    When started with -mcp flag, it runs an MCP server instead. *)

let Dm.Types.Log log = Dm.Log.mk_log "top"

let lsp_loop () =
  let events = LspManager.init () in
  let rec loop (todo : LspManager.event Sel.Todo.t) =
    (*log fun () -> "looking for next step";*)
    flush_all ();
    let ready, todo = Sel.pop todo in
    let nremaining = Sel.Todo.size todo in
    log (fun () -> Format.asprintf "Main loop event ready: %a, %d events waiting\n\n" LspManager.pr_event ready nremaining);
    log (fun () -> "==========================================================");
    log (fun () -> Format.asprintf "Todo events: %a" (Sel.Todo.pp LspManager.pr_event) todo );
    log (fun () -> "==========================================================\n\n");
    let new_events = LspManager.handle_event ready in
    let todo = Sel.Todo.add todo new_events in
    log (fun () -> "==========================================================");
    log (fun () -> Format.asprintf "New Todo events: %a" (Sel.Todo.pp LspManager.pr_event) todo );
    log (fun () -> "==========================================================\n\n");
    loop todo
  in
  let todo = Sel.Todo.add Sel.Todo.empty events in
  try loop todo
  with exn ->
    let info = Exninfo.capture exn in
    log ~force:true (fun () -> "==========================================================");
    log ~force:true (fun () -> Pp.string_of_ppcmds @@ CErrors.iprint_no_report info);
    log ~force:true (fun () -> "==========================================================")

let mcp_loop () =
  Mcpserver.McpManager.init ();
  Mcpserver.McpManager.main_loop ()

let main_loop () =
  if !(Args.mcp_mode) then mcp_loop ()
  else lsp_loop ()

[%%if rocq = "8.18" || rocq = "8.19" || rocq = "8.20"]
let _ =
  Coqinit.init_ocaml ();
  log (fun () -> "------------------ begin ---------------");
  let cwd = Unix.getcwd () in
  let opts = Args.get_local_args  cwd in
  let _injections = Coqinit.init_runtime opts in
  Safe_typing.allow_delayed_constants := true; (* Needed to delegate or skip proofs *)
  Flags.load_vos_libraries := true;
  Sys.(set_signal sigint Signal_ignore);
  main_loop ()
[%%else]

[%%if rocq = "9.0" || rocq = "9.1"]
let load_vos = Flags.load_vos_libraries
[%%else]
let load_vos = Loadpath.load_vos_libraries
[%%endif]

let () =
  Coqinit.init_ocaml ();
  log (fun () -> "------------------ begin ---------------");
  let cwd = Unix.getcwd () in
  let opts = Args.get_local_args cwd in
  let () = Coqinit.init_runtime ~usage:(Args.usage ()) opts in
  Safe_typing.allow_delayed_constants := true; (* Needed to delegate or skip proofs *)
  load_vos := true;
  Sys.(set_signal sigint Signal_ignore);
  main_loop ()
[%%endif]
