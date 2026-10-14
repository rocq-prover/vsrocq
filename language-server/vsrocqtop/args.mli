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

val usage : unit -> Boot.Usage.specific_usage

(* What a project file lookup is for: the server's own start, from its
   working directory, or checking one document, from the document's path. *)
type lookup =
  | Server_start of string
  | Document of string

val get_local_args : lookup -> Coqargs.t