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

type retry = bool
module Queue = struct
  type 'a t = 'a list ref

  let create () = ref []
  let is_empty q = [] = !q
  let pop q =
    match !q with
    | [] -> assert false
    | x :: xs -> q := xs; x
  let enqueue x q = q := !q @ [x]
  let add_head x q = q := x :: !q
  let iter f q = List.iter f !q

end

(* We run Rocq in a thread so that we can interrupt it *)
type rocq_job =
  | Job :
      document_id 
      * (Memprof_limits.Token.t -> 'a interruptible_result)
      * 'a interruptible_result Sel.Promise.handler
      * Memprof_limits.Token.t
      * retry ref
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
        let Job (doc_id ,task, resolver, token, retry) =
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
        log (fun () -> "runner: job begins");
        match task token with
        | Interrupted when !retry ->
            log (fun () -> "runner: postponing running job");
            Mutex.lock jobs_mutex;
            jobs.running <- None;
            Queue.enqueue (Job (doc_id ,task, resolver, Memprof_limits.Token.create (), ref false)) jobs.queue;
            Condition.signal jobs_condition;
            Mutex.unlock jobs_mutex

        | x ->
            log (fun () -> "runner: job ends");
            Sel.Promise.fulfill resolver x;
            Mutex.lock jobs_mutex;
            jobs.running <- None;
            Condition.signal jobs_condition;
            Mutex.unlock jobs_mutex

      done)
    ()

let interrupt_job_if ~doc_id (Job(id,_,_,token,_)) = if id = doc_id then Memprof_limits.Token.set token
let postpone_job (Job(_,_,_,token,retry)) =
  log (fun () -> "main: postponing running job");
  retry := true;
  Memprof_limits.Token.set token

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
      Aborted (CErrors.iprint (e, info))

let busy_wait timeout p token =
  let timeout = Unix.gettimeofday () +. timeout in
  while not (Sel.Promise.is_resolved p) && Unix.gettimeofday () < timeout do
    Unix.sleepf 0.01;
  done;
  Memprof_limits.Token.set token;
  try
    match Sel.Promise.get p with
    | Sel.Promise.Fulfilled x -> x
    | Sel.Promise.Rejected e -> raise e (* bug *)
  with Failure _ -> Aborted (Pp.str "Rocq times out")


let run ~doc_id ~timeout f =
  log (fun () -> "main: run");
  let token = Memprof_limits.Token.create () in
  let promise, r = Sel.Promise.make () in
  Mutex.lock jobs_mutex;
  Option.iter postpone_job jobs.running;
  Queue.add_head (Job (doc_id, limit f, r, token, ref false)) jobs.queue;
  Condition.signal jobs_condition;
  Mutex.unlock jobs_mutex;
  busy_wait timeout promise token

let eventually_run ~doc_id f =
  log (fun () -> "main: eventually_run");
  let token = Memprof_limits.Token.create () in
  let promise, r = Sel.Promise.make () in
  Mutex.lock jobs_mutex;
  Queue.enqueue (Job (doc_id, limit f, r, token, ref false)) jobs.queue;
  Condition.signal jobs_condition;
  Mutex.unlock jobs_mutex;
  promise

(* let try_run ~doc_id ~timeout f =
  log (fun () -> "main: try_run");
  Mutex.lock jobs_mutex;
  if jobs.running = None && Queue.is_empty jobs.queue then begin
    let token = Memprof_limits.Token.create () in
    let p, r = Sel.Promise.make () in
    Queue.add_head (Job (doc_id, limit f, r, token, ref false)) jobs.queue;
    Condition.signal jobs_condition;
    Mutex.unlock jobs_mutex;
    busy_wait timeout p token
  end else begin
    Mutex.unlock jobs_mutex;
    Aborted (Pp.str "Rocq is busy")
  end *)


