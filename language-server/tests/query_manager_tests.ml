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

let%test_unit "dune interaction: project nested below workspace" =
  let workspace = Stdlib.Filename.temp_file "vsrocq-dune-" "" in
  Stdlib.Sys.remove workspace;
  Unix.mkdir workspace 0o700;
  let project = Stdlib.Filename.concat workspace "project" in
  Unix.mkdir project 0o700;
  let write name contents =
    let channel = Stdlib.open_out (Stdlib.Filename.concat project name) in
    Stdlib.output_string channel contents;
    Stdlib.close_out channel
  in
  let build = Stdlib.Filename.concat project "_build" in
  let cwd = Unix.getcwd () in
  Stdlib.Fun.protect ~finally:(fun () ->
    Unix.chdir cwd;
    if Stdlib.Sys.file_exists build then begin
      Stdlib.Array.iter (fun name -> Stdlib.Sys.remove (Stdlib.Filename.concat build name))
        (Stdlib.Sys.readdir build);
      Unix.rmdir build
    end;
    Stdlib.Sys.remove (Stdlib.Filename.concat project "dune-project");
    Stdlib.Sys.remove (Stdlib.Filename.concat project "A.v");
    Unix.rmdir project;
    Unix.rmdir workspace) (fun () ->
    write "dune-project" "(lang dune 3.2)\n";
    write "A.v" "(* source *)\n";
    Unix.chdir workspace;
    let artifact = Stdlib.Filename.concat project "_build/default/A.v" in
    [%test_eq: string] (DuneInteraction.prefer_source artifact)
      (Stdlib.Filename.concat project "A.v"))
