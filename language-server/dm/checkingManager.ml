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

open Protocol
open Protocol.LspWrapper
open Protocol.ExtProtocol
open Protocol.Printing
open Types

type settings = {
  block_on_first_error : bool;
  check_mode : Protocol.Settings.Mode.t;
  diff_mode : Protocol.Settings.Goals.Diff.Mode.t;
  pp_mode : Protocol.Settings.Goals.PrettyPrint.t;
  point_interp_mode:Protocol.Settings.PointInterpretationMode.t;
}

let settings : settings ref = ref {
  check_mode = Settings.Mode.Manual;
  diff_mode = Settings.Goals.Diff.Mode.Off;
  pp_mode = Settings.Goals.PrettyPrint.Pp;
  point_interp_mode = Settings.PointInterpretationMode.Cursor;
  block_on_first_error = true;
}

let set_options s = settings := s

let (Log log) = Log.mk_log "checkingManager"

type interp_target = Next | Previous | Point of Position.t * Settings.PointInterpretationMode.t | End

let show_interp_target = function
  | End -> "End"
  | Next -> "Next"
  | Previous -> "Previous"
  | Point (p, _) -> Position.to_string p

type event =
  | Execute of {
      (* we split the computation to help interruptibility *)
      id : Types.sentence_id; (* sentence of interest *)
      vst_for_next_task : Vernacstate.t;
          (* the state to be used for the next
        todo, it is not necessarily the state of the last sentence, since it
        may have failed and this is a surrogate used for error resiliancy *)
      task : ExecutionManager.prepared_task;
      tasks : ExecutionManager.prepared_task list;
      started : float; (* time *)
    }
  | ExecutePromise of {
      id : Types.sentence_id;
      started : float;
      result : ExecutionManager.execution_result_;
      task : ExecutionManager.prepared_task;
      tasks : ExecutionManager.prepared_task list;
      block : bool;
      proof_view_event : event Sel.Event.t list;
    }
  | ExecutionManagerEvent of ExecutionManager.event
  | InterpretTo of Settings.Mode.t * interp_target
  | Observe of Types.sentence_id
  | SendBlockOnError of Types.sentence_id
  | SendMoveCursor of Range.t
  | SendProofView of Types.sentence_id option

let pp_event fmt = function
  | Execute { id; started; _ } ->
      let time = Unix.gettimeofday () -. started in
      Stdlib.Format.fprintf fmt "ExecuteToLoc %d (started %2.3f ago)" (Stateid.to_int id) time
  | ExecutionManagerEvent _ -> Stdlib.Format.fprintf fmt "ExecutionManagerEvent"
  | InterpretTo (_mode, tgt) -> Stdlib.Format.fprintf fmt "InterpretTo %s" (show_interp_target tgt)
  | Observe id -> Stdlib.Format.fprintf fmt "Observe %d" (Stateid.to_int id)
  | SendBlockOnError id -> Stdlib.Format.fprintf fmt "SendBlockOnError %d" @@ Stateid.to_int id
  | SendMoveCursor range -> Stdlib.Format.fprintf fmt "SendBlockOnError %s" @@ Range.to_string range
  | SendProofView id_opt -> Stdlib.Format.fprintf fmt "SendProofView %s" @@ Option.cata Stateid.to_string "None" id_opt
  | ExecutePromise { id } ->
      Stdlib.Format.fprintf fmt "ExecutePromise %d" (Stateid.to_int id)

let inject_em_event x = Sel.Event.map (fun e -> ExecutionManagerEvent e) x
let inject_em_events events = List.map inject_em_event events
let mk_interp_to_event mode tgt = [ Sel.now ~priority:PriorityManager.interp_to (InterpretTo (mode, tgt)) ]
let mk_observe_event id = Sel.now ~priority:PriorityManager.execution (Observe id)

let mk_move_cursor_event id =
  let priority = PriorityManager.move_cursor in
  Sel.now ~priority @@ SendMoveCursor id

