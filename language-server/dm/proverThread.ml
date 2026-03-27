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

let job_queue : rocq_job list ref = ref []
let job_mutex = Mutex.create ()
let job_condition = Condition.create ()

let _runner =
  Thread.create
    (fun () ->
      while true do
        (* get a job *)
        let Job (task, resolver, token) =
          Mutex.lock job_mutex;
          while !job_queue = [] do
            Condition.wait job_condition job_mutex
          done;
          let rc =
            match !job_queue with x :: _ -> (x) | [] -> assert false
          in
          Condition.signal job_condition;
          Mutex.unlock job_mutex;
          rc
        in

        (* run the job *)
        Sel.Promise.fulfill resolver (task token);

        (* erase the job *)
        Mutex.lock job_mutex;
        job_queue := List.tl !job_queue;
        Condition.signal job_condition;
        Mutex.unlock job_mutex
      done)
    ()

let interrupt_rocq_interpreter () =
  Mutex.lock job_mutex;
  while !job_queue <> [] do
    match !job_queue with
    | [] -> assert false
    | Job (_, _, token) :: _ ->
        log (fun () -> "interrupting...");
        Memprof_limits.Token.set token;
        Condition.wait job_condition job_mutex;
        log (fun () -> "interrupted!")
  done;
  Mutex.unlock job_mutex

let run_rocq_thread f resolver =
  Mutex.lock job_mutex;
  let token = Memprof_limits.Token.create () in
  job_queue := !job_queue @ [ Job (f, resolver, token) ];
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
  job_queue := !job_queue @ [ Job (f, r, token) ];
  Condition.signal job_condition;
  Mutex.unlock job_mutex;
  promise
