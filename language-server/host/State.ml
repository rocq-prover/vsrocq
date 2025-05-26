
type t = Vernacstate.t
let freeze_full_state = Vernacstate.freeze_full_state
let unfreeze_full_state = Vernacstate.unfreeze_full_state

[%%if rocq = "8.18" || rocq = "8.19"]
module Parser = Vernacstate.Parser
[%%else]
module Parser = struct
   let parse = Vernacstate.Synterp.parsing
end
[%%endif]

module Synterp = Vernacstate.Synterp

module Interp = Vernacstate.Interp

module LemmaStack = Vernacstate.LemmaStack

module Declare = Vernacstate.Declare [@ocaml.warning "-3"]

module Stm = Vernacstate.Stm

module Id = Stateid