(* Raw Document tests *)

open Base
open Dm
open Lsp.Types

let%test_unit "utf16 emoji position of loc" =
  let text = "Notation \"🦔🦔🦔\" := 1. Definition a := 1." in
  let doc = RawDocument.create text in

  let fst_sentence_end_loc = 29 in (* 1 per ascii, 4 per hedgehog (UTF8 bytes) *)
  let fst_sentence_end_pos = 23 in (* 1 per ascii, 2 per hedgehog (UTF16 code units) *)
  let pos_end_s1 = RawDocument.position_of_loc doc fst_sentence_end_loc in
  [%test_eq: int] pos_end_s1.Position.line 0;
  [%test_eq: int] pos_end_s1.Position.character fst_sentence_end_pos;

  (* \n = 1 byte = 1 code unit *)
  let snd_sentence_start_loc = fst_sentence_end_loc + 1 in
  let snd_sentence_start_pos = fst_sentence_end_pos + 1 in
  let pos_start_s2 = RawDocument.position_of_loc doc snd_sentence_start_loc in
  [%test_eq: int] pos_start_s2.Position.line 0;
  [%test_eq: int] pos_start_s2.Position.character snd_sentence_start_pos;

  (* second sentence is all ascii *)
  let snd_sentence_end_loc = snd_sentence_start_loc + 18 in
  let snd_sentence_end_pos = snd_sentence_start_pos + 18 in
  let pos_end_s2 = RawDocument.position_of_loc doc snd_sentence_end_loc in
  [%test_eq: int] pos_end_s2.Position.line 0;
  [%test_eq: int] pos_end_s2.Position.character snd_sentence_end_pos;

  [%test_eq: int] (RawDocument.loc_of_position doc pos_end_s1) fst_sentence_end_loc;
  [%test_eq: int] (RawDocument.loc_of_position doc pos_start_s2) snd_sentence_start_loc;
  [%test_eq: int] (RawDocument.loc_of_position doc pos_end_s2) snd_sentence_end_loc

let%test_unit "utf16 multiline emojis" =
  let text = "Line 1: 🚀🌟\nLine 2: pure ascii\nLine 3: 🎉 done" in
  let doc = RawDocument.create text in
  (* line 0: 8 ascii + 2*4 bytes + 1 ascii (\n) = 17 bytes *)
  let p_line1_start = RawDocument.position_of_loc doc 17 in
  [%test_eq: int] p_line1_start.Position.line 1;
  [%test_eq: int] p_line1_start.Position.character 0;

  (* in UTF-16 code units: 8 ascii + 2*2 units = 12 units. *)
  let p_line0_end = RawDocument.position_of_loc doc 16 in
  [%test_eq: int] p_line0_end.Position.line 0;
  [%test_eq: int] p_line0_end.Position.character 12;

  [%test_eq: int] (RawDocument.loc_of_position doc p_line1_start) 17;
  [%test_eq: int] (RawDocument.loc_of_position doc p_line0_end) 16;
  [%test_eq: int] (RawDocument.loc_of_position doc { line = 1; character = 5 }) 22

let%test_unit "out of bounds" =
  let text = "abc\ndef" in
  let doc = RawDocument.create text in
  [%test_eq: int] (RawDocument.position_of_loc doc (-5)).Position.line 0;
  [%test_eq: int] (RawDocument.position_of_loc doc (-5)).Position.character 0;
  [%test_eq: int] (RawDocument.position_of_loc doc 500).Position.line 1;
  [%test_eq: int] (RawDocument.position_of_loc doc 500).Position.character 3;
  [%test_eq: int] (RawDocument.loc_of_position doc { line = -1; character = 0 }) 0;
  [%test_eq: int] (RawDocument.loc_of_position doc { line = 100; character = 0 }) 4;
  [%test_eq: int] (RawDocument.loc_of_position doc { line = 0; character = -1 }) 0;
  [%test_eq: int] (RawDocument.loc_of_position doc { line = 0; character = 100 }) 4
