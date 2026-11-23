(**************************************************************************)
(*                                                                        *)
(*                                 VSRoc                                  *)
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

(* No processes: proofs are never delegated *)

let delegation_available = false

type sentence_id = Stateid.t

type job_handle = unit

module type Job = sig
  type t
  val name : string
  val binary_name : string
  val initial_pool_size : int
  val marshallable : t -> t
  type update_request
  val appendFeedback : Feedback.route_id * sentence_id -> (Feedback.level * Loc.t option * Quickfix.t list * Pp.t) -> update_request
end

let mk_job_handle _ : job_handle = ()

let cancel_job () = ()

module type Worker = sig
  type job_t
  type job_update_request
  val resize_pool : int -> unit
  type delegation
  val pr_event : delegation -> Pp.t
  type events = delegation Sel.Event.t list
  val handle_event : delegation -> (job_update_request option * events)
  val worker_available :
    jobs:((job_handle * Sel.Event.cancellation_handle * job_t) Queue.t) ->
    fork_action:(job_t -> send_back:(job_update_request -> unit) -> unit) ->
    feedback_cleanup:(unit -> unit) ->
    delegation Sel.Event.t
  type options
  [%%if rocq = "8.18" || rocq = "8.19" || rocq = "8.20"]
  val parse_options : string list -> options * string list
  [%%else]
  val parse_options : Coqargs.t -> string list -> options * string list
  [%%endif]
  val setup_plumbing : options -> ((job_update_request -> unit) * job_t)
  val log : Log.t
end

module MakeWorker (Job : Job) = struct
  type job_t = Job.t
  type job_update_request = Job.update_request

  let log = Log.mk_log ("worker." ^ Job.name)

  let resize_pool _ = ()

  type delegation = |
  let pr_event : delegation -> Pp.t = function _ -> .
  type events = delegation Sel.Event.t list
  let handle_event : delegation -> (job_update_request option * events) = function _ -> .

  let not_available () =
    CErrors.anomaly Pp.(str "proof delegation is not available")

  let worker_available ~jobs:_ ~fork_action:_ ~feedback_cleanup:_ = not_available ()

  type options = unit
  [%%if rocq = "8.18" || rocq = "8.19" || rocq = "8.20"]
  let parse_options a = (), a
  [%%else]
  let parse_options _ a = (), a
  [%%endif]
  let setup_plumbing () = not_available ()
end
