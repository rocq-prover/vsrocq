
(**
Proxy for existing types of location in VsCoq.

Will be replaced by modules that are defined in the file later.
*)
type t = Loc.t
type 'a located = 'a Loc.located
let unloc = Loc.unloc
let shift_loc = Loc.shift_loc
let get_begin t = t.Loc.bp
let get_end t = t.Loc.ep
let make_loc = Loc.make_loc
let add_loc = Loc.add_loc
let get_loc = Loc.get_loc

(**
Abstrat type for location in lsp protocol
*)
module type Location = sig

  type t
  type 'a located
  val unloc : t -> (int * int) (* Replace by Lsp.Postion.t*)
  val shift_loc : int -> int -> t -> t
  val get_begin : t -> int
  val get_end : t -> int
  val make_loc : int * int -> t
  val add_loc : Exninfo.info -> t -> Exninfo.info
  val get_loc : Exninfo.info -> t option
end

module RocqLoc : Location = struct
  type t = Loc.t
  type 'a located = 'a Loc.located
  let unloc = Loc.unloc
  let shift_loc = Loc.shift_loc
  let get_begin t = t.Loc.bp
  let get_end t = t.Loc.ep
  let make_loc = Loc.make_loc
  let add_loc = Loc.add_loc
  let get_loc = Loc.get_loc
end