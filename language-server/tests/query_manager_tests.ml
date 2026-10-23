(**************************************************************************)
(*                                                                        *)
(*                                 VSRocq                                 *)
(*                                                                        *)
(*                   Copyright INRIA and contributors                     *)
(*       (see version control and README file for authors & dates)        *)
(*                                                                        *)
(**************************************************************************)
(*                                                                        *)
(*   This file is distributed under the terms of the MIT License.         *)
(*   See LICENSE file for more details.                                   *)
(*                                                                        *)
(**************************************************************************)

open Base
open Dm

let%test_unit "dune interaction: copy rule locates source" =
  let rule = Yojson.Safe.from_string {|[
    {"deps":[{"File":["In_source_tree","theories/Foo.v"]}],
     "targets":{"files":["_build/default/theories/Foo.v"],"directories":[]},
     "action":["copy","theories/Foo.v","_build/default/theories/Foo.v"]}
  ]|} in
  [%test_eq: string option] (DuneInteraction.Internal.source_of_rules
    ~file:"_build/default/theories/Foo.v" rule) (Some "theories/Foo.v")

let%test_unit "dune interaction: generated rule has no source" =
  let rule = Yojson.Safe.from_string {|[
    {"deps":[],
     "targets":{"files":["_build/default/theories/Generated.v"],"directories":[]},
     "action":["with-stdout-to","_build/default/theories/Generated.v",["run","generator"]]}
  ]|} in
  [%test_eq: string option] (DuneInteraction.Internal.source_of_rules
    ~file:"_build/default/theories/Generated.v" rule) None

let%test_unit "dune interaction: malformed rule has no source" =
  let rule = Yojson.Safe.from_string {|[
    {"deps":[{"File":["In_source_tree",42]}],
     "action":["copy","theories/Foo.v","_build/default/theories/Foo.v"]}
  ]|} in
  [%test_eq: string option] (DuneInteraction.Internal.source_of_rules
    ~file:"_build/default/theories/Foo.v" rule) None
