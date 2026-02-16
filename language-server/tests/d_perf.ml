open Common
open Dm
open Base

[@@@warning "-27"]


let edit_text doc ~start ~stop text =
  let rdoc = Document.raw_document doc in
  let start = RawDocument.position_of_loc rdoc start in
  let end_ = RawDocument.position_of_loc rdoc stop in
  let range = Lsp.Types.Range.{ start; end_ } in
  Document.apply_text_edits doc [range, text]

let size = 30_000  let adjust = 5 + size

let validate_document parsed_document =
  let doc, events = Document.validate_document parsed_document in
  let todo = Sel.Todo.add Sel.Todo.empty events in
  handle_d_events ~steps:adjust todo doc

let checkpoint () =
  let t = Unix.gettimeofday () in
  (* Stdlib.Gc.major (); *)
  t

let%test_unit "diff: huge doc" =
  let t0 = checkpoint () in
  let text = Stdlib.String.concat ".\n" (Stdlib.List.init size (fun _ -> "Definition x := 3")) in
  let edit = String.length text / 2 in
  let Document.{parsed_document} = init_and_parse_test_doc ~steps:(size+adjust) ~text () in
  let t1 = checkpoint () in
  let parsed_document = edit_text parsed_document ~start:edit ~stop:edit "x" in
  let { Document.parsed_document } = validate_document parsed_document in
  let t2 = checkpoint () in
  let o = Document.outline parsed_document in
  let t3 = checkpoint () in
  [%test_pred: int] (fun x -> x + 3 >= size && x <=size) (List.length o); (* the error *)
  Stdlib.Printf.eprintf "full parse: %5.3f\n" (t1 -. t0);
  Stdlib.Printf.eprintf "edit: %5.3f \n" (t2 -. t1);
  Stdlib.Printf.eprintf "outline: %5.3f\n" (t3 -. t2);
  ()

let _ = Log.lsp_initialization_done ()