let mk_proof_view_event id = Sel.now ~priority:PriorityManager.proof_view (SendProofView (Some id))
let mk_proof_view_event_empty = Sel.now ~priority:PriorityManager.proof_view (SendProofView None)

let mk_execution_event background event =
  let priority = if background then None else Some PriorityManager.execution in
  Sel.now ?priority event

let mk_execution_promise_event background id started proof_view_event p k task tasks block =
  let priority = if background then None else Some (-100) in
  Sel.On.promise ?priority p (fun result -> ExecutePromise { result = k result; id; started; task; tasks; block; proof_view_event; })

let mk_block_on_error_event last_range error_id background =
  let update_goal_view = [ mk_proof_view_event error_id ] in
  if background then update_goal_view
  else
    let red_flash = [ Sel.now ~priority:PriorityManager.move_cursor @@ SendBlockOnError error_id ] in
    let move_cursor = match last_range with Some last_range -> [ mk_move_cursor_event last_range ] | None -> [] in
    red_flash @ move_cursor @ update_goal_view

type observe_id = Id of Types.sentence_id | Top

type state = {
  overview : exec_overview;
  observe_id : observe_id;
  exec_event_cancel_handle : Sel.Event.cancellation_handle option;
  execution_state : ExecutionManager.state;
}

let init ~feedback_pipe vs =
  {
    overview = empty_overview;
    observe_id = Top;
    exec_event_cancel_handle = None;
    execution_state = ExecutionManager.init ~feedback_pipe vs;
  }

let reset st vs ~feedback_pipe =
  ExecutionManager.destroy st.execution_state;
  init vs ~feedback_pipe

let get_observe_id { observe_id } = match observe_id with Top -> None | Id x -> Some x
let reset_to_top st = { st with observe_id = Top }

let cut_overview task state document =
  let range =
    match ExecutionManager.view_task task with
    | `Remote (_, _, _, terminator_id) -> Document.range_of_id_with_blank_space document terminator_id
    | `Local id -> Document.range_of_id_with_blank_space document id
  in
  let { prepared; processing; processed } = state.overview in
  let prepared = RangeList.cut_from_range range prepared in
  let processing = RangeList.cut_from_range range processing in
  let overview = { prepared; processing; processed } in
  { state with overview }

let update_processed_as_Done s range overview =
  let { prepared; processing; processed } = overview in
  match s with
  | Success _ ->
      let processed = RangeList.insert_or_merge_range range processed in
      let processing = RangeList.remove_or_truncate_range range processing in
      let prepared = RangeList.remove_or_truncate_range range prepared in
      { prepared; processing; processed }
  | Failure _ ->
      let processing = RangeList.remove_or_truncate_range range processing in
      let prepared = RangeList.remove_or_truncate_range range prepared in
      { prepared; processing; processed }

let update_processed id state document =
  let range = Document.range_of_id_with_blank_space document id in
  match Document.get_sentence document id with
  | Some { checked } -> begin
      match checked with
      | Some s ->
          let overview = update_processed_as_Done s range state.overview in
          { state with overview }
      | None ->
          let overview = update_processed_as_Done (Success None) range state.overview in
          { state with overview }
      (* FIXME: the document is not updated yet *)
      (* assert false delegated sentences born as such, cannot become it later *)
    end
  | None ->
      log (fun () -> "Trying to get overview with non-existing state id " ^ Stateid.to_string id);
      state

