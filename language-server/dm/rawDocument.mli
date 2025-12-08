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
open Lsp.Types

type text_edit = Range.t * string

type t

val create : string -> t
val text : t -> string

val position_of_loc : t -> int -> Position.t
val loc_of_position : t -> Position.t -> int
val end_loc : t -> int

val range_of_loc : t -> Loc.t -> Range.t
val word_at_position: t -> Position.t -> string option
val string_in_range: t -> int -> int -> string

(** Applies a text edit, and returns start/stop location of the new text
    and the shift of what follows. eg
     "123456" -> "1236" (zap 45) it returns 3,5,-2
     "1236" -> "123456" (add 45) it returns 3,3,+2
*)
type edit_impact = { start: int; stop: int; shift_after_stop: int }
val apply_text_edit : t -> text_edit -> t * edit_impact
