Compare the DocumentManager callgraph tool output against the checked-in reference.

  $ ./static_callgraph.exe --whitelist static_callgraph_whitelist.txt --safe-barriers static_callgraph_safe_barriers.txt ../../dm/.dm.objs/byte/dm__DocumentManager.cmt
  about -> Dm.QueryManager.about -> Dm.ProverThread.try_run -> [thunk] -> *
  about -> Dm.QueryManager.about -> Dm.QueryManager.to_types_error -> CErrors.iprint
  check -> Dm.QueryManager.check -> Dm.ProverThread.try_run -> [thunk] -> *
  check -> Dm.QueryManager.check -> Dm.QueryManager.to_types_error -> CErrors.iprint
  executed_ranges -> Dm.CheckingManager.executed_ranges -> Dm.CheckingManager.overview_until_range -> Dm.CheckingManager.overview_until_range.find_final_range
  get_completions -> Dm.QueryManager.get_completions -> Dm.ProverThread.try_run -> [thunk] -> *
  get_document_proofs -> Protocol.ProofState.mk_proof_block
  get_document_proofs -> Protocol.ProofState.mk_proof_statement
  get_document_proofs -> Stdlib.List.map -> Protocol.ProofState.mk_proof_step
  get_proof -> Dm.CheckingManager.get_proof -> Protocol.ProofState.get_proof
  handle_event -> Dm.CheckingManager.handle_event -> Dm.CheckingManager.execute -> Dm.ExecutionManager.execute -> Declare.Proof.return_proof
  handle_event -> Dm.CheckingManager.handle_event -> Dm.CheckingManager.execute -> Dm.ExecutionManager.execute -> Dm.ExecutionManager.execute.assign
  handle_event -> Dm.CheckingManager.handle_event -> Dm.CheckingManager.execute -> Dm.ExecutionManager.execute -> Dm.ExecutionManager.interp_qed_delayed -> CAst.make
  handle_event -> Dm.CheckingManager.handle_event -> Dm.CheckingManager.execute -> Dm.ExecutionManager.execute -> Dm.ExecutionManager.interp_qed_delayed -> Declare.Proof.close_future_proof
  handle_event -> Dm.CheckingManager.handle_event -> Dm.CheckingManager.execute -> Dm.ExecutionManager.execute -> Dm.ExecutionManager.interp_qed_delayed -> Dm.ExecutionManager.add_using -> Declare.Proof.set_proof_using
  handle_event -> Dm.CheckingManager.handle_event -> Dm.CheckingManager.execute -> Dm.ExecutionManager.execute -> Dm.ExecutionManager.interp_qed_delayed -> Future.create_delegate
  handle_event -> Dm.CheckingManager.handle_event -> Dm.CheckingManager.execute -> Dm.ExecutionManager.execute -> Dm.ExecutionManager.interp_qed_delayed -> Vernacinterp.interp_qed_delayed_proof
  handle_event -> Dm.CheckingManager.handle_event -> Dm.CheckingManager.execute -> Dm.ExecutionManager.execute -> Dm.ExecutionManager.interp_qed_delayed -> Vernacstate.LemmaStack.with_top
  handle_event -> Dm.CheckingManager.handle_event -> Dm.CheckingManager.execute -> Dm.ExecutionManager.execute -> Dm.ExecutionManager.thread_execute -> Dm.ProverThread.eventually_run -> *
  handle_event -> Dm.CheckingManager.handle_event -> Dm.CheckingManager.execute -> Dm.ExecutionManager.execute -> ProofWorker.worker_available
  handle_event -> Dm.CheckingManager.handle_event -> Dm.CheckingManager.execute -> Dm.ExecutionManager.execute -> Vernacstate.LemmaStack.with_top
  handle_event -> Dm.CheckingManager.handle_event -> Dm.CheckingManager.get_proof -> Protocol.ProofState.get_proof
  handle_event -> Dm.CheckingManager.handle_event -> Dm.CheckingManager.handle_execution_manager_event -> Dm.ExecutionManager.handle_event -> ProofWorker.handle_event
  handle_event -> Dm.CheckingManager.handle_event -> Dm.CheckingManager.observe -> Dm.ExecutionManager.build_tasks_for -> Dm.ExecutionManager.build_tasks_for.build_tasks
  handle_event -> Dm.CheckingManager.handle_event -> Dm.CheckingManager.real_interpret_to_previous -> Vernacstate.unfreeze_full_state
  handle_event -> Dm.CheckingManager.validate_document -> Dm.CheckingManager.interpret_in_background -> Dm.CheckingManager.observe -> Dm.ExecutionManager.build_tasks_for -> Dm.ExecutionManager.build_tasks_for.build_tasks
  handle_event -> Dm.Document.handle_event -> Dm.Document.create_parse_event -> Dm.ProverThread.eventually_run -> *
  handle_event -> Dm.Document.handle_event -> Dm.Document.handle_invalidate -> Dm.Document.invalidate -> Dm.Document.add_sentence -> Dm.Scheduler.schedule_sentence -> Dm.Scheduler.push_state -> Dm.Scheduler.base_id -> Dm.Scheduler.base_id.aux
  handle_event -> Dm.Document.handle_event -> Dm.Document.handle_invalidate -> Dm.Document.invalidate -> Dm.Document.add_sentence -> Dm.Scheduler.schedule_sentence -> Dm.Scheduler.push_state -> Dm.Scheduler.is_opaque_flat_proof -> Dm.Scheduler.find_proof_using_annotation -> Dm.Scheduler.find_proof_using -> Proof_using.get_default_proof_using
  handle_event -> Dm.Document.handle_event -> Dm.Document.handle_invalidate -> Dm.Document.invalidate -> Dm.Document.invalidate.add_new_or_patch
  handle_event -> Dm.Document.handle_event -> Dm.Document.handle_invalidate -> Dm.Document.invalidate -> Dm.Document.invalidate.remove_old
  handle_event -> Dm.Document.handle_event -> Dm.Document.handle_invalidate -> Dm.Document.invalidate -> Dm.Document.patch_sentence -> Dm.Scheduler.schedule_sentence -> Dm.Scheduler.push_state -> Dm.Scheduler.base_id -> Dm.Scheduler.base_id.aux
  handle_event -> Dm.Document.handle_event -> Dm.Document.handle_invalidate -> Dm.Document.invalidate -> Dm.Document.patch_sentence -> Dm.Scheduler.schedule_sentence -> Dm.Scheduler.push_state -> Dm.Scheduler.is_opaque_flat_proof -> Dm.Scheduler.find_proof_using_annotation -> Dm.Scheduler.find_proof_using -> Proof_using.get_default_proof_using
  handle_event -> Dm.Document.validate_document -> Dm.Document.create_parse_event -> Dm.ProverThread.eventually_run -> *
  hover -> Dm.QueryManager.hover -> Dm.ProverThread.try_run -> [thunk] -> *
  init -> Dm.ProverThread.run -> *
  interpret_in_background -> Dm.CheckingManager.interpret_in_background -> Dm.CheckingManager.observe -> Dm.ExecutionManager.build_tasks_for -> Dm.ExecutionManager.build_tasks_for.build_tasks
  jump_to_definition -> Dm.QueryManager.jump_to_definition -> Dm.ProverThread.try_run -> [thunk] -> *
  locate -> Dm.QueryManager.locate -> Dm.ProverThread.try_run -> [thunk] -> *
  locate -> Dm.QueryManager.locate -> Dm.QueryManager.to_types_error -> CErrors.iprint
  print -> Dm.QueryManager.print -> Dm.ProverThread.try_run -> [thunk] -> *
  print -> Dm.QueryManager.print -> Dm.QueryManager.to_types_error -> CErrors.iprint
  search -> Dm.QueryManager.search -> Dm.ProverThread.try_run -> [thunk] -> *
  start_library -> Coqinit.start_library
