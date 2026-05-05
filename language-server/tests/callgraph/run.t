Problematic calls

  $ ./static_callgraph.exe --whitelist static_callgraph_whitelist.txt --safe-barriers static_callgraph_safe_barriers.txt ../../dm/.dm.objs/byte/dm__DocumentManager.cmt | grep -v '*$'
  [1]

Calls sequentialized via ProverThread APIs

  $ ./static_callgraph.exe --whitelist static_callgraph_whitelist.txt --safe-barriers static_callgraph_safe_barriers.txt ../../dm/.dm.objs/byte/dm__DocumentManager.cmt | grep '*$'
  about -> Dm.QueryManager.about -> Dm.ProverThread.run -> [thunk] -> *
  check -> Dm.QueryManager.check -> Dm.ProverThread.run -> [thunk] -> *
  get_completions -> Dm.QueryManager.get_completions -> Dm.ProverThread.run -> [thunk] -> *
  get_document_proofs -> Dm.ProverThread.run -> *
  handle_event -> Dm.CheckingManager.handle_event -> Dm.CheckingManager.execute -> Dm.ExecutionManager.execute -> Dm.ExecutionManager.complete_proof -> Dm.ProverThread.run -> *
  handle_event -> Dm.CheckingManager.handle_event -> Dm.CheckingManager.execute -> Dm.ExecutionManager.execute -> Dm.ExecutionManager.interp_qed_delayed -> Dm.ProverThread.run -> *
  handle_event -> Dm.CheckingManager.handle_event -> Dm.CheckingManager.execute -> Dm.ExecutionManager.execute -> Dm.ExecutionManager.promise_execution -> Dm.ProverThread.eventually_run -> *
  handle_event -> Dm.CheckingManager.handle_event -> Dm.CheckingManager.execute -> Dm.ExecutionManager.execute -> ProofWorker.worker_available -> *
  handle_event -> Dm.CheckingManager.handle_event -> Dm.ProverThread.run -> *
  handle_event -> Dm.Document.handle_event -> Dm.Document.create_parse_event -> Dm.ProverThread.eventually_run -> *
  handle_event -> Dm.Document.validate_document -> Dm.Document.create_parse_event -> Dm.ProverThread.eventually_run -> *
  hover -> Dm.QueryManager.hover -> Dm.ProverThread.run -> [thunk] -> *
  init -> start_library -> Dm.ProverThread.run -> *
  jump_to_definition -> Dm.QueryManager.jump_to_definition -> Dm.ProverThread.run -> [thunk] -> *
  locate -> Dm.QueryManager.locate -> Dm.ProverThread.run -> [thunk] -> *
  print -> Dm.QueryManager.print -> Dm.ProverThread.run -> [thunk] -> *
  search -> Dm.QueryManager.search -> Dm.ProverThread.run -> [thunk] -> *
  start_library -> Dm.ProverThread.run -> *
