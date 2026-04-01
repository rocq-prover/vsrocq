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

open Protocol
open Scheduler
open Types

let Log log = Log.mk_log "executionManager"

let () = Memprof_limits.start_memprof_limits ()

let success vernac_st = Success (Some vernac_st)
let error loc qf msg vernac_st = Failure ((loc,msg), qf, (Some vernac_st))
let error_no_resiliency loc qf msg = Failure ((loc,msg), qf, None)

type errored_sentence = (sentence_id * Loc.t option) option

module SM = Map.Make (Stateid)

type delegation_info = { 
  job_handle : DelegationManager.job_handle;
  on_completion : (sentence_checking_result -> unit) option;
}

type delegation_mode =
  | CheckProofsInMaster
  | SkipProofs
  | DelegateProofsToWorkers of { number_of_workers : int }

type options = {
  delegation_mode : delegation_mode;
  completion_options : Settings.Completion.t;
  enableDiagnostics : bool
}

let default_options = {
  delegation_mode = CheckProofsInMaster;
  completion_options = {
    enable = false;
    algorithm = StructuredSplitUnification;
    unificationLimit = 100;
    atomicFactor = 5.;
    sizeFactor = 5.
  };
  enableDiagnostics = true;
}



type delegated_task = { 
  terminator_id: sentence_id;
  opener_id: sentence_id;
  proof_using: Vernacexpr.section_subset_expr;
  last_step_id: sentence_id option; (* only for setting a proof remotely *)
  tasks: executable_sentence list;
}

type prepared_task =
  | PSkip of { id: sentence_id; error: Pp.t option }
  | PBlock of { id: sentence_id; synterp : Vernacstate.Synterp.t; error: Pp.t Loc.located }
  | PExec of executable_sentence
  | PQuery of executable_sentence
  | PDelegate of delegated_task

module ProofJob = struct
  type update_request =
    | UpdateExecStatus of sentence_id * sentence_checking_result
    | AppendFeedback of Feedback.route_id * Types.sentence_id * (Feedback.level * Loc.t option * Quickfix.t list * Pp.t)
  let appendFeedback (rid,sid) fb = AppendFeedback(rid,sid,fb)

  type t = {
    tasks : executable_sentence list;
    initial_vernac_state : Vernacstate.t;
    doc_id : int;
    terminator_id : sentence_id;
  }
  let name = "proof"
  let binary_name = "vsrocqtop_proof_worker.opt"
  let initial_pool_size = 1

end

type state = {
  initial : Vernacstate.t;
  delegations : delegation_info SM.t;
  feedback_pipe : feedback_pipe; (* for relying stuff from the workers *)
  (* Why is this imperative? *)
  jobs : (DelegationManager.job_handle * Sel.Event.cancellation_handle * ProofJob.t) Queue.t;
}

let get_id_of_executed_task task =
  match task with
  | PSkip {id} -> id
  | PBlock {id} -> id
  | PExec {id} -> id
  | PQuery {id} -> id
  | PDelegate {terminator_id} -> terminator_id

let options = ref default_options

let set_options o = options := o
let set_default_options () = options := default_options
let is_diagnostics_enabled () = !options.enableDiagnostics

let get_options () = !options


module ProofWorker = DelegationManager.MakeWorker(ProofJob)

type event =
  | ProofWorkerEvent of ProofWorker.delegation

type events = event Sel.Event.t list
let pr_event = function
  | ProofWorkerEvent event -> ProofWorker.pr_event event

let inject_proof_event = Sel.Event.map (fun x -> ProofWorkerEvent x)
let inject_proof_events st l =
  (st, List.map inject_proof_event l)

let interp_error_recovery strategy st : Vernacstate.t =
  match strategy with
  | RSkip -> st
  | RAdmitted ->
    let f = Declare.Proof.save_admitted in
    let open Vernacstate in (* shadows Declare *)
    let { Interp.lemmas; program; _ } = st.interp in
    match lemmas with
    | None -> (* if Lemma failed *)
        st
    | Some lemmas ->
        let proof = Vernacstate.LemmaStack.get_top lemmas in
        let pm = NeList.head program in
        let result = 
          try Ok(f ~pm ~proof)
          with e -> (* we also catch anomalies *)
          let e, info = Exninfo.capture e in
          Error (e, info)
        in
        match result with
        | Ok (pm) ->
          let lemmas = snd (Vernacstate.LemmaStack.pop lemmas) in
          let program = NeList.map_head (fun _ -> pm) program in
          Vernacstate.Declare.set (lemmas,program) [@ocaml.warning "-3"];
          let interp = Vernacstate.Interp.freeze_interp_state () in
          { st with interp }
        | Error (Sys.Break, _ as exn) ->
          Exninfo.iraise exn
        | Error(_,_) ->
          st

