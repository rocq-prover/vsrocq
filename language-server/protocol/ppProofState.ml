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

open Ppx_yojson_conv_lib.Yojson_conv.Primitives

type hypothesis = {
  ids: string list;
  body: string option;
  _type: string;
} [@@deriving yojson]

type goal = {
  id: int;
  name: string option;
  hypotheses: hypothesis list;
  goal: string;
} [@@deriving yojson]

type t = {
  goals: goal list;
  shelvedGoals: goal list;
  givenUpGoals: goal list;
  unfocusedGoals: goal list;
} [@@deriving yojson]

open Printer
module CompactedDecl = Context.Compacted.Declaration

let mk_pp_hyp env sigma (decl:EConstr.compacted_declaration) =
  let ids, pbody, typ = match decl with
    | CompactedDecl.LocalAssum (ids, typ) ->
       ids, None, typ
    | CompactedDecl.LocalDef (ids,c,typ) ->
       (* Force evaluation *)
       let pb = pr_leconstr_env ~inctx:true env sigma c in
       let pb = if EConstr.isCast sigma c then Pp.surround pb else pb in
       ids, Some pb, typ in
    let ids =
      List.map (fun id -> Pp.string_of_ppcmds @@ Ppconstr.pr_id id.Context.binder_name) ids in
    let body = Option.map Pp.string_of_ppcmds pbody in
    let typ = pr_letype_env env sigma typ in
    let _type = Pp.string_of_ppcmds typ in
    {ids; body; _type} 

[%%if rocq = "8.18" || rocq = "8.19" || rocq = "8.20" || rocq = "9.0" || rocq = "9.1"]
let goal_name = Names.Id.to_string
[%%else]
let goal_name = Libnames.string_of_path
[%%endif]

let mk_goal env sigma g =
  let EvarInfo evi = Evd.find sigma g in
  let env = Evd.evar_filtered_env env evi in
  let min_env = Environ.reset_context env in
  let id = Evar.repr g in
  let name = Option.map goal_name (Evd.evar_ident g sigma) in
  let concl = match Evd.evar_body evi with
  | Evar_empty -> Evd.evar_concl evi
  | Evar_defined body -> Retyping.get_type_of env sigma body
  in
  let ccl =
    pr_letype_env ~goal_concl_style:true env sigma concl
  in
  let mk_hyp d (env,l) =
    let d' = CompactedDecl.to_named_context d in
    let env' = List.fold_right EConstr.push_named d' env in
    let Refl = EConstr.Unsafe.eq in
    let hyp = mk_pp_hyp env sigma d in
    (env', hyp :: l)
  in
  let (_env, hyps) =
    Context.Compacted.fold mk_hyp
      (Termops.compact_named_context sigma (EConstr.named_context env)) ~init:(min_env,[]) in
  {
    id;
    name;
    hypotheses = List.rev hyps;
    goal = Pp.string_of_ppcmds ccl;
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

let get_proof st =
  Vernacstate.unfreeze_full_state st;
  match proof_of_state st with
  | None -> None
  | Some proof ->
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