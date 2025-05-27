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

open Host
module TacticWorkerProcess : sig
  type options
[%%if rocq = "8.18" || rocq = "8.19" || rocq = "8.20"]
   val parse_options : string list -> options * string list
[%%else]
   val parse_options : Coqargs.t -> string list -> options * string list
[%%endif]
  val main : st:State.t -> options -> unit
  val log : ?force:bool -> (unit -> string) -> unit
end

(* HACK: the sentence id of the current phrase is used to report errors *)
val set_id_for_feedback : Feedback.route_id -> Host_common.Types.sentence_id -> unit
