open Bechamel
open Dm
open Base
open Common

let entries source =
  let doc = doc_of_str source in
  fun () ->
    let _ = DocumentEntries.entries doc in
    ()

let big_outline =
  let doc = doc_of_str big_rocq_source in
  let entries = DocumentEntries.entries doc in
  fun () ->
    let _ = DocumentEntries.document_symbols entries in
    ()

let big_folding_ranges =
  let doc = doc_of_str big_rocq_source in
  let entries = DocumentEntries.entries doc in
  fun () ->
    let _ = DocumentEntries.folding_ranges entries in
    ()

let outline = Test.make_grouped ~name:"outline" [
    (Test.make ~name:"big" @@ Bechamel.Staged.stage @@ big_outline);
  ]
let folding_ranges = Test.make_grouped ~name:"folding_ranges" [
    (Test.make ~name:"big" @@ Bechamel.Staged.stage @@ big_folding_ranges);
  ]
let suite = Test.make_grouped ~name:"entries" [
    (Test.make ~name:"big" @@ Bechamel.Staged.stage @@ entries big_rocq_source);
    (Test.make ~name:"unicode" @@ Bechamel.Staged.stage @@ entries unicode_rocq_source);
    outline;
    folding_ranges;
  ]
