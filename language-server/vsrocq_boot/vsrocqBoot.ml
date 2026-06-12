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

[%%import "vsrocq_config.mlh"]

let Dm.Types.Log log = Dm.Log.mk_log "boot"

[%%if rocq = "8.18" || rocq = "8.19" || rocq = "8.20"]
let boot main =
  Coqinit.init_ocaml ();
  log (fun () -> "------------------ begin ---------------");
  let cwd = Unix.getcwd () in
  let opts = Args.get_local_args  cwd in
  let _injections = Coqinit.init_runtime opts in
  Safe_typing.allow_delayed_constants := true; (* Needed to delegate or skip proofs *)
  Flags.load_vos_libraries := true;
  Sys.(set_signal sigint Signal_ignore);
  main ()
[%%else]

[%%if rocq = "9.0" || rocq = "9.1"]
let load_vos = Flags.load_vos_libraries
[%%else]
let load_vos = Loadpath.load_vos_libraries
[%%endif]

let boot main =
  Coqinit.init_ocaml ();
  log (fun () -> "------------------ begin ---------------");
  let cwd = Unix.getcwd () in
  let opts = Args.get_local_args cwd in
  let () = Coqinit.init_runtime ~usage:(Args.usage ()) opts in
  Safe_typing.allow_delayed_constants := true; (* Needed to delegate or skip proofs *)
  load_vos := true;
  Sys.(set_signal sigint Signal_ignore);
  main ()
[%%endif]
