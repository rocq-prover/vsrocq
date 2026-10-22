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
val line_count : t -> int
val line_nonwhitespace_start : t -> int -> Position.t option

val position_of_loc : t -> int -> Position.t
val loc_of_position : t -> Position.t -> int
val end_loc : t -> int

val range_of_loc : t -> Loc.t -> Range.t
val word_at_loc: t -> int -> string option
val string_in_range: t -> int -> int -> string

(** A text edit in byte offsets. The replaced range runs from [start] to
    [stop], [stop] excluded, in the text {e before} the edit, and
    [inserted_length] is the length of the text that replaces it. For example:
     "123456" -> "1236" (remove 45) gives 3, 5, 0
     "1236" -> "123456" (insert 45) gives 3, 3, 2 *)
type byte_edit = { start: int; stop: int; inserted_length: int }

(** Returns how far an edit moves the text from its [stop] on. Negative when the
    edit removes more than it inserts. *)
val shift_after_stop : byte_edit -> int

(** Applies a text edit and returns it in byte offsets. *)
val apply_text_edit : t -> text_edit -> t * byte_edit
