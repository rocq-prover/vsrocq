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
open Protocol.LspWrapper

type sentence_id = Stateid.t
type sentence_id_set = Stateid.Set.t

module RangeList = struct

  type t = Range.t list
  
  let insert_or_merge_range r ranges =
    let ranges = List.sort Range.compare (r :: ranges) in
    let rec insert_or_merge_sorted_ranges r1 = function
      | [] -> [r1]
      | r2 :: l ->
        if Range.included ~in_:r1 r2 then (*since the ranges are sorted, only r2 can be included in r1*)
          insert_or_merge_sorted_ranges r1 l
        else if Range.prefixes ~in_:r2 r1 then
          begin
            let range = Range.{start = r1.Range.start; end_ = r2.Range.end_} in
            insert_or_merge_sorted_ranges range l
          end
        else
          r1 :: (insert_or_merge_sorted_ranges r2 l)
    in
    insert_or_merge_sorted_ranges (List.hd ranges) (List.tl ranges)

  let rec remove_or_truncate_range r = function
  | [] -> []
  | r1 :: l ->
    if Range.equals r r1
    then
      l
    else if Range.strictly_included ~in_: r1 r then
      Range.{ start = r1.Range.start; end_ = r.Range.start} :: Range.{ start = r.Range.end_; end_ = r1.Range.end_} :: l
    else if Range.prefixes ~in_:r1 r then
      Range.{ start = r.Range.end_; end_ = r1.Range.end_} :: l
    else if Range.postfixes ~in_:r1 r then
      Range.{ start = r1.Range.start; end_ = r.Range.start} :: l
    else
      r1 :: (remove_or_truncate_range r l)

    let rec cut_from_range r = function
    | [] -> []
    | r1 :: l ->
      let (<=) x y = Position.compare x y <= 0 in
      if r.Range.start <= r1.Range.start then
        l
      else if r.Range.start <= r1.Range.end_ then
        Range.{start = r1.Range.start; end_ = r.Range.start} :: l
      else
        r1 :: (cut_from_range r l)

end


type exec_overview = {
  prepared: RangeList.t;
  processing : RangeList.t;
  processed : RangeList.t;
}

let empty_overview = {processing = []; processed = []; prepared = []}

[%%if rocq = "8.18" || rocq = "8.19" || rocq = "8.20"]
  module Quickfix = struct
    type t = unit
    let make ~loc:_ _pp = ()
    let from_exception _ = Ok([])
    let pp = Pp.mt
    let loc _ = Loc.make_loc (0,0)
  end
[%%endif]

type text_edit = Range.t * string

type link = {
  write_to :  Unix.file_descr;
  read_from:  Unix.file_descr;
}

type error = {
  code: Jsonrpc.Response.Error.Code.t option;
  message: string;
}

type 'a log = Log : 'a -> 'a log

type feedback_message = Feedback.level * Loc.t option * Quickfix.t list * Pp.t

type document_id = int

type feedback_data = Feedback.route_id * sentence_id * feedback_message

type rocq_feedback_listener = int

(* ugly stuff to correctly dispatch Rocq feedback *)
type feedback_pipe = {
  doc_id : document_id; (* unique number used to interface with Rocq's Feedback *)
  rocq_feeder : rocq_feedback_listener;
  sel_feedback_queue : feedback_data Queue.t;
  sel_cancellation_handle : Sel.Event.cancellation_handle;
}

type sentence_checking_result =
  | Success of Vernacstate.t option
  | Failure of Pp.t Loc.located * Quickfix.t list option * Vernacstate.t option (* State to use for resiliency *)

type document_updates =
  (sentence_id * sentence_checking_result) list

type ('state,'event) handled_event = {
    state : 'state option;
    events: 'event Sel.Event.t list;
    update_view: bool;
    notification: Protocol.ExtProtocol.Notification.Server.t option;
}
let make_handled_event ?state ?(events=[]) ?(update_view=false) ?notification () =
  { state ; events; update_view; notification; }

let lift_handled_event update_state inject_events { state; events; update_view; notification } =
  { state = update_state state; events = inject_events events; update_view; notification }

type 'a interruptible_result =
  Terminated of 'a | Aborted of Exninfo.iexn | Interrupted
