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

[%%import "vsrocq_config.mlh"]

let log = Log.mk_log "optionOverrides"

let pr_key key = String.concat " " key

(* The value set by the commands *)
let setting key =
  match Goptions.get_option_value key with
  | None -> Error (Printf.sprintf "There is no option %s." (pr_key key))
  | Some read ->
    match read () with
    | Goptions.BoolValue b -> Ok b
    | _ -> Error (Printf.sprintf "%s is not a flag." (pr_key key))

[%%if rocq = "8.18" || rocq = "8.19" || rocq = "8.20" || rocq = "9.0" || rocq = "9.1" || rocq = "9.2" || rocq = "9.3"]

(* [CDebug.get_flags] uses the syntax of [Set Debug]: a comma separated list
   of enabled "component" and disabled "-component" *)
let parse_debug_flags s =
  let parse_flag s =
    if String.length s > 0 && s.[0] = '-'
    then String.sub s 1 (String.length s - 1), false
    else s, true
  in
  List.map parse_flag (String.split_on_char ',' s)

let unsupported = Error "Toggling flags from the editor requires Rocq 9.4 or later."

let toggle_flag _ = unsupported

let flag_value key = Result.to_option (setting key)

let debug_flags () =
  List.map (fun (name, b) -> name, b, false) (parse_debug_flags (CDebug.get_flags ()))

let toggle_debug_flag _ = unsupported

let clear () = ()

[%%else]

let user_error f =
  try Ok (f ())
  with CErrors.UserError msg -> Error (Pp.string_of_ppcmds msg)

(* The overrides set by this module, to remove them in [clear] *)
let flags = ref Goptions.OptionMap.empty
let debug = ref CString.Set.empty

let toggle_flag key =
  let override = match Goptions.get_option_override key with
    | Some _ -> Ok None
    | None -> Result.map (fun b -> Some (not b)) (setting key)
  in
  Result.bind override (fun override ->
    log.debug (fun () -> Printf.sprintf "override %s := %s" (pr_key key)
      (match override with None -> "none" | Some b -> string_of_bool b));
    user_error (fun () ->
      Goptions.set_option_override key (Option.map (fun b -> Goptions.BoolValue b) override);
      flags := Goptions.OptionMap.add key () !flags;
      override))

let flag_value key =
  match Goptions.get_option_override key with
  | Some (Goptions.BoolValue b) -> Some b
  | Some _ -> None
  | None -> Result.to_option (setting key)

let debug_flags () =
  (* an override of "all" applies to the flags without their own override *)
  let all = Option.has_some (CDebug.get_override "all") in
  List.map (fun (name, b) -> name, b, all || Option.has_some (CDebug.get_override name))
    (CDebug.get_flag_values ())

let toggle_debug_flag name =
  let override = match CDebug.get_override name with
    | Some _ -> Ok None
    | None ->
      match List.assoc_opt name (CDebug.get_flag_values ()) with
      | Some b -> Ok (Some (not b))
      | None -> Error (Printf.sprintf "There is no debug flag \"%s\"." name)
  in
  Result.bind override (fun override ->
    log.debug (fun () -> Printf.sprintf "override debug flag %s := %s" name
      (match override with None -> "none" | Some b -> string_of_bool b));
    user_error (fun () ->
      CDebug.set_override name override;
      debug := CString.Set.add name !debug;
      override))

let clear () =
  Goptions.OptionMap.iter (fun key () ->
    try Goptions.set_option_override key None with CErrors.UserError _ -> ()) !flags;
  CString.Set.iter (fun name ->
    try CDebug.set_override name None with CErrors.UserError _ -> ()) !debug;
  flags := Goptions.OptionMap.empty;
  debug := CString.Set.empty

[%%endif]
