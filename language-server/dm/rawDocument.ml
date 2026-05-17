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
  is_ascii : bool array; (* whether lines are ascii-only *)
}

let compute_lines text =
  let len = String.length text in
  let rec loop idx current_ascii acc_lines acc_ascii =
    if idx >= len then
      let final_lines = Array.of_list (List.rev acc_lines) in
      let final_ascii = Array.of_list (List.rev (current_ascii :: acc_ascii)) in
      (final_lines, final_ascii)
    else
      let c = String.unsafe_get text idx in
      if c = '\n' then
        loop (idx + 1) true ((idx + 1) :: acc_lines) (current_ascii :: acc_ascii)
      else
        loop (idx + 1) (current_ascii && Char.code c < 128) acc_lines acc_ascii
  in
  loop 0 true [0] []

let create text =
  let lines, is_ascii = compute_lines text in
  { text; lines; is_ascii }

let text t = t.text

let line_count raw =
  Array.length raw.lines

let line_span raw i =
  if i + 1 < Array.length raw.lines then
   (raw.lines.(i), raw.lines.(i+1) - raw.lines.(i))
  else
   (raw.lines.(i), String.length raw.text - raw.lines.(i))

(* first non-whitespace character position in a line *)
let line_nonwhitespace_start raw i =
  let start, end_ = line_span raw i in
  let length = end_ - start in
  let rec loop j =
    if j >= length then None
    else if raw.text.[start + j] = ' ' || raw.text.[start + j] = '\t' then
      loop (j + 1)
    else Some j
  in
  Option.map (fun col -> Position.create ~line:i ~character:col) (loop 0)

(* UTF8 byte -> UTF16 code unit position *)
let code_unit_pos_of_loc raw line_idx loc =
  let line_start, line_len = line_span raw line_idx in
  let loc = max 0 (min loc line_len) in
  if raw.is_ascii.(line_idx) then
    (* ASCII fast path: character position == byte offset *)
    loc
  else
    let rec loop byte_offset utf16_count =
      if byte_offset >= loc then
        utf16_count
      else
        let d = String.get_utf_8_uchar raw.text (line_start + byte_offset) in
        let byte_len = Uchar.utf_decode_length d in
        let u = Uchar.utf_decode_uchar d in
        (* handle UTF16 properly, code-points above 0xFFFF take two units to encode *)
        let units = if Uchar.to_int u > 0xFFFF then 2 else 1 in
        loop (byte_offset + byte_len) (utf16_count + units)
    in
    loop 0 0

(* UTF16 code unit position -> UTF8 byte *)
let loc_of_code_unit_pos raw line_idx pos =
  let line_start, line_len = line_span raw line_idx in
  let pos = max 0 (min pos line_len) in
  if raw.is_ascii.(line_idx) then
    (* ASCII fast path: character position == byte offset *)
    pos
  else
    let rec loop byte_offset utf16_count =
      if utf16_count >= pos then
        byte_offset
      else
        let d = String.get_utf_8_uchar raw.text (line_start + byte_offset) in
        let byte_len = Uchar.utf_decode_length d in
        let u = Uchar.utf_decode_uchar d in
        (* handle UTF16 properly, code-points above 0xFFFF take two units to encode *)
        let units = if Uchar.to_int u > 0xFFFF then 2 else 1 in
        loop (byte_offset + byte_len) (utf16_count + units)
    in
    loop 0 0

let line_of_loc raw loc =
  let nlines = line_count raw in
  let rec aux low high =
    if low > high then max 0 high
    else
      let mid = low + (high - low) / 2 in
      if raw.lines.(mid) <= loc then
        if mid = nlines - 1 || loc < raw.lines.(mid + 1) then
          mid
        else
          aux (mid + 1) high
      else
        aux low (mid - 1)
  in
  aux 0 (nlines - 1)

let position_of_loc raw loc =
  let line = line_of_loc raw loc in
  let character = code_unit_pos_of_loc raw line (loc - raw.lines.(line)) in
  Position.{ line; character }

let loc_of_position raw Position.{ line; character } =
  let nlines = line_count raw in
  let line = max 0 (min line (nlines - 1)) in
  let charloc = loc_of_code_unit_pos raw line character in
  raw.lines.(line) + charloc

let end_loc raw =
  String.length raw.text

let range_of_loc raw loc =
  let open Range in
  { start = position_of_loc raw loc.Loc.bp;
    end_  = position_of_loc raw loc.Loc.ep;
  }

let word_back_reg = Str.regexp {|[^a-zA-Z_0-9.']|}
let word_forward_reg = Str.regexp {|[^a-zA-Z_0-9']|}

let word_at_loc raw loc : string option =
  try
    let start_ind = loc in
    (* Search backwards until we find a character that cannot be part of a word *)
    let first_non_word_ind = Str.search_backward word_back_reg raw.text start_ind in
    let first_word_ind = first_non_word_ind + 1 in
    (* Search forwards ensuring that all characters are part of a well defined word. (Cannot start with [0-9'.] and cannot end with .)*)
    let last_word_ind = Str.search_forward word_forward_reg raw.text start_ind in
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
  let new_lines, new_is_ascii = compute_lines new_text in (* FIXME compute this incrementally *)
  { text = new_text; lines = new_lines; is_ascii = new_is_ascii }, start
