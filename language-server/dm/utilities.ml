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

open Types

let shift_loc ~start ~offset loc =
  let (loc_start, loc_stop) = Loc.unloc loc in
  if loc_start >= start then Loc.shift_loc offset offset loc
  else if loc_stop > start then Loc.shift_loc 0 offset loc
  else loc

let shift_feedback ~start ~offset (level, oloc, qf, msg as feedback) =
  match oloc with
  | None -> feedback
  | Some loc ->
    let loc' = shift_loc ~start ~offset loc in
    if loc' == loc then feedback else (level, Some loc', qf, msg)

let doc_id = ref (-1)
let fresh_doc_id () = incr doc_id; !doc_id

let feedback_pipe_cleanup { rocq_feeder; sel_feedback_queue; sel_cancellation_handle } =
  Feedback.del_feeder rocq_feeder;
  Queue.clear sel_feedback_queue;
  Sel.Event.cancel sel_cancellation_handle

