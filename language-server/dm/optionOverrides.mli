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

(** Rocq flags and debug flags toggled from the editor.

    They are overridden in Rocq ([Goptions.set_option_override],
    [CDebug.set_override]), for the whole server and independently of the
    documents: the states of the sentences keep the values set by the
    documents, which apply again when the override is removed. This needs
    Rocq 9.4 or later; with earlier versions toggling fails. *)

val toggle_flag : Goptions.option_name -> (bool option, string) Result.t
(** Toggles the override of a flag (e.g. [["Ltac"; "Backtrace"]]): when it
    is not overridden, overrides it to the opposite of the value set by the
    commands in the current state, otherwise removes the override. Returns
    the new override. *)

val flag_value : Goptions.option_name -> bool option
(** The value of a flag in the current state, override included. *)

val debug_flags : unit -> (string * bool * bool) list
(** The debug flags known to Rocq (see [CDebug.get_flags]), with whether
    they are active, override included, and whether they are overridden
    (by an override of their own or of ["all"]). *)

val toggle_debug_flag : string -> (bool option, string) Result.t
(** Toggles the override of a debug flag (["all"], ["backtrace"] or a
    component), like [toggle_flag]. Returns the new override. *)

val clear : unit -> unit
(** Removes all the overrides set by [toggle_flag] and [toggle_debug_flag]. *)
