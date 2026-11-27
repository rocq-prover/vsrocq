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

type event
type events = event Sel_core.Event.t list

val handle_event : event -> events
val pr_event : Format.formatter -> event -> unit

(** [init ~input ~output] where [input k] is the (recurrent) event receiving
    one message from the client and [k] decodes it, and [output] sends
    a JSON message to the client. *)
val init :
  input:(((Bytes.t, exn) result -> event) -> event Sel_core.Event.t) ->
  output:(string -> unit) ->
  event Sel_core.Event.t list
