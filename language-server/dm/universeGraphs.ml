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

open Protocol.UniverseGraph

(* The universe graphs of [Show Universes] and [Print Universes]. The
   universe API of Rocq changes between versions, hence the many cases. *)

[%%if rocq = "8.18" || rocq = "8.19" || rocq = "8.20"]

let unsupported () =
  CErrors.user_err Pp.(str "The universe graph needs Rocq 9.0 or later.")

let local ~range_of_loc:_ _ = unsupported ()
let global ~subgraph:_ _ = unsupported ()

[%%else]

module Level = Univ.Level

let string_of_pp pp = Pp.string_of_ppcmds pp

[%%if rocq = "9.0" || rocq = "9.1"]
let fold_constraints f csts acc =
  Univ.Constraints.fold (fun (l, k, r) acc ->
    let k = match k with Univ.Lt -> "<" | Univ.Le -> "<=" | Univ.Eq -> "=" in
    f (l, k, r) acc) csts acc
let universe_context_set = UState.context_set
[%%else]
let fold_constraints f csts acc =
  Univ.UnivConstraints.fold (fun (l, k, r) acc ->
    let k = match k with
      | Univ.UnivConstraint.Lt -> "<" | Univ.UnivConstraint.Le -> "<=" | Univ.UnivConstraint.Eq -> "=" in
    f (l, k, r) acc) csts acc
let universe_context_set = UState.universe_context_set
[%%endif]

[%%if rocq = "9.0" || rocq = "9.1" || rocq = "9.2"]
let minimize_universes Proof.{ sigma; _ } = Evd.minimize_universes sigma
let qualities _ = None
[%%else]
let minimize_universes Proof.{ sigma; poly; _ } = Evd.minimize_universes ~poly sigma

(* The edges [q1 -> q2] such that q1 eliminates into q2 *)
let qualities uctx =
  let g = UState.elim_graph uctx in
  let qs = Sorts.Quality.Set.elements (QGraph.domain g) in
  let name q = string_of_pp (Sorts.Quality.pr (UState.quality_printer uctx) q) in
  let eliminations =
    List.concat_map (fun q1 ->
      List.filter_map (fun q2 ->
        if not (Sorts.Quality.equal q1 q2) && QGraph.eliminates_to g q1 q2
        then Some { from_quality = name q1; to_quality = name q2 } else None) qs) qs
  in
  Some { qualities = List.map name qs; eliminations }
[%%endif]

[%%if rocq = "9.0" || rocq = "9.1" || rocq = "9.2" || rocq = "9.3"]
let loc_of_level _ _ = None
let subgraph _ _ =
  CErrors.user_err Pp.(str "Restricting the universe graph needs a later version of Rocq.")
[%%else]
let loc_of_level = UState.loc_of_level

(* Names as in [Print Universes Subgraph]: a raw universe ends with a number *)
let subgraph names g =
  let parse s =
    match List.rev (String.split_on_char '.' s) with
    | n :: _ :: _ when Option.has_some (int_of_string_opt n) -> Vernacexpr.RawUniv (CAst.make s)
    | _ -> Vernacexpr.NamedUniv (Libnames.qualid_of_string s)
  in
  Vernacentries.universe_subgraph (List.map parse names) g
[%%endif]

let constraint_ (l, kind, r) = { source = Level.to_string l; kind; target = Level.to_string r }

(* The graph of the constraints [csts], with the [levels] and those the
   constraints mention *)
let make_graph level levels csts =
  let levels = fold_constraints (fun (l, _, r) acc -> Level.Set.add l (Level.Set.add r acc)) csts levels in
  { levels = List.map level (Level.Set.elements levels);
    constraints = List.rev (fold_constraints (fun c acc -> constraint_ c :: acc) csts []) }

let local_graph ~range_of_loc sigma =
  let uctx = Evd.ustate sigma in
  let level l = {
    id = Level.to_string l;
    name = string_of_pp (UState.pr_uctx_level uctx l);
    flexible = UnivFlex.mem l (UState.subst uctx);
    algebraic = UState.is_algebraic l uctx;
    range = Option.bind (loc_of_level uctx l) range_of_loc;
  } in
  let levels, csts = universe_context_set uctx in
  make_graph level levels csts

(* The universes of the proof in [vs], as [Show Universes] *)
let local ~range_of_loc (vs : Vernacstate.t) =
  Vernacstate.unfreeze_full_state vs;
  match vs.interp.lemmas with
  | None -> CErrors.user_err Pp.(str "No proof in progress.")
  | Some lemmas ->
    let data = Vernacstate.LemmaStack.with_top lemmas ~f:(fun p -> Proof.data (Declare.Proof.get p)) in
    let sigma = data.Proof.sigma in
    { graph = local_graph ~range_of_loc sigma;
      normalized = Some (local_graph ~range_of_loc (minimize_universes data));
      qualities = qualities (Evd.ustate sigma) }

(* The global universe graph in [vs], or its restriction to the universes
   [subgraph], as [Print Universes] *)
let global ~subgraph:names (vs : Vernacstate.t) =
  Vernacstate.unfreeze_full_state vs;
  let g = Global.universes () in
  let g = match names with None | Some [] -> g | Some names -> subgraph names g in
  let csts, classes = UGraph.constraints_of_universes g in
  let level l = {
    id = Level.to_string l;
    name = string_of_pp (UnivNames.pr_level_with_global_universes l);
    flexible = false;
    algebraic = false;
    range = None;
  } in
  let graph = make_graph level (UGraph.domain g) csts in
  (* Each class of equal universes, as a chain of equalities *)
  let equalities = List.concat_map (fun cls ->
    match Level.Set.elements cls with
    | [] -> []
    | l :: ls ->
      snd (List.fold_left (fun (prev, acc) l -> l, constraint_ (prev, "=", l) :: acc) (l, []) ls))
    classes
  in
  { graph = { graph with constraints = graph.constraints @ equalities };
    normalized = None;
    qualities = None }

[%%endif]