let update_processing task state document =
  let { processing; prepared } = state.overview in
  match ExecutionManager.view_task task with
  | `Remote (_, first_step, last_step, _) ->
      let proof_begin_range = Document.range_of_id_with_blank_space document first_step in
      let proof_end_range = Document.range_of_id_with_blank_space document last_step in
      let range = Range.create ~end_:proof_end_range.end_ ~start:proof_begin_range.start in
      (* When a job is delegated we shouldn't merge ranges (to get the proper progress report) *)
      let processing = List.append processing [ range ] in
      let prepared = RangeList.remove_or_truncate_range range prepared in
      let overview = { state.overview with prepared; processing } in
      { state with overview }
  | `Local id ->
      let range = Document.range_of_id_with_blank_space document id in
      let processing = RangeList.insert_or_merge_range range processing in
      let prepared = RangeList.remove_or_truncate_range range prepared in
      let overview = { state.overview with processing; prepared } in
      { state with overview }

let update_prepared task document state =
  let { prepared } = state.overview in
  match ExecutionManager.view_task task with
  | `Remote (_, first_step, last_step, _) ->
      let proof_begin_range = Document.range_of_id_with_blank_space document first_step in
      let proof_end_range = Document.range_of_id_with_blank_space document last_step in
      let range = Range.create ~end_:proof_end_range.end_ ~start:proof_begin_range.start in
      (* When a job is delegated we shouldn't merge ranges (to get the proper progress report) *)
      let prepared = List.append prepared [ range ] in
      let overview = { state.overview with prepared } in
      { state with overview }
  | `Local id ->
      let range = Document.range_of_id_with_blank_space document id in
      let prepared = RangeList.insert_or_merge_range range prepared in
      let overview = { state.overview with prepared } in
      { state with overview }

let update_overview task tasks state document =
  let state =
    match ExecutionManager.view_task task with
    | `Remote (_, _, _, terminator_id) ->
        let range = Document.range_of_id_with_blank_space document terminator_id in
        let { prepared } = state.overview in
        let prepared = RangeList.remove_or_truncate_range range prepared in
        let overview = update_processed_as_Done (Success None) range state.overview in
        let overview = { overview with prepared } in
        { state with overview }
    | `Local id -> update_processed id state document
  in
  match tasks with [] -> state | next :: _ -> update_processing next state document

let build_processed_overview state document =
  let sentences = Document.sentences document in
  let sentence_ids = List.map (fun (s : Document.sentence) -> s.id) sentences in
  List.fold_right (fun id st -> update_processed id st document) sentence_ids state

let reset_overview st document unchanged_id =
  let overview = { processed = []; prepared = []; processing = [] } in
  let st = build_processed_overview { st with overview } document in
  let observe_id =
    match (unchanged_id, st.observe_id) with
    | None, Id _ -> Top
    | _, Top -> Top
    | Some id, Id id' -> if Document.is_sentence_above document id id' then Id id else st.observe_id
  in
  { st with observe_id }

let overview st = st.overview

let print_exec_overview overview =
  let { processing; processed; prepared } = overview in
  log (fun () -> "--------- Prepared ranges ---------");
  List.iter (fun r -> log (fun () -> Range.to_string r)) prepared;
  log (fun () -> "-------------------------------------");
  log (fun () -> "--------- Processing ranges ---------");
  List.iter (fun r -> log (fun () -> Range.to_string r)) processing;
  log (fun () -> "-------------------------------------");
  log (fun () -> "--------- Processed ranges ---------");
  List.iter (fun r -> log (fun () -> Range.to_string r)) processed;
  log (fun () -> "-------------------------------------")

let overview_until_range st range =
  let find_final_range l = List.find_opt (fun (r : Range.t) -> Range.included ~in_:r range) l in
  let { processed; processing; prepared } = st.overview in
  let final_range = find_final_range processed in
  match final_range with
  | None ->
      let final_range = find_final_range processing in
      begin match final_range with
      | None -> { processed; processing; prepared }
      | Some { start } ->
          let processing = List.filter (fun (r : Range.t) -> not @@ Range.included ~in_:r range) processing in
          let processing = List.append processing [ Range.create ~start ~end_:range.end_ ] in
          { processing; processed; prepared }
      end
  | Some { start } ->
      let processed =
        List.filter
          (fun (r : Range.t) -> (not @@ Range.included ~in_:r range) && Position.compare r.start range.end_ <= 0)
          processed
      in
      let processed = List.append processed [ Range.create ~start ~end_:range.end_ ] in
      print_exec_overview { processing; processed; prepared };
      { processing; processed; prepared }

