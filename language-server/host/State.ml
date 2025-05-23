
type t = Vernacstate.t
let freeze_full_state = Vernacstate.freeze_full_state
let unfreeze_full_state = Vernacstate.unfreeze_full_state

module Parser = Vernacstate.Parser

module Synterp = Vernacstate.Synterp

module Interp = Vernacstate.Interp

module LemmaStack = Vernacstate.LemmaStack

module Declare = Vernacstate.Declare

module Stm = Vernacstate.Stm