(* just a wrapper around vernac interp *)
let interp_ast ~doc_id ~state_id ~st ~error_recovery ast =
    Feedback.set_id_for_feedback doc_id state_id;
    ParTactic.set_id_for_feedback doc_id state_id;
    let result =
        try Ok(Vernacinterp.interp_entry ~st ast)
        with e -> (* we also catch anomalies *)
          let e, info = Exninfo.capture e in
          Error (e, info) in
    match result with
    | Ok (interp) ->
        let st = { st with interp } in
        st, success st
    | Error (e, info) ->
        let loc = Loc.get_loc info in
        let qf = Result.value ~default:[] @@ Quickfix.from_exception e in
        let msg = CErrors.iprint (e, info) in
        let status = error loc (Some qf) msg st in
        let st = interp_error_recovery error_recovery st in
        st, status

(* This adapts the Future API with our event model *)
[%%if rocq = "8.18"]
let definition_using e s ~fixnames:_ ~using ~terms =
  Proof_using.definition_using e s ~using ~terms
[%%elif rocq = "8.19"]
let definition_using = Proof_using.definition_using
[%%endif]

[%%if rocq = "8.18" || rocq = "8.19"]
let add_using proof proof_using lemmas =
      let env = Global.env () in
      let sigma, _ = Declare.Proof.get_current_context proof in
      let initial_goals pf = Proofview.initial_goals Proof.((data pf).entry) in
      let terms = List.map (fun (_,_,x) -> x) (initial_goals (Declare.Proof.get proof)) in
      let names = Vernacstate.LemmaStack.get_all_proof_names lemmas in
      let using = definition_using env sigma ~fixnames:names ~using:proof_using ~terms in
      let vars = Environ.named_context env in
      Names.Id.Set.iter (fun id ->
          if not (List.exists Util.(Context.Named.Declaration.get_id %> Names.Id.equal id) vars) then
            CErrors.user_err
              Pp.(str "Unknown variable: " ++ Names.Id.print id ++ str "."))
        using;
      let _, pstate = Declare.Proof.set_used_variables proof ~using in
      pstate
[%%else]
let add_using proof proof_using _ =
  Declare.Proof.set_proof_using proof proof_using |> snd
[%%endif]

let interp_qed_delayed ~proof_using ~state_id ~st =
  let lemmas = Option.get @@ st.Vernacstate.interp.lemmas in
  let f proof =
    let proof = add_using proof proof_using lemmas in
    let fix_exn = None in (* FIXME *)
    let f, assign = Future.create_delegate ~blocking:false ~name:"XX" fix_exn in
    Declare.Proof.close_future_proof ~feedback_id:state_id proof f, assign
  in
  let proof, assign = Vernacstate.LemmaStack.with_top lemmas ~f in
  let control = [] (* FIXME *) in
  let opaque = Vernacexpr.Opaque in
  let pending = CAst.make @@ Vernacexpr.Proved (opaque, None) in
  (*log fun () -> "calling interp_qed_delayed done";*)
  let interp = Vernacinterp.interp_qed_delayed_proof ~proof ~st ~control pending in
  (*log fun () -> "interp_qed_delayed done";*)
  let st = { st with interp } in
  st, success st, assign

let id_of_first_task ~default = function
  | [] -> default
  | { id } :: _ -> id

let id_of_last_task ~default l =
  id_of_first_task ~default (List.rev l)

let view_task = function
  | PSkip { id } | PExec { id } | PQuery { id } | PBlock { id } -> `Local id
  | PDelegate { opener_id; terminator_id; tasks } ->
      let first = id_of_first_task ~default:opener_id tasks in
      let last = id_of_last_task ~default:terminator_id tasks in
      `Remote(opener_id, first, last, terminator_id)


let init vernac_state ~feedback_pipe =
  {
    initial = vernac_state;
    delegations = SM.empty;
    feedback_pipe;
    jobs = Queue.create ();
  }

(* called by the forked child. Since the Feedback API is imperative, the
   feedback pipes have to be modified in place *)