let rec build_prepared_overview document tasks state =
  match tasks with [] -> state | task :: l -> build_prepared_overview document l (update_prepared task document state)

let shift_overview st ~before ~after ~start ~offset =
  let before = Document.raw_document before in
  let after = Document.raw_document after in
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
  let processed = CList.Smart.map shift_range st.overview.processed in
  let processing = CList.Smart.map shift_range st.overview.processing in
  let prepared = CList.Smart.map shift_range st.overview.prepared in
  let overview = { processed; processing; prepared } in
  { st with overview }

let executed_ranges document st =
  let mode = !settings.check_mode in
  match (st.observe_id, mode) with
  | _, Settings.Mode.Continuous -> overview st
  | Top, Settings.Mode.Manual -> empty_overview
  | Id id, Settings.Mode.Manual ->
      let range = Document.range_of_id document id in
      overview_until_range st range

let observe_id_range document st =
  let doc = Document.raw_document document in
  match st.observe_id with
  | Top -> None
  | Id id -> (
      match Document.get_sentence document id with
      | None -> failwith "observe_id does not exist"
      | Some { start; stop } ->
          let start = RawDocument.position_of_loc doc start in
          let end_ = RawDocument.position_of_loc doc stop in
          let range = Range.{ start; end_ } in
          Some range)

let observe_before_error document st error_id =
  match Document.get_sentence document error_id with
  | None -> st
  | Some { start } -> (
      match Document.find_sentence_before document start with
      | None -> { st with observe_id = Top }
      | Some { id } -> { st with observe_id = Id id })

let state_before_error document state error_id loc =
  match Document.get_sentence document error_id with
  | None -> (state, None)
  | Some _ ->
      let errored_sentence_range = Document.range_of_id_with_blank_space document error_id in
      let error_range =
        Option.cata
          (fun loc -> RawDocument.range_of_loc (Document.raw_document document) loc)
          errored_sentence_range loc
      in
      let state = observe_before_error document state error_id in
      (state, Some error_range)

let observe document st ~background id ~block_on_first_error : state * event Sel.Event.t list =
  match Document.get_sentence document id with
  | None -> (st, [] (* TODO error? *))
  | Some { id } -> (
      Option.iter Sel.Event.cancel st.exec_event_cancel_handle;
      let vst_for_next_task, tasks, execution_state, error_id =
        ExecutionManager.build_tasks_for document (Document.schedule document) st.execution_state id
      in
      let st = { st with execution_state } in
      match tasks with
      | task :: tasks as all_tasks -> begin
          match (error_id, block_on_first_error) with
          | None, _ | _, false ->
              let st = build_prepared_overview document all_tasks st in
              let event =
                mk_execution_event background
                  (Execute { id; vst_for_next_task; task; tasks; started = Unix.gettimeofday () })
              in
              let exec_event_cancel_handle = Some (Sel.Event.get_cancellation_handle event) in
              ({ st with exec_event_cancel_handle }, [ event ])
          | Some (error_id, loc), true ->
              let st, error_range = state_before_error document st error_id loc in
              let events = mk_block_on_error_event error_range error_id background in
              (st, events)
        end
      | [] -> (st, []))

let interpret_to document st id check_mode =
  let observe_id = Id id in
  let st = { st with observe_id } in
  match check_mode with
  | Settings.Mode.Manual ->
      let event = mk_observe_event id in
      let pv_event = mk_proof_view_event id in
      (st, [ event ] @ [ pv_event ])
  | Settings.Mode.Continuous -> (
      match Document.get_sentence document id with
      | Some { checked = Some (Success (Some _) | Failure (_, _, Some _)) } ->
          (* we have the vernac state *)
          (st, [ mk_proof_view_event id ])
      | _ -> (st, []))

