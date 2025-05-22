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
