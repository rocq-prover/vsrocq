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
(*   See LICENSE file.                                                    *)
(*                                                                        *)
(**************************************************************************)
open Lsp.Types

type text_edit = Range.t * string

type t = {
  text : string;
  lines : int array; (* locs of beginning of lines *)
}

let compute_lines text =
  let lines = String.split_on_char '\n' text in
  let _,lines_locs = CList.fold_left_map (fun acc s -> let n = String.length s in n + acc + 1, acc) 0 lines in
  Array.of_list lines_locs

let create text = { text; lines = compute_lines text }

let text t = t.text

let line_text raw i =
  if i + 1 < Array.length raw.lines then
   (raw.lines.(i), raw.lines.(i+1) - raw.lines.(i))
  else
   (raw.lines.(i), String.length raw.text - raw.lines.(i))

let get_character_pos raw (i,e) loc =
  let rec loop d =
    if Uutf.decoder_byte_count d >= loc then
      Uutf.decoder_count d
    else
      match Uutf.decode d with
      | `Uchar _ -> loop d
      | `Malformed _ -> loop d
      | `End -> Uutf.decoder_count d
      | `Await -> Uutf.Manual.src d (Bytes.unsafe_of_string "") 0 0; loop d
  in
  let nln = `Readline (Uchar.of_int 0x000A) in
  let encoding = `UTF_8 in
  let d = Uutf.decoder ~nln ~encoding `Manual in
  (* Printf.eprintf "lookup %d|%s\n" loc (String.sub raw.text i e); *)
  Uutf.Manual.src d (Bytes.unsafe_of_string raw.text) i e;
  loop d

let rec position_of_loc_bisect raw loc i m n len =
  (* Printf.eprintf "%i | %i(%d) <= %i(%d) < %i(%d)\n" loc m raw.lines.(m) i raw.lines.(i) n raw.lines.(n); *)
  if i = len || i = n || raw.lines.(i) <= loc && loc < raw.lines.(i+1) then i
  else if loc < raw.lines.(i) then position_of_loc_bisect raw loc (m + (max 1 ((i - m) / 2))) m i len
  else position_of_loc_bisect raw loc (i + (max 1 ((n - i) / 2))) i n len


let position_of_loc_bisect raw loc =
  let nlines = Array.length raw.lines in
  let line = if loc = 0 then 0 else position_of_loc_bisect raw loc (nlines/2) 0 (nlines-1) (nlines-1) in
  (* Printf.eprintf "line bisect: %d\n" line; *)
  let char = get_character_pos raw (line_text raw line) (loc - raw.lines.(line)) in
  Position.{ line = line; character = char }

let position_of_loc = position_of_loc_bisect

(* let position_of_loc raw loc =
  let i = ref 0 in
  while (!i < Array.length raw.lines && raw.lines.(!i) <= loc) do incr(i) done;
  let line = !i - 1 in
  (* Printf.eprintf "line linear: %d\n" line; *)
  let char = get_character_pos raw (line_text raw line) (loc - raw.lines.(line)) in
   Position.{ line = line; character = char }

let position_of_loc r l =
  assert(l>=0);
  let p1 = position_of_loc_bisect r l in
  let p2 = position_of_loc r l in
  (* Printf.eprintf "%d=%d, %d=%d\n" p1.Position.character p2.Position.character p1.Position.line p2.Position.line; *)
  assert(p1=p2);
  p1
 *)
let get_character_loc raw (i,e) pos =
  let rec loop d =
    if Uutf.decoder_count d >= pos then
      Uutf.decoder_byte_count d
    else
      match Uutf.decode d with
      | `Uchar _ -> loop d
      | `Malformed _ -> loop d
      | `End -> Uutf.decoder_byte_count d
      | `Await -> Uutf.Manual.src d (Bytes.unsafe_of_string "") 0 0; loop d
  in
  let nln = `Readline (Uchar.of_int 0x000A) in
  let encoding = `UTF_8 in
  let d = Uutf.decoder ~nln ~encoding `Manual in
  Uutf.Manual.src d (Bytes.unsafe_of_string raw.text) i e;
  loop d

let loc_of_position raw Position.{ line; character } =
  let linestr = line_text raw line in
  let charloc = get_character_loc raw linestr character in
  raw.lines.(line) + charloc

let end_loc raw =
  String.length raw.text

let range_of_loc raw loc =
  let open Range in
  { start = position_of_loc_bisect raw loc.Loc.bp;
    end_  = position_of_loc_bisect raw loc.Loc.ep;
  }

let word_at_position raw pos : string option =
  try
    let back_reg = Str.regexp {|[^a-zA-Z_0-9.']|} in
    let start_ind = loc_of_position raw pos in
    (* Search backwards until we find a character that cannot be part of a word *)
    let first_non_word_ind = Str.search_backward back_reg raw.text start_ind in
    let first_word_ind = first_non_word_ind + 1 in
    let forward_reg = Str.regexp {|[^a-zA-Z_0-9']|} in
    (* Search forwards ensuring that all characters are part of a well defined word. (Cannot start with [0-9'.] and cannot end with .)*)
    let last_word_ind = Str.search_forward forward_reg raw.text start_ind in
    (* we get the substring from the first word index to the last index for the word *)
    let word = String.sub raw.text first_word_ind (last_word_ind - first_word_ind) in
    Some word
  with _ ->
    None

let string_in_range raw start end_ =
  try
    String.sub raw.text start (end_ - start)
  with _ -> (* TODO: ERROR *)
    ""

let apply_text_edit raw (Range.{start; end_}, editText) =
  let start = loc_of_position raw start in
  let stop = loc_of_position raw end_ in
  let before = String.sub raw.text 0 start in
  let after = String.sub raw.text stop (String.length raw.text - stop) in
  let new_text = before ^ editText ^ after in (* FIXME avoid concatenation *)
  let new_lines = compute_lines new_text in (* FIXME compute this incrementally *)
  { text = new_text; lines = new_lines }, start
