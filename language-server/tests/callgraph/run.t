Problematic calls

  $ ./static_callgraph.exe --whitelist static_callgraph_whitelist.txt --safe-barriers static_callgraph_safe_barriers.txt ../../dm/.dm.objs/byte/dm__DocumentManager.cmt | grep -v '*$'
  get_document_proofs -> Protocol.ProofState.mk_proof_block
  get_document_proofs -> Protocol.ProofState.mk_proof_statement
  get_document_proofs -> Stdlib.List.map -> Protocol.ProofState.mk_proof_step
  get_proof -> Dm.CheckingManager.get_proof -> Option.bind -> Protocol.ProofState.get_proof
  handle_event -> Dm.CheckingManager.handle_event -> Dm.CheckingManager.execute -> Dm.CheckingManager.mk_execution_promise_event -> Dm.CheckingManager.mk_execution_promise_event.k
  handle_event -> Dm.CheckingManager.handle_event -> Dm.CheckingManager.get_proof -> Option.bind -> Protocol.ProofState.get_proof
  handle_event -> Dm.CheckingManager.handle_event -> Dm.CheckingManager.get_string_proof -> Option.bind -> Protocol.PpProofState.get_proof

Calls sequentialized via ProverThread APIs

  $ ./static_callgraph.exe --whitelist static_callgraph_whitelist.txt --safe-barriers static_callgraph_safe_barriers.txt ../../dm/.dm.objs/byte/dm__DocumentManager.cmt | grep '*$'
  about -> Dm.QueryManager.about -> Dm.ProverThread.try_run -> [thunk] -> *
  check -> Dm.QueryManager.check -> Dm.ProverThread.try_run -> [thunk] -> *
  get_completions -> Dm.QueryManager.get_completions -> Dm.ProverThread.try_run -> [thunk] -> *
  handle_event -> Dm.CheckingManager.handle_event -> Dm.CheckingManager.execute -> Dm.ExecutionManager.execute -> Dm.ExecutionManager.complete_proof -> Dm.ProverThread.run -> *
  handle_event -> Dm.CheckingManager.handle_event -> Dm.CheckingManager.execute -> Dm.ExecutionManager.execute -> Dm.ExecutionManager.interp_qed_delayed -> Dm.ProverThread.run -> *
  handle_event -> Dm.CheckingManager.handle_event -> Dm.CheckingManager.execute -> Dm.ExecutionManager.execute -> Dm.ExecutionManager.promise_execution -> Dm.ProverThread.eventually_run -> *
  handle_event -> Dm.CheckingManager.handle_event -> Dm.CheckingManager.execute -> Dm.ExecutionManager.execute -> ProofWorker.worker_available -> *
  handle_event -> Dm.Document.handle_event -> Dm.Document.create_parse_event -> Dm.ProverThread.eventually_run -> *
  handle_event -> Dm.Document.validate_document -> Dm.Document.create_parse_event -> Dm.ProverThread.eventually_run -> *
  hover -> Dm.QueryManager.hover -> Dm.ProverThread.try_run -> [thunk] -> *
  init -> start_library -> Dm.ProverThread.run -> *
  jump_to_definition -> Dm.QueryManager.jump_to_definition -> Dm.ProverThread.try_run -> [thunk] -> *
  locate -> Dm.QueryManager.locate -> Dm.ProverThread.try_run -> [thunk] -> *
  print -> Dm.QueryManager.print -> Dm.ProverThread.try_run -> [thunk] -> *
  search -> Dm.QueryManager.search -> Dm.ProverThread.try_run -> [thunk] -> *
  start_library -> Dm.ProverThread.run -> *
