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

open Printing
open Lsp.Types
open EConstr

open Ppx_yojson_conv_lib.Yojson_conv.Primitives

type proof_statement = {
  statement: string;
  range: Range.t;
} [@@deriving yojson]

type proof_step = {
  tactic: string;
  range: Range.t;
} [@@deriving yojson]

type proof_block = {
  statement: proof_statement;
  range: Range.t;
  steps: proof_step list;
} [@@deriving yojson]

type hypothesis = {
  ids: string list;
  body: pp option;
  _type: pp;
  universe: string;
} [@@deriving yojson]

type goal = {
  id: int;
  name: string option;
  hypotheses: hypothesis list;
  goal: pp;
} [@@deriving yojson]

type t = {
  goals: goal list;
  shelvedGoals: goal list;
  givenUpGoals: goal list;
  unfocusedGoals: goal list;
} [@@deriving yojson]

open Printer
[%%if rocq = "8.18" || rocq = "8.19" || rocq = "8.20" || rocq = "9.0" || rocq = "9.1" || rocq = "9.2"]
module CompactedDecl = Context.Compacted.Declaration
type compacted_context = EConstr.compacted_context
let get_ids = function
  | CompactedDecl.LocalAssum (ids, _) | LocalDef (ids, _, _) ->
    List.map (fun id -> id.Context.binder_name) ids

let compact sigma env = Termops.compact_named_context sigma (EConstr.named_context env)
[%%else]
module CompactedDecl = Ppconstr.CompactedDecl
type compacted_context = CompactedDecl.t list
let get_ids = function
  | CompactedDecl.LocalAssum (ids, _) | LocalDef (ids, _, _) ->
    List.map (fun (_,id) -> id.Context.binder_name) ids

let compact sigma env = Ppconstr.compact_named_context sigma (Environ.named_context_val env)
[%%endif]

[%%if rocq = "8.18" || rocq = "8.19" || rocq = "8.20" || rocq = "9.0" || rocq = "9.1"]
let goal_name = Names.Id.to_string
[%%else]
let goal_name = Libnames.string_of_path
[%%endif]

let hypothesis_universe env sigma typ =
  try
    let sort = Retyping.get_sort_of env sigma typ in
    Pp.string_of_ppcmds (Printer.pr_sort sigma (ESorts.kind sigma sort))
  with _ -> ""

let decl_universe env sigma = function
  | CompactedDecl.LocalAssum (_, typ) -> hypothesis_universe env sigma typ
  | CompactedDecl.LocalDef (_, _, typ) -> hypothesis_universe env sigma typ

let ids_of_decl decl =
  List.map (fun id -> Pp.string_of_ppcmds @@ Ppconstr.pr_id id) (get_ids decl)

let mk_hypothesis env sigma d =
  let pbody, typ = match d with
    | CompactedDecl.LocalAssum (_, typ) -> None, typ
    | CompactedDecl.LocalDef (_, c, typ) ->
      let pb = pr_leconstr_env ~inctx:true env sigma c in
      let pb = if EConstr.isCast sigma c then Pp.surround pb else pb in
      Some pb, typ
  in
  {
    ids = ids_of_decl d;
    body = Option.map pp_of_rocqpp pbody;
    _type = pp_of_rocqpp (pr_letype_env env sigma typ);
    universe = decl_universe env sigma d;
  }

let mk_fallback_hypothesis hyp = {
  ids = [];
  body = None;
  _type = pp_of_rocqpp hyp;
  universe = "";
}

let add_diff_hypotheses_info env sigma hyps =
  (* The proof-diff API gives us already-rendered hypotheses. We try to match them
   against the current compacted context to recover ids and universe
   information; if the shapes do not line up, keep the rendered diff hypotheses
   and leave the extra metadata empty. *)
  let enrich_hypothesis decl hyp =
    {
      (mk_fallback_hypothesis hyp) with
      ids = ids_of_decl decl;
      universe = decl_universe env sigma decl;
    }
  in
  let compacted = compact sigma env in
  if List.length hyps <> List.length compacted then
    List.map mk_fallback_hypothesis hyps
  else
    List.map2 enrich_hypothesis compacted hyps

