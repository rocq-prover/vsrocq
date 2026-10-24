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

open Ppx_yojson_conv_lib.Yojson_conv.Primitives

(* Printing flags set by the user from the client, for one document. Option
   values are part of the frozen Rocq state of each sentence, so these
   overrides are not stored in it: they are re-applied with [apply] every time
   a state is unfrozen to print something for the client (goals, queries,
   hovers), and to the state a document is reset to. *)

type printing_option = {
  name : string;
  value : bool;
  overridden : bool;
} [@@deriving yojson]

type t = (Goptions.option_name * bool) list

let empty = []

let is_empty overrides = overrides = []

let key_of_name name = String.split_on_char ' ' name |> List.filter (fun s -> s <> "")

let name_of_key key = String.concat " " key

let is_printing_flag key { Goptions.opt_depr; opt_value } =
  match key, opt_depr, opt_value with
  | "Printing" :: _ :: _, None, Goptions.BoolValue _ -> true
  | _ -> false

let set overrides name value =
  let key = key_of_name name in
  match Goptions.OptionMap.find_opt key (Goptions.get_tables ()) with
  | Some st when is_printing_flag key st -> Ok ((key, value) :: List.remove_assoc key overrides)
  | _ -> Error ("Unknown printing flag: " ^ name)

(* Must be called right after unfreezing a Rocq state. Unfreezing is skipped
   when the state is the one last unfrozen, which is no longer true once an
   override has been applied: drop that cache, so that the next unfreeze
   restores the flags of the state, and the overrides never leak into the
   execution of a document or into another document. *)
let apply overrides =
  if overrides <> [] then begin
    List.iter (fun (key, value) -> Goptions.set_bool_option_value key value) overrides;
    Vernacstate.Interp.invalidate_cache ()
  end

(* The printing flags of the current Rocq state, [overrides] included *)
let list overrides =
  let add key st acc =
    match st.Goptions.opt_value with
    | Goptions.BoolValue value when is_printing_flag key st ->
      { name = name_of_key key; value; overridden = List.mem_assoc key overrides } :: acc
    | _ -> acc
  in
  List.rev @@ Goptions.OptionMap.fold add (Goptions.get_tables ()) []
