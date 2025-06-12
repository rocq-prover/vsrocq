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
open Types
open Protocol
open Protocol.LspWrapper

module SM = Map.Make (Stateid)

let Log log = Log.mk_log "execOverview"

let cut_overview id {prepared; processing; processed} document =
  let range = Document.range_of_id_with_blank_space document id in
  (* let range = match task with
  | PDelegate { terminator_id } -> Document.range_of_id_with_blank_space document terminator_id
  | PSkip { id } | PExec { id } | PQuery { id } | PBlock { id } ->
    Document.range_of_id_with_blank_space document id
  in *)
  let prepared = RangeList.cut_from_range range prepared in
  let processing = RangeList.cut_from_range range processing in
  {prepared; processing; processed}

let update_processed_success id {prepared; processing; processed} document =
  let range = Document.range_of_id_with_blank_space document id in
  let processed = RangeList.insert_or_merge_range range processed in
  let processing = RangeList.remove_or_truncate_range range processing in
  let prepared = RangeList.remove_or_truncate_range range prepared in
  {prepared; processing; processed}

let update_processed_error   id {prepared; processing; processed} document =
  let range = Document.range_of_id_with_blank_space document id in
  let processing = RangeList.remove_or_truncate_range range processing in
  let prepared = RangeList.remove_or_truncate_range range prepared in
  {prepared; processing; processed}


(* let update_processed id state document =
  let range = Document.range_of_id_with_blank_space document id in
  match SM.find id state.of_sentence with
  | (s, _) ->
    begin match s with
    | Done s -> 
      let overview = update_processed_as_Done s range state.overview in
      {state with overview}
    | _ -> assert false (* delegated sentences born as such, cannot become it later *)
    end
  | exception Not_found ->
    log (fun () -> "Trying to get overview with non-existing state id " ^ Stateid.to_string id);
    state *)

let update_prepared id document ({prepared} as overview) =
  (* match task with
  | PDelegate { opener_id; terminator_id; tasks } ->
    let proof_opener_id = id_of_first_task ~default:opener_id tasks in
    let proof_closer_id = id_of_last_task ~default:terminator_id tasks in
    let proof_begin_range = Document.range_of_id_with_blank_space document proof_opener_id in
    let proof_end_range = Document.range_of_id_with_blank_space document proof_closer_id in
    let range = Range.create ~end_:proof_end_range.end_ ~start:proof_begin_range.start in
    (* When a job is delegated we shouldn't merge ranges (to get the proper progress report) *)
    let prepared = List.append prepared [ range ] in
    let overview = {state.overview with prepared} in
    {state with overview}
  | PSkip { id } | PExec { id } | PQuery { id } | PBlock { id } -> *)
    let range = Document.range_of_id_with_blank_space document id in
    let prepared = RangeList.insert_or_merge_range range prepared in
    {overview with prepared}
    

let build_prepared_overview sentence_ids overview document =
  List.fold_right (fun id st -> update_prepared id document st) sentence_ids overview

let build_processed_overview ~processed_success ~processed_error overview document =
  overview
  |> List.fold_right (fun id st -> update_processed_success id st document) processed_success
  |> List.fold_right (fun id st -> update_processed_error id st document) processed_error

let reset_overview ~processed_success ~processed_error ~todo document =
  let overview = {processed=[]; prepared=[]; processing=[]} in
  let overview = build_processed_overview ~processed_success ~processed_error overview document in
  build_prepared_overview todo overview document

let prepare_overview overview prepared = {overview with prepared}

let shift_overview {processed; processing; prepared} ~before ~after ~start ~offset =
  let shift_loc loc_start loc_end =
    if loc_start >= start then (loc_start + offset, loc_end + offset)
    else if loc_end > start then (loc_start, loc_end + offset)
    else (loc_start, loc_end)
  in
  let shift_range range =
    let r_start = RawDocument.loc_of_position before range.Range.start in
    let r_stop = RawDocument.loc_of_position before range.Range.end_ in
    let r_start', r_stop' = shift_loc r_start r_stop in
    Range.create ~start:(RawDocument.position_of_loc after r_start') ~end_:(RawDocument.position_of_loc after r_stop')
  in
  let processed = CList.Smart.map shift_range processed in
  let processing = CList.Smart.map shift_range processing in
  let prepared = CList.Smart.map shift_range prepared in
  {processed; processing; prepared}

let print overview =
  let {processing; processed; prepared } = overview in
  log (fun () -> "--------- Prepared ranges ---------");
  List.iter (fun r -> log (fun () -> Range.to_string r)) prepared;
  log (fun () -> "-------------------------------------");
  log (fun () -> "--------- Processing ranges ---------");
  List.iter (fun r -> log (fun () -> Range.to_string r)) processing;
  log (fun () -> "-------------------------------------");
  log (fun () -> "--------- Processed ranges ---------");
  List.iter (fun r -> log (fun () -> Range.to_string r)) processed;
  log (fun () -> "-------------------------------------")

  
let overview_until_range {processed; processing; prepared} range =
  let find_final_range l = List.find_opt (fun (r: Range.t) -> Range.included ~in_:r range) l in
  let final_range = find_final_range processed  in
  match final_range with
  | None ->
    let final_range = find_final_range processing in
    begin match final_range with
    | None -> { processed; processing; prepared }
    | Some { start } ->
      let processing = (List.filter (fun (r: Range.t) -> not @@ Range.included ~in_:r range) processing) in
      let processing = List.append processing [Range.create ~start:start ~end_:range.end_] in
      {processing; processed; prepared}
    end
  | Some { start } ->
    let processed = (List.filter (fun (r: Range.t) -> (not @@ Range.included ~in_:r range) && (Position.compare r.start range.end_ <= 0)) processed) in
    let processed = List.append processed [Range.create ~start:start ~end_:range.end_] in
    print {processing; processed;prepared};
    { processing; processed; prepared }
  
  