let handle_event document event state =
  match event with
  | ProofWorkerEvent event ->
      let update, events = ProofWorker.handle_event event in
      let state, update, id =
        match update with
        | None -> None, None, None
        | Some (ProofJob.AppendFeedback(x,id,fb)) ->
            Queue.push (x,id,fb) state.feedback_pipe.sel_feedback_queue;
            None, None, None
        | Some (ProofJob.UpdateExecStatus(id,v)) ->
            match Document.get_sentence document id with
            | None -> None, None, None
            | Some { checked } ->
                match checked, SM.find_opt id state.delegations, v with
                | None, Some { on_completion }, _ ->
                    Option.default ignore on_completion v;
                    let state = { state with delegations = SM.remove id state.delegations } in
                    Some state, Some (id,v), Some id
                | Some (Success s), _, Failure (err,qf, _) ->
                    let state = { state with delegations = SM.remove id state.delegations } in
                    (* This only happens when a Qed closing a delegated proof
                      receives an updated by a worker saying that the proof is
                      not completed *)
                    Some state, Some (id, Failure (err,qf,s)), Some id
                | _ -> None, None, Some id
      in
      let state, events = inject_proof_events state events in
      id, update, state, events

let find_fulfilled_opt x document =
    let ss = Document.get_sentence x document in
    match ss with
    | Some { checked = x } -> x
    | None -> None


let exec_error_of_execution_status id v = match v with
  | Success _ -> None
  | Failure ((loc, _), _, _) -> Some (id, loc)

let get_vs_and_exec_error id document =
  match find_fulfilled_opt document id with
  | Some (Success (Some vs) as es) -> vs, exec_error_of_execution_status id es
  | Some (Failure (_,_,Some vs) as es) -> vs, exec_error_of_execution_status id es
  | _ -> CErrors.anomaly Pp.(str "get_vs_and_exec_error call should be protected with is_locally_executed")

let is_locally_executed document id =
  match find_fulfilled_opt id document with
  | Some (Success (Some _) | Failure (_,_,Some _)) -> true
  | _ -> false

let is_remotely_executed st id = SM.mem id st.delegations
  
(* TODO: kill all Delegated... *)
let destroy  { jobs } =
  Queue.iter (fun (h,c,_) -> DelegationManager.cancel_job h; Sel.Event.cancel c) jobs

let last_opt l = try Some (CList.last l).id with Failure _ -> None

let prepare_task task : prepared_task list =
  match task with
  | Skip { id; error } -> [PSkip { id; error }]
  | Block { id; synterp; error } -> [PBlock {id; synterp; error}]
  | Exec e -> [PExec e]
  | Query e -> [PQuery e]
  | OpaqueProof { terminator; opener_id; tasks; proof_using} ->
      match !options.delegation_mode with
      | DelegateProofsToWorkers _ ->
          log (fun () -> "delegating proofs to workers");
          let last_step_id = last_opt tasks in
          [PDelegate {terminator_id = terminator.id; opener_id; last_step_id; tasks; proof_using}]
      | CheckProofsInMaster ->
          log (fun () -> "running the proof in master as per config");
          List.map (fun x -> PExec x) tasks @ [PExec terminator]
      | SkipProofs ->
          log (fun () -> Printf.sprintf "skipping proof made of %d tasks" (List.length tasks));
          [PExec terminator]

let id_of_prepared_task = function
  | PSkip { id } -> id
  | PBlock { id } -> id
  | PExec ex -> ex.id
  | PQuery ex -> ex.id
  | PDelegate { terminator_id } -> terminator_id

let purge_state = function
  | Success _ -> Success None
  | Failure(e,_,_) -> Failure (e,None,None)

(* TODO move to proper place *)
let worker_execute ~doc_id ~send_back vs { id; ast; synterp; error_recovery } =
  let vs = { vs with Vernacstate.synterp } in
  log (fun () -> "worker interp " ^ Stateid.to_string id);
  let vs, v = interp_ast ~doc_id ~state_id:id ~st:vs ~error_recovery ast in
  send_back (ProofJob.UpdateExecStatus (id,purge_state v));
  vs

(* The execution of Qed for a non-delegated proof checks the proof is completed.
   When the proof is delegated this step is performed by the worker, which
   sends back an update on the Qed sentence in case the proof is unfinished *)
