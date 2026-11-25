(* Entry point of the web language server.

   There are no threads: the JavaScript side (worker.js) pushes the messages
   coming from the client with [vsrocq.push], the events are handled by the
   driver of Sel_js, from the JavaScript event loop. Messages for the client
   are sent with [vsrocqSend]. While Rocq computes, the JavaScript event loop
   is blocked, so an interruption request is read from shared memory by
   [vsrocqInterrupted] (polled by Rocq via ProverThread). *)

open Js_of_ocaml

let log = Dm.Log.mk_log "web"

let inbox : string Queue.t = Queue.create ()

let input k =
  Sel.On.queue ~priority:Dm.PriorityManager.lsp_message ~name:"lsp" inbox
    (fun s -> k (Ok (Bytes.of_string s)))

let output msg =
  ignore (Js.Unsafe.fun_call (Js.Unsafe.global##.vsrocqSend) [| Js.Unsafe.inject (Js.string msg) |])

let interrupted () =
  Js.to_bool (Js.Unsafe.fun_call (Js.Unsafe.global##.vsrocqInterrupted) [||])

let handle_event ev =
  log.debug (fun () -> Format.asprintf "event: %a" LspManager.pr_event ev);
  let evs =
    try LspManager.handle_event ev
    with exn ->
      let info = Exninfo.capture exn in
      log.error (fun () -> "uncaught exception: " ^
        Pp.string_of_ppcmds (CErrors.iprint_no_report info));
      [] in
  flush_all ();
  evs

let () =
  Coqinit.init_ocaml ();
  (* Plugins are bytecode, loaded with Dynlink, which by default refuses
     units declaring external primitives (e.g. atdgen-runtime, needed by
     rocq-elpi). Native Dynlink does not check this, so Rocq never asks:
     allow them; a missing primitive is reported when linking the plugin. *)
  Dynlink.allow_unsafe_modules true;
  let cwd = Unix.getcwd () in
  let opts = Args.get_local_args (Args.Server_start cwd) in
  Coqinit.init_runtime ~usage:(Args.usage ()) opts;
  Safe_typing.allow_delayed_constants := true;
  Loadpath.load_vos_libraries := true;
  Dm.ProverThread.set_external_interrupt interrupted;
  Sel_js.run handle_event (Sel.Todo.add Sel.Todo.empty (LspManager.init ~input ~output));
  Js.Unsafe.set Js.Unsafe.global "vsrocq" (object%js
    method push (s : Js.js_string Js.t) =
      Queue.push (Js.to_string s) inbox;
      Sel_js.wakeup ()
  end);
  ignore (Js.Unsafe.fun_call (Js.Unsafe.global##.vsrocqReady) [||])
