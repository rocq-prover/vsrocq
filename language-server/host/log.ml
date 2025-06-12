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

type event = string
type events = event Sel.Event.t list

[%% if rocq = "8.18" || rocq = "8.19"  || rocq = "8.20"]
let feedback_add_feeder_on_Message f =
  Feedback.add_feeder (fun fb ->
    match fb.Feedback.contents with
    | Feedback.Message(a,b,c) -> f fb.Feedback.route fb.Feedback.span_id fb.Feedback.doc_id a b [] c
    | _ -> ())
[%%else]
let feedback_add_feeder_on_Message f =
  Feedback.add_feeder (fun fb ->
    match fb.Feedback.contents with
    | Feedback.Message(a,b,c,d) -> f fb.Feedback.route fb.Feedback.span_id fb.Feedback.doc_id a b c d
    | _ -> ())
[%%endif]
let install_debug_feedback f =
  feedback_add_feeder_on_Message (fun _route _span _doc lvl loc _qf m ->
    match lvl, loc with
    | Feedback.Debug,None -> f Pp.(string_of_ppcmds m)
    | _ -> ())

(* We go through a queue in case we receive a debug feedback from Rocq before we
   replied to Initialize *)
let rocq_debug_feedback_queue = Queue.create ()
let main_debug_feeder = install_debug_feedback (fun txt -> Queue.push txt rocq_debug_feedback_queue)
   
let debug : event Sel.Event.t =
  Sel.On.queue ~name:"debug" ~priority:PriorityManager.feedback rocq_debug_feedback_queue (fun x -> x)
let cancel_debug_event = Sel.Event.get_cancellation_handle debug

let lsp_initialization_done () =
  lsp_initialization_done := true;
  Option.iter close_out_noerr init_log;
  Queue.iter handle_event initialization_feedback_queue;
  Queue.clear initialization_feedback_queue;
  [debug]

let worker_initialization_begins () =
  Sel.Event.cancel cancel_debug_event;
  Feedback.del_feeder main_debug_feeder;
    (* We do not want to inherit master's Feedback reader (feeder), otherwise we
    would output on the worker's stderr.
    Debug feedback from worker is forwarded to master via a specific handler
    (see [worker_initialization_done]) *)
  Queue.clear rocq_debug_feedback_queue

let worker_initialization_done ~fwd_event =
  let _ = install_debug_feedback fwd_event in
  ()
