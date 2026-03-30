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

let Log log = Log.mk_log "utilities"

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

let shift_1qf ~start ~offset q =
  let loc = Quickfix.loc q in
  let loc' = shift_loc ~start ~offset loc in
  if loc' == loc then q else Quickfix.make ~loc:loc' (Quickfix.pp q)

let shift_quickfix ~start ~offset qf =
  Option.Smart.map (CList.Smart.map (shift_1qf ~start ~offset)) qf

let shift_checking_result ~start ~offset = function
  | Success _ | Failure ((None,_),_,_) as x -> x
  | (Failure ((Some loc,e),qf,st)) as x ->
      let loc' = shift_loc ~start ~offset loc in
      let qf' = shift_quickfix ~start ~offset qf in
      if loc' == loc && qf' == qf then x else Failure ((Some loc',e),qf',st)

let doc_id = ref (-1)
let fresh_doc_id () = incr doc_id; !doc_id

let feedback_pipe_cleanup { rocq_feeder; sel_feedback_queue; sel_cancellation_handle } =
  Feedback.del_feeder rocq_feeder;
  Queue.clear sel_feedback_queue;
  Sel.Event.cancel sel_cancellation_handle

let context_of_vernac_state (st : Vernacstate.t) =
  let st = st.Vernacstate.interp in
  Vernacstate.Interp.unfreeze_interp_state st;
  begin match st.lemmas with
  | None ->
    let env = Global.env () in
    let sigma = Evd.from_env env in
    sigma, env
  | Some lemmas ->
    let open Declare in
    let open Vernacstate in
    lemmas |> LemmaStack.with_top ~f:Proof.get_current_context
  end

(** Returns the vernac state after the sentence *)
let get_vernac_state (checked : sentence_checking_result option) =
  match checked with
  | None -> log (fun () -> "Cannot find state for get_vernac_state"); None
  | Some (Failure (_,_,None)) -> log (fun () -> "State requested after error with no state"); None
  | Some (Success None) -> log (fun () -> "State requested in a remotely checked state"); None
  | Some (Success (Some st))
  | Some (Failure (_,_, Some st)) -> Some st


let get_proof_context (checked : sentence_checking_result option) =
  match checked with
  | None -> log (fun () -> "Cannot find state for get_proof_context"); None
  | Some (Failure _) -> log (fun () -> "Context requested in error state"); None
  | Some (Success None) -> log (fun () -> "Context requested in a remotely checked state"); None
  | Some (Success (Some st)) -> Some (context_of_vernac_state st)
