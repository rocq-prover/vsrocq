(** Type for the raw document provided by the client *)
type text

(** Types that [Prover] provides *)

(** Integer that represent the absolute offset character in the
    document as an integer. *)
type loc
type doc = Host.ast list

(** LSP-like diagnostic *)
type diagnostic

(** LSP-like hovering info *)
type hover_info

(** LSP-like symbol information *)
type outline_item

(** Parse the raw document and returns a "chunk" of ast and the end
    location of the parsed ast.

    Returns [None] when the end of file has been reached or on an
    unrecoverable error. *)
val parse: text -> ?start:loc -> (Host.ast * loc) option

(** Validate semantically the [doc] which is a list of ast and
    populate a [valid_doc] which contains enough structure to compute
    diagnostics, hovering and outlining capabilities. *)
val validate: doc -> Host.valid_doc

(** Retrieve the diagnostics (warning/errors) from the validated
    doc. *)
val diagnostics: Host.valid_doc -> diagnostic list

(** Returns the info that located at the [loc] cursor position in
    validated document. *)
val hover: Host.valid_doc -> loc -> hover_info

(** Returns the outlined symbols of the validated document. *)
val outline: Host.valid_doc -> outline_item list
