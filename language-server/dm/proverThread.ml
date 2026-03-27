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
      (Memprof_limits.Token.t -> 'a)
      * 'a Sel.Promise.handler
      * Memprof_limits.Token.t
      -> rocq_job

let job_queue : rocq_job Queue.t = Queue.create ()
let job_mutex = Mutex.create ()
let job_condition = Condition.create ()

let _runner =
  Thread.create
    (fun () ->
      while true do
        (* get a job *)
        let Job (task, resolver, token) =
          Mutex.lock job_mutex;
          while Queue.is_empty job_queue do
            Condition.wait job_condition job_mutex
          done;
          let rc = Queue.peek job_queue in
          Condition.signal job_condition;
          Mutex.unlock job_mutex;
          rc
        in

        (* run the job *)
        Sel.Promise.fulfill resolver (task token);

        (* erase the job *)
        Mutex.lock job_mutex;
        ignore(Queue.pop job_queue);
        Condition.signal job_condition;
        Mutex.unlock job_mutex
      done)
    ()

let interrupt_rocq_interpreter () =
  Mutex.lock job_mutex;
  while not @@ Queue.is_empty job_queue do
    let Job (_, _, token) = Queue.peek job_queue in
    log (fun () -> "interrupting...");
    Memprof_limits.Token.set token;
    Condition.wait job_condition job_mutex;
    log (fun () -> "interrupted!")
  done;
  Mutex.unlock job_mutex

let run_rocq_thread f resolver =
  Mutex.lock job_mutex;
  let token = Memprof_limits.Token.create () in
  Queue.push (Job (f, resolver, token)) job_queue;
  Condition.signal job_condition;
  Mutex.unlock job_mutex

let run_rocq f =
  let token = Memprof_limits.Token.create () in
  let promise, r = Sel.Promise.make () in
  let f token =
    match Terminated (Memprof_limits.limit_with_token ~token f) with
    | Aborted _ | Interrupted -> assert false
    | Terminated (Error _) -> Interrupted
    | Terminated (Ok x) -> Terminated x
    | exception e ->
        let e, info = Exninfo.capture e in
        Aborted (e, info)
  in
  Mutex.lock job_mutex;
  Queue.push (Job (f, r, token)) job_queue;
  Condition.signal job_condition;
  Mutex.unlock job_mutex;
  promise