let mk_goal env sigma g =
  let EvarInfo evi = Evd.find sigma g in
  let env = Evd.evar_filtered_env env evi in
  let id = Evar.repr g in
  let name = Option.map goal_name (Evd.evar_ident g sigma) in
  let concl = match Evd.evar_body evi with
  | Evar_empty -> Evd.evar_concl evi
  | Evar_defined body -> Retyping.get_type_of env sigma body
  in
  let ccl =
    pr_letype_env ~goal_concl_style:true env sigma concl
  in
  let hyps = List.map (mk_hypothesis env sigma) (compact sigma env) |> List.rev in
  {
    id;
    name;
    hypotheses = hyps;
    goal = pp_of_rocqpp ccl;
  }

[%%if rocq = "8.18" || rocq = "8.19" || rocq = "8.20" || rocq = "9.0" || rocq = "9.1"]
let diff_goal = Proof_diffs.diff_goal
[%%else]
let diff_goal ?og_s g = Proof_diffs.diff_goal ~flags:(PrintingFlags.current()) ?og_s g
[%%endif]

let mk_goal_diff diff_goal_map env sigma g =
  let EvarInfo evi = Evd.find sigma g in
  let env = Evd.evar_filtered_env env evi in
  let id = Evar.repr g in
  let name = Option.map goal_name (Evd.evar_ident g sigma) in
  let og_s = Proof_diffs.map_goal g diff_goal_map in
  let (hyps, ccl) = diff_goal ?og_s (Proof_diffs.make_goal env sigma g) in
  {
    id;
    name;
    hypotheses = List.rev (add_diff_hypotheses_info env sigma hyps);
    goal = pp_of_rocqpp ccl;
  }

let proof_of_state st =
  match st.Vernacstate.interp.lemmas with
  | None -> None
  | Some lemmas ->
    Some (lemmas |> Vernacstate.LemmaStack.with_top ~f:Declare.Proof.get)

(* The Rocq diff API is so poorly designed that we have to imperatively set a
   string option to control the behavior of `mk_goal_diff`. We do the required
   plumbing here. *)
let string_of_diff_mode = function
  | Settings.Goals.Diff.Mode.Off -> "off"
  | On -> "on"
  | Removed -> "removed"

let set_diff_mode diff_mode =
  Goptions.set_string_option_value Proof_diffs.opt_name @@ string_of_diff_mode diff_mode

let get_proof ~previous diff_mode st =
  Vernacstate.unfreeze_full_state st;
  match proof_of_state st with
  | None -> None
  | Some proof ->
    let mk_goal env sigma g =
      match diff_mode with
      | Settings.Goals.Diff.Mode.Off ->
        mk_goal env sigma g
      | _ ->
        begin
          set_diff_mode diff_mode;
          match Option.bind previous proof_of_state with
          | None -> mk_goal env sigma g
          | Some old_proof ->
            let diff_goal_map = Proof_diffs.make_goal_map old_proof proof in
            mk_goal_diff diff_goal_map env sigma g
        end
    in
    let env = Global.env () in
    let proof_data = Proof.data proof in
    let b_goals = Proof.background_subgoals proof in
    let sigma = proof_data.sigma in
    let goals = List.map (mk_goal env sigma) proof_data.goals in
    let unfocusedGoals = List.map (mk_goal env sigma) b_goals in
    let shelvedGoals = List.map (mk_goal env sigma) (Evd.shelf sigma) in
    let givenUpGoals = List.map (mk_goal env sigma) (Evar.Set.elements @@ Evd.given_up sigma) in
    Some {
      goals;
      shelvedGoals;
      givenUpGoals;
      unfocusedGoals;
    }

let mk_proof_statement statement range = {statement; range}

let mk_proof_step tactic range = {tactic; range}

let mk_proof_block statement steps range = {steps; statement; range}
