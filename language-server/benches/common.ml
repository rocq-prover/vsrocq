open Dm
open Tests.Common

let big_rocq_source = [%blob "Big.v"]

let unicode_rocq_source =
  let size = 5000 in
  let buf = Buffer.create (size * 20) in
  for i = 1 to size do
    Buffer.add_string buf (Printf.sprintf "Notation \"🦔_%d_🚀\" := %d. (* 🌟 Comment with UTF-8: é, à, ü *) Definition foo_%d := %d.\n" i i i i)
  done;
  Buffer.contents buf

let doc_of_str text =
  let Document.{parsed_document} = init_and_parse_test_doc ~steps:(String.length text) ~text () in
  parsed_document