let worker_ensure_proof_is_over vs send_back terminator_id =
  let f = Declare.Proof.close_proof in
  let open Vernacstate in (* shadows Declare *)
  let { Interp.lemmas } = vs.interp in
  match lemmas with
  | None -> assert false
  | Some lemmas ->
      let proof = Vernacstate.LemmaStack.get_top lemmas in
      try let _ = f ~opaque:Vernacexpr.Opaque ~keep_body_ucst_separate:false proof in ()
      with e ->
        let e, info = Exninfo.capture e in
        let loc = Loc.get_loc info in
        let qf = Result.value ~default:[] @@ Quickfix.from_exception e in
        let msg = CErrors.iprint (e, info) in
        let status = error loc (Some qf) msg vs in
        send_back (ProofJob.UpdateExecStatus (terminator_id,status))

let worker_main { ProofJob.tasks; initial_vernac_state = vs; doc_id; terminator_id } ~send_back =
  try
    let vs = List.fold_left (worker_execute ~doc_id ~send_back) vs tasks in
    worker_ensure_proof_is_over vs send_back terminator_id;
    flush_all ();
    exit 0
  with e ->
    let e, info = Exninfo.capture e in
    let message = CErrors.iprint_no_report (e, info) in
    Feedback.msg_debug @@ Pp.str "======================= worker ===========================";
    Feedback.msg_debug message;
    Feedback.msg_debug @@ Pp.str "==========================================================";
    exit 1

type execution_result_ = {
  updates: (sentence_id * sentence_checking_result) list;
  vs: Vernacstate.t;
  events: events;
  exec_error: errored_sentence;
}
type internal = (Vernacstate.t * sentence_checking_result) interruptible_result
type execution_result =
  | Done of execution_result_
  | WillDo of internal Sel.Promise.t * (internal Sel.Promise.state -> execution_result_)

let interrupt_execution { feedback_pipe = { doc_id } } = ProverThread.interrupt ~doc_id

let thread_execute ~doc_id ~state_id ~st ~error_recovery ast =
  let promise = ProverThread.run ~doc_id (fun () -> 
    interp_ast ~doc_id ~state_id ~st ~error_recovery ast) in
  let promise_to_result p =
    match p with
    | Sel.Promise.Rejected e -> raise e (* bug in vsrocq *)
    | Sel.Promise.Fulfilled result ->
      match result with
      | Terminated (vs, v) ->
          let updates = [state_id, v] in
          let exec_error = exec_error_of_execution_status state_id v in
          { updates; vs; events = []; exec_error }
      | Aborted e -> Exninfo.iraise e (* bug in vsrocq *)
      | Interrupted ->
          let v = error_no_resiliency None None Pp.(str "Interrupted by the user") in
          let updates = [state_id, v] in
          let exec_error = exec_error_of_execution_status state_id v in
          { updates; vs = st; events = []; exec_error }
  in
  WillDo(promise,promise_to_result)

