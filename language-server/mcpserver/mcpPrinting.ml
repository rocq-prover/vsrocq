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

open Lsp.Types

(** Format a range as a human-readable string *)
let format_range (range : Range.t) : string =
  Printf.sprintf "line %d, character %d to line %d, character %d"
    (range.start.line + 1) range.start.character
    (range.end_.line + 1) range.end_.character

let format_proof_state (ps : Protocol.PpProofState.t option) : string =
  match ps with
  | None -> "No proof in progress."
  | Some { goals; shelvedGoals; givenUpGoals; unfocusedGoals } ->
    let format_goal (g : Protocol.PpProofState.goal) =
      let hyps = List.map (fun (h : Protocol.PpProofState.hypothesis) ->
        let ids = String.concat ", " h.ids in
        let body = match h.body with
          | Some b -> " := " ^ b
          | None -> ""
        in
        Printf.sprintf "%s%s : %s" ids body h._type
      ) g.hypotheses in
      Printf.sprintf "Goal %d:\n  %s\n  ============================\n  %s"
        g.id
        (String.concat "\n  " hyps)
        g.goal
    in
    let goals_str =
      if goals = [] then "No more subgoals."
      else Printf.sprintf "%d goal(s):\n%s"
        (List.length goals)
        (String.concat "\n\n" (List.map format_goal goals))
    in
    let shelved_str =
      if shelvedGoals = [] then ""
      else Printf.sprintf "\n\nShelved goals: %d" (List.length shelvedGoals)
    in
    let given_up_str =
      if givenUpGoals = [] then ""
      else Printf.sprintf "\n\nGiven up goals: %d" (List.length givenUpGoals)
    in
    let unfocused_str =
      if unfocusedGoals = [] then ""
      else Printf.sprintf "\n\nUnfocused goals: %d" (List.length unfocusedGoals)
    in
    goals_str ^ shelved_str ^ given_up_str ^ unfocused_str

let format_severity (severity : DiagnosticSeverity.t) : string =
  match severity with
  | DiagnosticSeverity.Error -> "Error"
  | DiagnosticSeverity.Warning -> "Warning"
  | DiagnosticSeverity.Information -> "Info"
  | DiagnosticSeverity.Hint -> "Hint"

let format_messages (messages : (DiagnosticSeverity.t * string) list) : string =
  if messages = [] then "No messages."
  else
    let format_msg (severity, msg) =
      Printf.sprintf "[%s] %s" (format_severity severity) msg
    in
    String.concat "\n" (List.map format_msg messages)

let get_observe_range (st : Dm.DocumentManager.state) : Range.t option =
  Dm.DocumentManager.observe_id_range st

let get_proof_state (st : Dm.DocumentManager.state) : string =
  let observe_id = Dm.DocumentManager.Internal.observe_id st in
  let ost = Option.bind observe_id
    (Dm.ExecutionManager.get_vernac_state (Dm.DocumentManager.Internal.execution_state st)) in
  match ost with
  | None -> "No proof state available (document may not be executed to this point)."
  | Some vst -> format_proof_state (Protocol.PpProofState.get_proof vst)

let get_messages (st : Dm.DocumentManager.state) : string =
  match Dm.DocumentManager.Internal.observe_id st with
  | None -> "No messages (at document start)."
  | Some id ->
    let messages = Dm.DocumentManager.get_string_messages st id in
    format_messages messages

let get_errors (st : Dm.DocumentManager.state) : string =
  let exec_state = Dm.DocumentManager.Internal.execution_state st in
  let document = Dm.DocumentManager.Internal.document st in
  let all_errors = Dm.ExecutionManager.all_errors exec_state in
  let valid_errors = List.filter (fun (id, _) ->
    Option.has_some (Dm.Document.get_sentence document id)
  ) all_errors in
  if valid_errors = [] then "No errors."
  else
    let format_error (id, (_oloc, msg, _qf)) =
      let range = Dm.Document.range_of_id document id in
      Printf.sprintf "[Error at %s] %s" (format_range range) (Pp.string_of_ppcmds msg)
    in
    String.concat "\n" (List.map format_error valid_errors)

let format_interp_result (st : Dm.DocumentManager.state) : string =
  let position_info = match get_observe_range st with
    | None -> "Position: document start (no sentences executed)"
    | Some range -> Printf.sprintf "Position: %s" (format_range range)
  in
  let proof_state = get_proof_state st in
  let messages = get_messages st in
  let errors = get_errors st in
  Printf.sprintf "%s\n\nProof state:\n%s\n\nMessages:\n%s\n\nErrors:\n%s" position_info proof_state messages errors