let interpret_to_next_position document st pos check_mode =
  match Document.find_sentence_after_pos document pos with
  | None -> (st, []) (* document is empty *)
  | Some { id } ->
      let st, events = interpret_to document st id check_mode in
      (st, events)

let real_interpret_to_position document st pos check_mode ~point_interp_mode =
  match point_interp_mode with
  | Settings.PointInterpretationMode.Cursor -> begin
      match Document.find_sentence_before_pos document pos with
      | None -> (st, []) (* document is empty *)
      | Some { id } -> interpret_to document st id check_mode
    end
  | Settings.PointInterpretationMode.NextCommand -> interpret_to_next_position document st pos check_mode

let real_interpret_to_previous document st check_mode =
  match st.observe_id with
  | Top -> (st, [])
  | Id id -> (
      match Document.get_sentence document id with
      | None -> (st, []) (* TODO error? *)
      | Some { start } -> (
          match Document.find_sentence_before document start with
          | None ->
              let range = Range.top () in
              ({ st with observe_id = Top }, [ mk_move_cursor_event range; mk_proof_view_event_empty ])
          | Some { id } ->
              let st, events = interpret_to document st id check_mode in
              let range = Document.range_of_id document id in
              let mv_cursor = mk_move_cursor_event range in
              (st, [ mv_cursor ] @ events)))

let real_interpret_to_next document st check_mode =
  match st.observe_id with
  | Top -> begin
      match Document.get_first_sentence document with
      | None -> (st, [] (*The document is empty*))
      | Some { id } ->
          let st, events = interpret_to document st id check_mode in
          let range = Document.range_of_id document id in
          let mv_cursor = mk_move_cursor_event range in
          (st, [ mv_cursor ] @ events)
    end
  | Id id -> (
      match Document.get_sentence document id with
      | None -> (st, [] (* TODO error? *))
      | Some { stop } -> (
          match Document.find_sentence_after document (stop + 1) with
          | None -> (st, [])
          | Some { id } ->
              let st, events = interpret_to document st id check_mode in
              let range = Document.range_of_id document id in
              let mv_cursor = mk_move_cursor_event range in
              (st, [ mv_cursor ] @ events)))

let real_interpret_to_end document st check_mode =
  match Document.get_last_sentence document with
  | None -> (st, [])
  | Some { id } ->
      log (fun () -> "interpret_to_end id = " ^ Stateid.to_string id);
      interpret_to document st id check_mode

let interpret_to_end () = mk_interp_to_event !settings.check_mode End
let interpret_to_next () = mk_interp_to_event !settings.check_mode Next
let interpret_to_previous () = mk_interp_to_event !settings.check_mode Previous
let interpret_to_position p = mk_interp_to_event !settings.check_mode (Point (p, !settings.point_interp_mode))
let invalidate st id = { st with execution_state = ExecutionManager.invalidate st.execution_state id }

let interpret_in_background document st =
  match Document.get_last_sentence document with
  | None -> (st, [])
  | Some { id } ->
      log (fun () -> "interpret_to_end id = " ^ Stateid.to_string id);
      observe document ~background:true st id ~block_on_first_error:!settings.block_on_first_error

let validate_document document st =
  if !settings.check_mode = Settings.Mode.Continuous then interpret_in_background document st else st, []

let execution_finished st id started =
  let time = Unix.gettimeofday () -. started in
  log (fun () -> Printf.sprintf "ExecuteToLoc %d ends after %2.3f" (Stateid.to_int id) time);
  (* We update the state to trigger a publication of diagnostics *)
  let update_view = true in
  let state = Some st in
  { state; events = []; update_view; notification = None }

