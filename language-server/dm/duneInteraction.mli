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
(*                                                                        *)
(**************************************************************************)

(** Return the source file Dune copied to [file], or [file] when Dune cannot
    provide a verified source mapping. *)
val prefer_source : string -> string

(** Parser details exposed only for focused unit tests. *)
module Internal : sig
  val source_of_rules : file:string -> Yojson.Safe.t -> string option
end
