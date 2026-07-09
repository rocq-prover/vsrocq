open Base

type raw = { lines : int array }

let rec position_of_loc_bisect raw loc i m n len =
  (* Printf.eprintf "%i | %i(%d) <= %i(%d) < %i(%d)\n" loc m raw.lines.(m) i raw.lines.(i) n raw.lines.(n); *)
  if i = len || i = n || raw.lines.(i) <= loc && loc < raw.lines.(i+1) then i
  else if loc < raw.lines.(i) then position_of_loc_bisect raw loc (m + (max 1 ((i - m) / 2))) m i len
  else position_of_loc_bisect raw loc (i + (max 1 ((n - i) / 2))) i n len

let go raw loc =
  let nlines = Array.length raw.lines in
  let line = if loc = 0 then 0 else position_of_loc_bisect raw loc (nlines/2) 0 (nlines-1) (nlines-1) in
  line

let raw = { lines = Array.init 5 ~f:(fun i -> i * 5) }

let%test_unit "bisect hole" =
  [%test_eq: int] (go raw 0) 0;
  let last = ref 0 in
  for i = 0 to 41 do
    let p = go raw i in
    [%test_pred: int] ((<=) !last) p;
    last := p;
  done

let raw = { lines = Array.init 5 ~f:(fun i -> i) }

let%test_unit "bisect hole" =
  [%test_eq: int] (go raw 0) 0;
  let last = ref 0 in
  for i = 0 to 41 do
    let p = go raw i in
    [%test_pred: int] ((<=) !last) p;
    last := p;
  done