let post_execute document st id started background proof_view_event task tasks block vst_for_next_task events exec_error = 
  let st, tasks, block_events =
    match (block, exec_error) with
    | false, _ | _, None ->
        let st = update_overview task tasks st document in
        (st, tasks, [])
    | true, Some (error_id, loc) ->
        let st = cut_overview task st document in
        let st, error_range = state_before_error document st error_id loc in
        (st, [], mk_block_on_error_event error_range error_id background)
  in
  match tasks with
  | [] -> execution_finished st id started
  | task :: tasks ->
      let event = mk_execution_event background (Execute { id; vst_for_next_task; task; tasks; started }) in
      let exec_event_cancel_handle = Some (Sel.Event.get_cancellation_handle event) in
      let state = Some { st with exec_event_cancel_handle } in
      let update_view = true in
      let events = proof_view_event @ inject_em_events events @ block_events @ [ event ] in
      { state; events; update_view; notification = None }

let execute document st id vst_for_next_task started task tasks background block =
  let time = Unix.gettimeofday () -. started in
  let proof_view_event =
    (*When in continuous mode we always check if we should update the goal view *)
    if background then begin
      match st.observe_id with
      | Top -> []
      | Id o_id ->
          let s_id = ExecutionManager.get_id_of_executed_task task in
          if o_id = s_id then [ mk_proof_view_event s_id ] else []
    end
    else []
  in
  match Document.get_sentence document id with
  | None ->
      log (fun () -> Printf.sprintf "ExecuteToLoc %d stops after %2.3f, sentences invalidated" (Stateid.to_int id) time);
      ([], { state = Some st; events = []; update_view = true; notification = None })
      (* Sentences have been invalidate, probably because the user edited while executing *)
  | Some _ ->
      log (fun () -> Printf.sprintf "ExecuteToLoc %d continues after %2.3f" (Stateid.to_int id) time);
      let execution_state, result =ExecutionManager.execute st.execution_state document vst_for_next_task task in
      let st = { st with execution_state } in
      match result with
      | Done { updates; vs = vst_for_next_task; events; exec_error } ->
        updates, post_execute document st id started background proof_view_event task tasks block vst_for_next_task events exec_error
      | WillDo(promise,k) ->
        [],{state=Some st; events=[mk_execution_promise_event background id started proof_view_event promise k task tasks block]; update_view=true; notification=None}

let execute_promise document st id started background proof_view_event task tasks block { ExecutionManager.updates; vs = vst_for_next_task; events; exec_error } =
  updates, post_execute document st id started background proof_view_event task tasks block vst_for_next_task events exec_error

let handle_execution_manager_event document st ev =
  let id, document_update, execution_state_update, events =
    ExecutionManager.handle_event document ev st.execution_state
  in
  let updates = match document_update with None -> [] | Some (id, v) -> [ (id, v) ] in
  let st =
    match (id, execution_state_update) with
    | Some id, Some execution_state ->
        let st = update_processed id st document in
        Some { st with execution_state }
    | Some id, None ->
        let st = update_processed id st document in
        Some st
    | _, _ -> Option.map (fun execution_state -> { st with execution_state }) execution_state_update
  in
  let update_view = true in
  (updates, { state = st; events = inject_em_events events; update_view; notification = None })

let vernac_state_of_sentence document id =
  Document.get_sentence document id |> fun x -> Option.bind x (fun x -> Utilities.get_vernac_state x.Document.checked)

let get_proof document st id =
  let previous_st id =
    let oid = fst @@ Scheduler.task_for_sentence (Document.schedule document) id in
    Option.bind oid (vernac_state_of_sentence document)
  in
  let observe_id = get_observe_id st in
  let oid = Option.append id observe_id in
  let ost = Option.bind oid (vernac_state_of_sentence document) in
  let previous = Option.bind oid previous_st in
  Option.bind ost (ProofState.get_proof ~previous !settings.diff_mode)

let get_string_proof document st id =
  let observe_id = get_observe_id st in
  let oid = Option.append id observe_id in
  let ost = Option.bind oid (vernac_state_of_sentence document) in
  Option.bind ost PpProofState.get_proof

