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

let log = Log.mk_log "optionOverrides"

let flag_overrides : bool Goptions.OptionMap.t ref = ref Goptions.OptionMap.empty
let debug_overrides : bool CString.Map.t ref = ref CString.Map.empty

let clear () =
  flag_overrides := Goptions.OptionMap.empty;
  debug_overrides := CString.Map.empty

let is_empty () =
  Goptions.OptionMap.is_empty !flag_overrides && CString.Map.is_empty !debug_overrides

(* Flags *)

let pr_key key = String.concat " " key

let read_flag key =
  match Goptions.get_option_value key with
  | None -> Error (Printf.sprintf "There is no option %s." (pr_key key))
  | Some read ->
    match read () with
    | Goptions.BoolValue b -> Ok b
    | _ -> Error (Printf.sprintf "%s is not a flag." (pr_key key))

let toggle_flag key =
  let current =
    match Goptions.OptionMap.find_opt key !flag_overrides with
    | Some b -> Ok b
    | None ->
      match read_flag key with
      | Ok b -> Ok b
      | Error _ as e when Option.has_some (Goptions.get_option_value key) -> e (* not a flag *)
      | Error _ ->
        (* The flag may be declared by a plugin which is not loaded in the
           current state (e.g. Ltac Backtrace before any document is
           executed): flags are off by default. *)
        log.debug (fun () -> Printf.sprintf "unknown flag %s, assuming it is off" (pr_key key));
        Ok false
  in
  Result.map (fun b ->
    let b = not b in
    log.debug (fun () -> Printf.sprintf "override %s := %b" (pr_key key) b);
    flag_overrides := Goptions.OptionMap.add key b !flag_overrides;
    b) current

let apply_flag key v =
  match read_flag key with
  | Ok b when b = v -> () (* avoids adding a Lib leaf for each sentence *)
  | Ok _ -> Goptions.set_bool_option_value_gen ~locality:Goptions.OptLocal key v
  | Error _ -> ()

(* Debug flags *)

(* [CDebug.get_flags] uses the syntax of [Set Debug]: a comma separated list
   of enabled "component" and disabled "-component" *)
let parse_debug_flags s =
  let parse_flag s =
    if String.length s > 0 && s.[0] = '-'
    then String.sub s 1 (String.length s - 1), false
    else s, true
  in
  List.map parse_flag (String.split_on_char ',' s)

let print_debug_flags l =
  String.concat "," (List.map (fun (name, b) -> if b then name else "-" ^ name) l)

let current_debug_flags () = parse_debug_flags (CDebug.get_flags ())

let debug_flags () =
  List.map (fun (name, enabled) ->
    name, Option.default enabled (CString.Map.find_opt name !debug_overrides))
    (current_debug_flags ())

let toggle_debug_flag name =
  let current =
    match CString.Map.find_opt name !debug_overrides with
    | Some b -> Ok b
    | None ->
      match List.assoc_opt name (current_debug_flags ()) with
      | Some b -> Ok b
      | None -> Error (Printf.sprintf "There is no debug flag \"%s\"." name)
  in
  Result.map (fun b ->
    let b = not b in
    log.debug (fun () -> Printf.sprintf "override debug flag %s := %b" name b);
    debug_overrides := CString.Map.add name b !debug_overrides;
    b) current

let apply_debug_flags () =
  if not (CString.Map.is_empty !debug_overrides) then begin
    let current = current_debug_flags () in
    let stale = CString.Map.filter (fun name b -> List.assoc_opt name current <> Some b) !debug_overrides in
    if not (CString.Map.is_empty stale) then
      (* "all" comes first in the bindings, so that it does not undo the
         other flags *)
      CDebug.set_flags (print_debug_flags (CString.Map.bindings stale))
  end

(* Application *)

let apply () =
  Goptions.OptionMap.iter apply_flag !flag_overrides;
  apply_debug_flags ()

let apply_to_state st =
  if is_empty () then st
  else begin
    Vernacstate.unfreeze_full_state st;
    apply ();
    Vernacstate.freeze_full_state ()
  end
