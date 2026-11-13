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
open Util
open Printer
open Protocol.Printing
open Protocol.LspWrapper

(* Note: this queue is not very useful today, as we process results in the main
vsrocq process, which does not allow for real asynchronous processing of results. *)
let query_results_queue = Queue.create ()

let query_feedback : notification Sel.Event.t =
  Sel.On.queue query_results_queue (fun x -> QueryResultNotification x)

[%%if rocq = "8.18"]
open Vernacexpr
open Pp
(* TODO : remove these two functions when interp_search_restriction is 
  added in the comSearch.mli in Rocq (they're simply copied here for now) *)
let global_module qid =
    try Nametab.full_name_module qid
    with Not_found ->  
      CErrors.user_err ?loc:qid.CAst.loc
       (str "Module/Section " ++ Ppconstr.pr_qualid qid ++ str " not found.")
let interp_search_restriction = function
  | SearchOutside l -> (List.map global_module l, true)
  | SearchInside l -> (List.map global_module l, false)
let adapt_pr_search f r k e c = f r k e (Evd.from_env e) c
[%%else]
let interp_search_restriction = ComSearch.interp_search_restriction
let adapt_pr_search f = f
[%%endif]

let search_output_name_only () =
  match Goptions.get_option_value ["Search"; "Output"; "Name"; "Only"] with
  | Some read -> (match read () with Goptions.BoolValue b -> b | _ -> false)
  | None -> false

let interp_search ~id env sigma s r =
  let name_only = search_output_name_only () in
  let pr_search ref _kind env sigma c =
    let name = pp_of_rocqpp (pr_global ref) in
    let statement =
      if name_only then pp_of_rocqpp (Pp.mt ())
      else
        let open Impargs in
        let impls = implicits_of_global ref in
        let impargs = select_stronger_impargs impls in
        let impargs = List.map binding_kind_of_status impargs in
        pp_of_rocqpp (pr_ltype_env env sigma ~impargs c)
    in
    Queue.push { id; name; statement } query_results_queue
  in
  let r = interp_search_restriction r in
  (Search.search env sigma (List.map (ComSearch.interp_search_request env sigma) s) r |>
    Search.prioritize_search) (adapt_pr_search pr_search);
  [query_feedback]