let execute st document vs task : state * execution_result =
  match task with
  | PBlock { id; synterp; error = err} ->
      let vs = { vs with Vernacstate.synterp } in
      let (loc, pp) = err in
      let v = error loc None pp vs in
      let parse_error = Some (id, loc) in
      let updates = [id, v] in
      st, Done {updates; vs; events = []; exec_error = parse_error }
  | PSkip { id; error = err } ->
      let v = match err with
        | None -> success vs
        | Some msg -> error None None msg vs
      in
      let updates = [id, v] in
      st, Done { updates; vs; events = []; exec_error = None }
  | PExec { id; ast; synterp; error_recovery } ->
      let vs = { vs with Vernacstate.synterp } in
      if is_locally_executed id document then
        let vs, exec_error = get_vs_and_exec_error id document in
        log (fun () -> Format.asprintf "skipping execution of already executed %s" (Stateid.to_string id));
        st, Done { updates = []; vs; events = []; exec_error }
      else
        st, thread_execute ~doc_id:st.feedback_pipe.doc_id ~state_id:id ~st:vs ~error_recovery ast
  | PQuery { id; ast; synterp; error_recovery } ->
      let vs = { vs with Vernacstate.synterp } in
      st, thread_execute ~doc_id:st.feedback_pipe.doc_id ~state_id:id ~st:vs ~error_recovery ast
  | PDelegate { terminator_id; opener_id; last_step_id; tasks; proof_using } ->
      match find_fulfilled_opt document opener_id with
      | Some (Success _) ->
        let job =  { ProofJob.tasks; initial_vernac_state = vs; doc_id = st.feedback_pipe.doc_id; terminator_id } in
        let job_handle = DelegationManager.mk_job_handle (0,terminator_id) in
        (* The proof was successfully opened *)
        let last_vs, _v, assign = interp_qed_delayed ~state_id:terminator_id ~proof_using ~st:vs in
        let complete_job status =
          try match status with
          | Success None ->
            log (fun () -> "Resolved future (without sending back the witness)");
            assign (`Exn (Failure "no proof",Exninfo.null))
          | Success (Some vernac_st) ->
            let f proof =
              log (fun () -> "Resolved future");
              assign (`Val (Declare.Proof.return_proof proof))
            in
            Vernacstate.LemmaStack.with_top (Option.get @@ vernac_st.Vernacstate.interp.lemmas) ~f
          | Failure ((loc,err),_,_) ->
              log (fun () -> "Aborted future");
              assign (`Exn (CErrors.UserError err, Option.fold_left Loc.add_loc Exninfo.null loc))
          with exn when CErrors.noncritical exn ->
            assign (`Exn (CErrors.UserError(Pp.str "error closing proof"), Exninfo.null))
        in
        let updates = [terminator_id,success last_vs] in
        let st = List.fold_left (fun st { id } ->
            if Option.equal Stateid.equal (Some id) last_step_id then
              { st with delegations = SM.add id { job_handle; on_completion = Some complete_job } st.delegations }
            else
              { st with delegations = SM.add id { job_handle; on_completion = None } st.delegations })
            st tasks in
        let e =
            ProofWorker.worker_available ~jobs:st.jobs
              ~fork_action:worker_main
              ~feedback_cleanup:(fun () -> Utilities.feedback_pipe_cleanup st.feedback_pipe)
        in
        Queue.push (job_handle, Sel.Event.get_cancellation_handle e, job) st.jobs;
        st, Done { updates; vs = last_vs; events = [inject_proof_event e]; exec_error = None }
      | _ ->
        (* If executing the proof opener failed, we skip the proof *)
        let updates = [terminator_id, success vs] in
        st, Done { updates; vs; events = []; exec_error = None }

let build_tasks_for document sch st id =
  let rec build_tasks id tasks st =
    begin match find_fulfilled_opt document id with
    | Some (Success (Some vs)) ->
      (* We reached an already computed state *)
      log (fun () -> "Reached computed state " ^ Stateid.to_string id);
      vs, tasks, st, None
    | Some (Failure((loc, _),_,Some vs)) ->
      (* We try to be resilient to an error *)
      log (fun () -> "Failure resiliency on state " ^ Stateid.to_string id);
      vs, tasks, st, Some (id, loc)
    | _ ->
      log (fun () -> "Non (locally) computed state " ^ Stateid.to_string id);
      let (base_id, task) = task_for_sentence sch id in
      begin match base_id with
      | None -> (* task should be executed in initial state *)
        st.initial, task :: tasks, st, None
      | Some base_id ->
        build_tasks base_id (task::tasks) st
      end
    end
  in
  let vs, tasks, st, error_id = build_tasks id [] st in
  vs, List.concat_map prepare_task tasks, st, error_id


let invalidate1 st id =
  try
    let { job_handle } = SM.find id st.delegations in
    DelegationManager.cancel_job job_handle;
    { st with delegations = SM.remove id st.delegations }
  with Not_found -> st

let invalidate st id =
  log (fun () -> "Invalidating: " ^ Stateid.to_string id);
  let st = invalidate1 st id in
  let old_jobs = Queue.copy st.jobs in
  let removed = ref [] in
  Queue.clear st.jobs;
  Queue.iter (fun ((_, cancellation, { ProofJob.terminator_id; tasks }) as job) ->
    if terminator_id != id then
      Queue.push job st.jobs
    else begin
      Sel.Event.cancel cancellation;
      removed := List.map (fun e -> PExec e) tasks :: !removed
    end) old_jobs;
  let st = List.fold_left invalidate1 st
    List.(concat (map (fun tasks -> map id_of_prepared_task tasks) !removed)) in
  st

let get_initial_vernac_state st = st.initial

module ProofWorkerProcess = struct
  type options = ProofWorker.options
  let parse_options = ProofWorker.parse_options
  let main ~st:_ options =
    let send_back, job = ProofWorker.setup_plumbing options in
    worker_main job ~send_back
  let log = ProofWorker.log
end

