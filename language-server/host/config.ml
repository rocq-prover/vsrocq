let check_mode = ref Settings.Mode.Manual

let diff_mode = ref Settings.Goals.Diff.Mode.Off

let point_interp_mode = ref Settings.PointInterpretationMode.Cursor

let max_memory_usage  = ref 4000000000

let full_diagnostics = ref false
let full_messages = ref false

let block_on_first_error = ref true

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

let options = ref default_options

let set_options o = options := o
let set_default_options () = options := default_options

let is_diagnostics_enabled () = !options.enableDiagnostics

let get_options () = !options

let do_configuration settings =
  let open Settings in
  let delegation_mode =
    match settings.proof.delegation with
    | None     -> CheckProofsInMaster
    | Skip     -> SkipProofs
    | Delegate -> DelegateProofsToWorkers { number_of_workers = Option.get settings.proof.workers }
  in
  set_options {
    delegation_mode;
    completion_options = settings.completion;
    enableDiagnostics = settings.diagnostics.enable;
  };
  check_mode := settings.proof.mode;
  diff_mode := settings.goals.diff.mode;
  full_diagnostics := settings.diagnostics.full;
  full_messages := settings.goals.messages.full;
  max_memory_usage := settings.memory.limit * 1000000000;
  block_on_first_error := settings.proof.block;
  point_interp_mode := settings.proof.pointInterpretationMode
