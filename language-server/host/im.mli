(** Given a location, returns the set of tasks that the interactive
    prover has to compute. *)
val tasks: Host.valid_doc -> destination:Dm.loc -> Host.task list

(** Compute a [task] given a valid document and an execution state and
    returns its result: with the modified state in case of success. *)
val interp: Host.valid_doc -> Host.task -> Host.state -> (Host.state, string) result

(** When validation ends, the bridge notifies the interaction manager that can invalidate
    its internal state *)
(* reset ? *)
val doc_changed: Host.valid_doc -> Host.state -> Host.state

(** Given a state, returns all the diagnostic that should be sent to
    the user. *)
val diagnostics: Host.state -> Dm.diagnostic list

(** Given a state and a location, returns the information (if any)
    associated to the term pointed. *)
val hover: Host.state -> Dm.loc -> Dm.hover_info

(** ??? *)
val query: Host.state -> Host.query_type -> Host.pp

(** ??? *)
val goalview: Host.state -> Dm.loc -> Host.pp
