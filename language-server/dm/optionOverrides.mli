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

(** Rocq flags and debug flags forced from the editor, independently of the
    document.

    Rocq keeps the values of its options in the summary, so restoring the
    state of a sentence also restores the values set by the document. The
    overrides are therefore re-applied each time a state is restored, to
    execute a sentence or to run a query, and take precedence over the
    [Set]/[Unset] commands of the document until they are cleared. *)

val toggle_flag : Goptions.option_name -> (bool, string) Result.t
(** Flip the value of a boolean option (e.g. [["Ltac"; "Backtrace"]]) and
    return the new value. A flag unknown to the current state (declared by a
    plugin not loaded yet) is assumed to be off. Fails if the option is not a
    flag. *)

val debug_flags : unit -> (string * bool) list
(** The debug flags known to Rocq (see [CDebug.get_flags]), with their
    effective values. *)

val toggle_debug_flag : string -> (bool, string) Result.t
(** Flip a debug flag (e.g. ["backtrace"], ["all"] or a component name) and
    return its new value. Fails if the flag does not exist. *)

val clear : unit -> unit
(** Forget all the overrides. *)

val apply : unit -> unit
(** Apply the overrides to the current Rocq state. *)

val apply_to_state : Vernacstate.t -> Vernacstate.t
(** [apply_to_state st] is [st] with the overrides applied. It is [st] itself
    when there is no override. *)
