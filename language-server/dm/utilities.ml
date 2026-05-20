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

open Types

let Log log = Log.mk_log "utilities"

let shift_loc ~start ~offset loc =
  let (loc_start, loc_stop) = Loc.unloc loc in
  if loc_start >= start then Loc.shift_loc offset offset loc
  else if loc_stop > start then Loc.shift_loc 0 offset loc
  else loc

let shift_feedback ~start ~offset (level, oloc, qf, msg as feedback) =
  match oloc with
  | None -> feedback
  | Some loc ->
    let loc' = shift_loc ~start ~offset loc in
    if loc' == loc then feedback else (level, Some loc', qf, msg)

let shift_1qf ~start ~offset q =
  let loc = Quickfix.loc q in
  let loc' = shift_loc ~start ~offset loc in
  if loc' == loc then q else Quickfix.make ~loc:loc' (Quickfix.pp q)

let shift_quickfix ~start ~offset qf =
  Option.Smart.map (CList.Smart.map (shift_1qf ~start ~offset)) qf

let shift_checking_result ~start ~offset = function
  | Success _ | Failure ((None,_),_,_) as x -> x
  | (Failure ((Some loc,e),qf,st)) as x ->
      let loc' = shift_loc ~start ~offset loc in
      let qf' = shift_quickfix ~start ~offset qf in
      if loc' == loc && qf' == qf then x else Failure ((Some loc',e),qf',st)

let doc_id = ref (-1)
let fresh_doc_id () = incr doc_id; !doc_id

let feedback_pipe_cleanup { rocq_feeder; sel_feedback_queue; sel_cancellation_handle } =
  Feedback.del_feeder rocq_feeder;
  Queue.clear sel_feedback_queue;
  Sel.Event.cancel sel_cancellation_handle

(** Returns the vernac state after the sentence *)
let get_vernac_state (checked : sentence_checking_result option) =
  match checked with
  | None -> log (fun () -> "Cannot find state for get_vernac_state"); None
  | Some (Failure (_,_,None)) -> log (fun () -> "State requested after error with no state"); None
  | Some (Success None) -> log (fun () -> "State requested in a remotely checked state"); None
  | Some (Success (Some st))
  | Some (Failure (_,_, Some st)) -> Some st

[%%if rocq ="8.18" || rocq ="8.19"]
let vernacstate_synterp_parsing x = x.Vernacstate.synterp.Vernacstate.Synterp.parsing
[%%else]
let vernacstate_synterp_parsing x = Vernacstate.(Synterp.parsing x.synterp)
[%%endif]

let rec fold_constr (f : 'acc -> Constrexpr.constr_expr -> 'acc) (acc : 'acc) (e : Constrexpr.constr_expr) : 'acc =
  let acc = f acc e in
  fold_constr_children f acc e

and fold_constr_children (f : 'acc -> Constrexpr.constr_expr -> 'acc) (acc : 'acc) (e : Constrexpr.constr_expr) : 'acc =
  let open Constrexpr in
  let rec walk acc = function
    | [] -> acc
    | e :: rest ->
      let acc = fold_constr f acc e in
      walk acc rest
  in
  let walk_opt acc = function
    | None -> acc
    | Some e -> fold_constr f acc e
  in
  let walk_binders acc binders =
    List.fold_left (fun acc b -> match b with
      | CLocalAssum (_, _, _, ty) -> fold_constr f acc ty
      | CLocalDef (_, _, e, e_opt) ->
        let acc = fold_constr f acc e in
        walk_opt acc e_opt
      | CLocalPattern _ -> acc
    ) acc binders
  in
  let walk_branches acc branches =
    List.fold_left (fun acc (b : branch_expr) ->
      let (_pats, body) = b.v in
      fold_constr f acc body
    ) acc branches
  in
  match e.v with
  | CRef _ | CHole _ | CPatVar _ | CEvar _ | CSort _ | CPrim _
  | CGenarg _ | CGenargGlob _ ->
    acc
  | CNotation (_, _, (terms, recursive_terms, _, recursive_binders)) ->
    let acc = walk acc terms in
    let acc = List.fold_left walk acc recursive_terms in
    List.fold_left walk_binders acc recursive_binders
  | CFix (_, fixes) ->
    List.fold_left (fun acc (_name, _rel, _order, binders, rtype, body) ->
      let acc = walk_binders acc binders in
      let acc = fold_constr f acc rtype in
      fold_constr f acc body
    ) acc fixes
  | CCoFix (_, cofixes) ->
    List.fold_left (fun acc (_name, _rel, binders, rtype, body) ->
      let acc = walk_binders acc binders in
      let acc = fold_constr f acc rtype in
      fold_constr f acc body
    ) acc cofixes
  | CProdN (binders, body) | CLambdaN (binders, body) ->
    let acc = walk_binders acc binders in
    fold_constr f acc body
  | CLetIn (_, e1, e2_opt, e3) ->
    let acc = fold_constr f acc e1 in
    let acc = walk_opt acc e2_opt in
    fold_constr f acc e3
  | CAppExpl (_, args) -> walk acc args
  | CApp (fn, args) ->
    let acc = fold_constr f acc fn in
    walk acc (List.map fst args)
  | CProj (_, _, args, e) ->
    let acc = walk acc (List.map fst args) in
    fold_constr f acc e
  | CRecord fields -> walk acc (List.map snd fields)
  | CCases (_style, ret, scrutinees, branches) ->
    let acc = walk_opt acc ret in
    let acc = walk acc (List.map (fun (e, _, _) -> e) scrutinees) in
    walk_branches acc branches
  | CLetTuple (_, _, e1, e2) ->
    let acc = fold_constr f acc e1 in
    fold_constr f acc e2
  | CIf (cond, (_, ret_opt), then_br, else_br) ->
    let acc = fold_constr f acc cond in
    let acc = walk_opt acc ret_opt in
    let acc = fold_constr f acc then_br in
    fold_constr f acc else_br
  | CCast (e1, _, e2) ->
    let acc = fold_constr f acc e1 in
    fold_constr f acc e2
  | CGeneralization (_, e) -> fold_constr f acc e
  | CDelimiters (_, _, e) -> fold_constr f acc e
  | CArray (_, elems, _, default) ->
    let acc = walk acc (Array.to_list elems) in
    fold_constr f acc default