let get_messages document id =
  let error = Document.error document id in
  let feedback = Document.feedback document id in
  let feedback =
    List.map (fun (lvl, _oloc, _, msg) -> (DiagnosticSeverity.of_feedback_level lvl, pp_of_rocqpp msg)) feedback
  in
  match error with Some (_oloc, msg, _) -> (DiagnosticSeverity.Error, pp_of_rocqpp msg) :: feedback | None -> feedback

let get_string_messages document id =
  let error = Document.error document id in
  let feedback = Document.feedback document id in
  let feedback =
    List.map (fun (lvl, _oloc, _, msg) -> (DiagnosticSeverity.of_feedback_level lvl, Pp.string_of_ppcmds msg)) feedback
  in
  match error with
  | Some (_oloc, msg, _) -> (DiagnosticSeverity.Error, Pp.string_of_ppcmds msg) :: feedback
  | None -> feedback

let handle_event ~uri document st ev =
  let { block_on_first_error; check_mode; pp_mode } = !settings in
  let background = check_mode = Settings.Mode.Continuous in
  match ev with
  | Execute { id; vst_for_next_task; started; task; tasks } ->
      execute document st id vst_for_next_task started task tasks background block_on_first_error
  | ExecutePromise { id; started; result; proof_view_event; task; tasks; block } ->
      execute_promise document st id started background proof_view_event task tasks block result
  | ExecutionManagerEvent ev -> handle_execution_manager_event document st ev
  | Observe id ->
      let state, events = observe document st id ~block_on_first_error ~background in
      ([], make_handled_event ~state ~update_view:true ~events ())
  | SendProofView (Some id) when Document.has_sentence document id ->
      let proof, pp_proof =
        match pp_mode with
        | Pp -> (get_proof document st (Some id), None)
        | String -> (None, get_string_proof document st (Some id))
      in
      let messages, pp_messages =
        match pp_mode with Pp -> (get_messages document id, []) | String -> ([], get_string_messages document id)
      in
      let range = Document.range_of_id document id in
      let params = Notification.Server.ProofViewParams.{ proof; messages; pp_proof; pp_messages; range } in
      let notification = Notification.Server.ProofView params in
      ([], make_handled_event ~state:st ~notification ~update_view:true ())
  | SendProofView _ ->
      let params =
        Notification.Server.ProofViewParams.
          { proof = None; pp_proof = None; messages = []; pp_messages = []; range = Range.top () }
      in
      let notification = Notification.Server.ProofView params in
      ([], make_handled_event ~state:st ~notification ~update_view:true ())
  | SendBlockOnError id ->
      let range = Document.range_of_id document id in
      let notification = Notification.Server.BlockOnError { uri; range } in
      ([], make_handled_event ~state:st ~notification ())
  | SendMoveCursor range ->
      let notification = Notification.Server.MoveCursor { uri; range } in
      ([], make_handled_event ~state:st ~notification ())
  | InterpretTo (mode, End) ->
      let state, events = real_interpret_to_end document st mode in
      ([], make_handled_event ~state ~events ())
  | InterpretTo (mode, Next) ->
      let state, events = real_interpret_to_next document st mode in
      ([], make_handled_event ~state ~events ())
  | InterpretTo (mode, Point (p, point_interp_mode)) ->
      let state, events = real_interpret_to_position document st p mode ~point_interp_mode in
      ([], make_handled_event ~state ~events ())
  | InterpretTo (mode, Previous) ->
      let state, events = real_interpret_to_previous document st mode in
      ([], make_handled_event ~state ~events ())

let interrupt_execution st =
  Option.iter Sel.Event.cancel st.exec_event_cancel_handle;
  ExecutionManager.interrupt_execution st.execution_state

module Internal = struct
  let is_remotely_executed st id = ExecutionManager.is_remotely_executed st.execution_state id
end
