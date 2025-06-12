(**************************************************************************)
(*                                                                        *)
(*                                 VSRocq                                  *)
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
open Protocol.LspWrapper

module Loc = struct
  include Loc
end
[@@deprecated "use a proxy in host/"]

[%%if rocq = "8.18" || rocq = "8.19" || rocq = "8.20"]
  module Quickfix = struct
    type t = unit
    let from_exception _ = Ok([])
    let pp = Pp.mt
    let loc _ = Loc.make_loc (0,0)
  end
[%%endif]
