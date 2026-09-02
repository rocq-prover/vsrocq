open Bechamel
open Dm
open Base
open Common
open Tests.Common

let edit_text doc ~start ~stop text =
  let rdoc = Document.raw_document doc in
  let start = RawDocument.position_of_loc rdoc start in
  let end_ = RawDocument.position_of_loc rdoc stop in
  let range = Lsp.Types.Range.{ start; end_ } in
  Document.apply_text_edits doc [range, text]

let validate_document parsed_document =
  let doc, events = Document.validate_document parsed_document in
  let todo = Sel.Todo.add Sel.Todo.empty events in
  let size = String.length @@ RawDocument.text @@ Document.raw_document parsed_document in
  handle_d_events ~steps:size todo doc

let big_raw_document_create =
  fun () ->
    let _ = RawDocument.create big_rocq_source in
    ()

let position_of_loc source =
  let rdoc = RawDocument.create source in
  let len = RawDocument.end_loc rdoc in
  let sample_count = 1000 in
  let locs = Array.init sample_count ~f:(fun i -> (i * (len - 1)) / sample_count) in
  fun () ->
    for i = 0 to sample_count - 1 do
      let _ = RawDocument.position_of_loc rdoc locs.(i) in
      ()
    done

let loc_of_position source =
  let rdoc = RawDocument.create source in
  let len = RawDocument.end_loc rdoc in
  let sample_count = 1000 in
  let positions = Array.init sample_count ~f:(fun i ->
    let loc = (i * (len - 1)) / sample_count in
    RawDocument.position_of_loc rdoc loc
  ) in
  fun () ->
    for i = 0 to sample_count - 1 do
      let _ = RawDocument.loc_of_position rdoc positions.(i) in
      ()
    done

let word_at_loc source =
  let rdoc = RawDocument.create source in
  let len = RawDocument.end_loc rdoc in
  let sample_count = 1000 in
  let locs = Array.init sample_count ~f:(fun i -> (i * (len - 1)) / sample_count) in
  fun () ->
    for i = 0 to sample_count - 1 do
      let _ = RawDocument.word_at_loc rdoc locs.(i) in
      ()
    done

let big_parse =
  let text = big_rocq_source in
  fun () ->
    let Document.{parsed_document} = init_and_parse_test_doc ~steps:(String.length text) ~text () in
    let _ = validate_document parsed_document in
    ()

let big_edit =
  let text = big_rocq_source in
  let edit = String.length text in
  let Document.{parsed_document} = init_and_parse_test_doc ~steps:(String.length text) ~text () in
  fun () ->
    let parsed_document = edit_text parsed_document ~start:edit ~stop:edit "Abort." in
    let _ = validate_document parsed_document in
    ()

let raw_document = Test.make_grouped ~name:"raw_document" [
    (Test.make ~name:"create" @@ Bechamel.Staged.stage @@ big_raw_document_create);
    (Test.make ~name:"pos_of_loc" @@ Bechamel.Staged.stage @@ position_of_loc big_rocq_source);
    (Test.make ~name:"loc_of_pos" @@ Bechamel.Staged.stage @@ loc_of_position big_rocq_source);
    (Test.make ~name:"word_at_loc" @@ Bechamel.Staged.stage @@ word_at_loc big_rocq_source);
    (Test.make ~name:"unicode_pos_of_loc" @@ Bechamel.Staged.stage @@ position_of_loc unicode_rocq_source);
    (Test.make ~name:"unicode_loc_of_pos" @@ Bechamel.Staged.stage @@ loc_of_position unicode_rocq_source);
    (Test.make ~name:"unicode_word_at_loc" @@ Bechamel.Staged.stage @@ word_at_loc unicode_rocq_source);
  ]
let edit = Test.make_grouped ~name:"edit" [
    (Test.make ~name:"big" @@ Bechamel.Staged.stage @@ big_edit);
  ]
let parse = Test.make_grouped ~name:"parse" [
    (Test.make ~name:"big" @@ Bechamel.Staged.stage @@ big_parse);
  ]
let suite = Test.make_grouped ~name:"text" [
    raw_document;
    edit;
    parse;
  ]
