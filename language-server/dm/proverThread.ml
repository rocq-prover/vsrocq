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

open Types

let (Log log) = Log.mk_log "proverThread"

(* We run Rocq in a thread so that we can interrupt it *)
type rocq_job =
  | Job :
      document_id 
      * (Memprof_limits.Token.t -> 'a)
      * 'a Sel.Promise.handler
      * Memprof_limits.Token.t
      -> rocq_job

type jobs = { mutable running : rocq_job option; queue : rocq_job Queue.t }

let jobs : jobs = { running = None; queue = Queue.create () }

let jobs_mutex = Mutex.create ()
let jobs_condition = Condition.create ()

let _runner =
  Thread.create
    (fun () ->
      while true do
        (* get a job *)
        let Job (_,task, resolver, token) =
          Mutex.lock jobs_mutex;
          while Queue.is_empty jobs.queue do
            Condition.wait jobs_condition jobs_mutex
          done;
          let rc = Queue.pop jobs.queue in
          jobs.running <- Some rc;
          Condition.signal jobs_condition;
          Mutex.unlock jobs_mutex;
          rc
        in

        (* run the job *)
        Sel.Promise.fulfill resolver (task token);

        (* erase the job *)
        Mutex.lock jobs_mutex;
        jobs.running <- None;
        Condition.signal jobs_condition;
        Mutex.unlock jobs_mutex
      done)
    ()

let interrupt_job_if ~doc_id (Job(id,_,_,token)) = if id = doc_id then Memprof_limits.Token.set token

let interrupt ~doc_id =
  Mutex.lock jobs_mutex;
  Option.iter (interrupt_job_if ~doc_id) jobs.running;
  Queue.iter (interrupt_job_if ~doc_id) jobs.queue;
  Mutex.unlock jobs_mutex

let limit f token =
  match Terminated (Memprof_limits.limit_with_token ~token f) with
  | Aborted _ | Interrupted -> assert false
  | Terminated (Error _) -> Interrupted
  | Terminated (Ok x) -> Terminated x
  | exception e ->
      let e, info = Exninfo.capture e in
      Aborted (e, info)

let run ~doc_id f =
  let token = Memprof_limits.Token.create () in
  let promise, r = Sel.Promise.make () in
  Mutex.lock jobs_mutex;
  Queue.push (Job (doc_id, limit f, r, token)) jobs.queue;
  Condition.signal jobs_condition;
  Mutex.unlock jobs_mutex;
  promise

let try_run ~doc_id ~timeout f =
  Mutex.lock jobs_mutex;
  if jobs.running = None && Queue.is_empty jobs.queue then begin
    let token = Memprof_limits.Token.create () in
    let p, r = Sel.Promise.make () in
    Queue.push (Job (doc_id, limit f, r, token)) jobs.queue;
    Condition.signal jobs_condition;
    Mutex.unlock jobs_mutex;
    let timeout = Unix.gettimeofday () +. timeout in
    while not (Sel.Promise.is_resolved p) && Unix.gettimeofday () < timeout do
      Unix.sleepf 0.01;
    done;
    Memprof_limits.Token.set token;
    try
      match Sel.Promise.get p with
      | Sel.Promise.Fulfilled (Terminated x) -> Result.Ok x
      | Sel.Promise.Fulfilled (Aborted e) -> Result.Error e
      | Sel.Promise.Fulfilled Interrupted -> Result.Error (Exninfo.capture @@ Failure "Rocq times out")
      | Sel.Promise.Rejected e -> raise e (* bug *)
    with Failure _ as e -> let e = Exninfo.capture e in Result.Error e
  end else begin
    Mutex.unlock jobs_mutex;
    Result.Error (Exninfo.capture @@ Failure "Rocq is busy")
  end


