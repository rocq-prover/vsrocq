(** Given a location, returns the set of tasks that the interactive
    prover has to compute. *)
(* val tasks: HostTypes.valid_doc -> destination:DocumentManager.loc -> HostTypes.task list *)

(** Compute a [task] given a valid document and an execution state and
    returns its result: with the modified state in case of success. *)
(* val interp: HostTypes.valid_doc -> HostTypes.task -> HostTypes.state -> (HostTypes.state, string) result *)

(** When validation ends, the bridge notifies the interaction manager that can invalidate
    its internal state *)
(* reset ? *)
(* val doc_changed: HostTypes.valid_doc -> HostTypes.state -> HostTypes.state *)

(** Given a state, returns all the diagnostic that should be sent to
    the user. *)
(* val diagnostics: HostTypes.state -> DocumentManager.diagnostic list *)

(** Given a state and a location, returns the information (if any)
    associated to the term pointed. *)
(* val hover: HostTypes.state -> DocumentManager.loc -> DocumentManager.hover_info *)

(** ??? *)
(* val query: HostTypes.state -> HostTypes.query_type -> HostTypes.pp *)

(** ??? *)
(* val goalview: HostTypes.state -> DocumentManager.loc -> HostTypes.pp *)
