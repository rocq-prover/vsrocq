open Dm
open Tests.Common

let big_rocq_source = [%blob "Big.v"]

let doc_of_str text =
  let Document.{parsed_document} = init_and_parse_test_doc ~steps:(String.length text) ~text () in
  parsed_document
