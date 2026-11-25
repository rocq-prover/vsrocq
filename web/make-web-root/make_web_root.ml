(* Make a trimmed copy of an opam switch, to be served as static files
   (e.g. GitHub Pages) to the web language server (lazyfs.js, worker.js).

   It keeps what the wasm language server reads at run time:
   - the .vo files of Rocq's coqlib (Corelib and user-contrib);
   - findlib.conf, the META files and the bytecode (.cma, .cmo) of the
     findlib packages needed by Rocq plugins (the plugins of rocq-runtime and
     of the packages depending on it);
   - the wasm language server (vsrocq-language-server-web) and rocq-web.

   It writes manifest.json at the root of the output:
     prefix      the prefix of the switch: the files are mounted there, so
                 that the absolute paths compiled in the programs keep working
     files       the files, relative to the prefix, with their size
     compressed  the files published compressed with gzip, at their path
                 followed by "z" (e.g. Foo.voz), with their compressed size
     opaques     false if the opaque proofs were stripped from the .vo files
     server      the server (relative path), worker and lazyfs: the JS files
     rocq        the programs of rocq-web (rocq c, rocq dep), runner: their
                 JS glue
     args        the command line of the server
     prefetch    files to fetch before starting the server
     packages    the versions of the installed opam packages
     unloadable  the .vo and .cma files that cannot be loaded with 31-bit
                 integers (see check_int31), with the reason

   wasm_of_ocaml represents OCaml integers as 31-bit i31ref values. A file
   written by a native (63-bit) program that contains a larger integer, e.g.
   max_int in a .vo file or a large literal in the bytecode of a plugin,
   fails to load with "input_value: integer too large". Such files are
   reported, and --strict makes them an error.

   --strip-opaques replaces the table of opaque proofs of each .vo file
   (the "opaques" segment, the bodies of the constants ended by Qed) by a
   table of the same length with no proof. Rocq reads it only to print such
   a body or for Print Assumptions, which then reports the proofs it cannot
   read. The digest of a library, which the files requiring it check, is
   the one of the "library" segment, which does not change.

   This tool must be built with the Rocq of the switch (it reads and writes
   .vo files with Rocq's ObjFile). *)

let usage = "vsrocq-make-web-root [OPTIONS] OUTDIR"

(* processes *)

let run cmd =
  let ic = Unix.open_process_args_in cmd.(0) cmd in
  let out = In_channel.input_all ic in
  match Unix.close_process_in ic with
  | Unix.WEXITED 0 -> out
  | _ -> failwith (String.concat " " (Array.to_list cmd) ^ " failed")

let lines s = String.split_on_char '\n' s |> List.filter (fun l -> String.trim l <> "")

(* files *)

let rec mkdir_p d =
  if not (Sys.file_exists d) then begin
    mkdir_p (Filename.dirname d);
    try Sys.mkdir d 0o755 with Sys_error _ when Sys.is_directory d -> ()
  end

let size f = (Unix.stat f).Unix.st_size

let read_file f = In_channel.with_open_bin f In_channel.input_all
let write_file f s = Out_channel.with_open_bin f (fun oc -> Out_channel.output_string oc s)

let copy_file src dst =
  In_channel.with_open_bin src (fun ic ->
    Out_channel.with_open_bin dst (fun oc ->
      let buf = Bytes.create 65536 in
      let rec loop () =
        let n = In_channel.input ic buf 0 65536 in
        if n > 0 then (Out_channel.output oc buf 0 n; loop ()) in
      loop ()))

(* the files under d whose name satisfies keep (like os.walk, symbolic links
   to directories are not followed) *)
let rec walk d keep acc =
  Array.fold_left (fun acc n ->
    let p = Filename.concat d n in
    match (Unix.lstat p).Unix.st_kind with
    | Unix.S_DIR -> walk p keep acc
    | _ when keep n -> p :: acc
    | _ -> acc) acc (Sys.readdir d)

let has_suffix s l = List.exists (fun x -> String.ends_with ~suffix:x s) l
let has_prefix s l = List.exists (fun x -> String.starts_with ~prefix:x s) l

(* OCaml's Marshal format (runtime/caml/intext.h) *)

let magic_small = 0x8495A6BE
let magic_big = 0x8495A6BF
let int31 = 1 lsl 30

exception Not_marshaled

(* Scan the marshaled value starting at pos; return (end, n) where n is the
   number of integers that do not fit in 31 bits *)
let large_ints_in_marshal s pos =
  let u8 p = Char.code s.[p] in
  let u32 p = Int32.to_int (String.get_int32_be s p) land 0xFFFFFFFF in
  let u64 p = Int64.to_int (String.get_int64_be s p) in
  let pos = match u32 pos with
    | m when m = magic_small -> pos + 20
    | m when m = magic_big -> pos + 32
    | _ -> raise Not_marshaled in
  let pos = ref pos and todo = ref 1 and n = ref 0 in
  let large v = if v < - int31 || v >= int31 then incr n in
  while !todo > 0 do
    decr todo;
    let c = u8 !pos in
    incr pos;
    let p = !pos in
    let skip k = pos := p + k in
    if c >= 0x80 then todo := !todo + ((c lsr 4) land 7)   (* small block *)
    else if c >= 0x40 then ()                               (* small int *)
    else if c >= 0x20 then skip (c land 0x1F)               (* small string *)
    else match c with
      | 0x00 | 0x04 -> skip 1                               (* int8, shared8 *)
      | 0x01 | 0x05 -> skip 2                               (* int16, shared16 *)
      | 0x02 -> large (Int32.to_int (String.get_int32_be s p)); skip 4
      | 0x03 -> large (Int64.to_int (String.get_int64_be s p)); skip 8
      | 0x06 -> skip 4                                      (* shared32 *)
      | 0x14 -> skip 8                                      (* shared64 *)
      | 0x08 -> todo := !todo + (u32 p lsr 10); skip 4      (* block32 *)
      | 0x13 -> todo := !todo + (u64 p lsr 10); skip 8      (* block64 *)
      | 0x09 -> skip (1 + u8 p)                             (* string8 *)
      | 0x0A -> skip (4 + u32 p)                            (* string32 *)
      | 0x15 -> skip (8 + u64 p)                            (* string64 *)
      | 0x0B | 0x0C -> skip 8                               (* double *)
      | 0x0D | 0x0E -> skip (1 + 8 * u8 p)                  (* double array8 *)
      | 0x07 | 0x0F -> skip (4 + 8 * u32 p)                 (* double array32 *)
      | 0x16 | 0x17 -> skip (8 + 8 * u64 p)                 (* double array64 *)
      | 0x12 | 0x18 | 0x19 ->                               (* custom blocks *)
          let e = String.index_from s p '\000' in
          let ident = String.sub s p (e - p) in
          let p = e + 1 in
          if c = 0x18 then pos := p + 12 + u64 (p + 4)      (* custom_len *)
          else begin match ident with
            | "_j" -> pos := p + 8                          (* Int64 *)
            | "_i" -> pos := p + 4                          (* Int32 *)
            | "_n" -> pos := p + 1 + (if u8 p = 1 then 4 else 8)  (* Nativeint *)
            | _ -> raise Not_marshaled
          end
      | _ -> raise Not_marshaled
  done;
  !pos, !n

(* None if the marshaled data in the file (.vo segments, .cma descriptors
   and constants) only contains integers fitting in 31 bits, else the
   reason *)
let check_int31 path =
  let s = read_file path in
  let magics = List.map (fun m ->
    let b = Bytes.create 4 in Bytes.set_int32_be b 0 (Int32.of_int m); Bytes.to_string b)
    [magic_small; magic_big] in
  let find m from =
    let lm = String.length m and ls = String.length s in
    let rec go i =
      if i + lm > ls then None
      else if String.sub s i lm = m then Some i
      else match String.index_from_opt s (i + 1) m.[0] with
        | None -> None
        | Some j -> go j in
    match String.index_from_opt s from m.[0] with None -> None | Some i -> go i in
  let rec loop pos n =
    match List.filter_map (fun m -> find m pos) magics with
    | [] -> n
    | starts ->
        let start = List.fold_left min max_int starts in
        match large_ints_in_marshal s start with
        | pos, k -> loop pos (n + k)
        | exception (Not_marshaled | Invalid_argument _ | Not_found) -> loop (start + 4) n in
  match loop 0 0 with
  | 0 -> None
  | n -> Some (Printf.sprintf "%d integers do not fit in 31 bits" n)

(* .vo files *)

(* Copy the .vo file src to dst, replacing the table of opaque proofs by a
   table of the same length with no proof: its type is an option array
   (Opaques.opaque_disk), and None is what a delayed proof (-vos) looks
   like. The other segments are copied unchanged. ObjFile computes the hash
   of each segment, and writes the table of segments. *)
let strip_opaques ~src ~dst =
  let ih = ObjFile.open_in ~file:src in
  let segs = CString.Map.bindings (ObjFile.segments ih)
    |> List.sort (fun (_, a) (_, b) -> Int64.compare a.ObjFile.pos b.ObjFile.pos) in
  let oh = ObjFile.open_out ~file:dst in
  In_channel.with_open_bin src (fun ic ->
    List.iter (fun (name, s) ->
      let segment = ObjFile.make_id name in
      if name = "opaques" then
        let (t : Obj.t option array), _ = ObjFile.marshal_in_segment ih ~segment in
        ObjFile.marshal_out_segment oh ~segment (Array.make (Array.length t) None)
      else
        let oc, stop = ObjFile.marshal_out_binary oh ~segment in
        In_channel.seek ic s.ObjFile.pos;
        let data = really_input_string ic (Int64.to_int s.ObjFile.len) in
        Out_channel.output_string oc data;
        stop ()) segs);
  ObjFile.close_in ih;
  ObjFile.close_out oh

let gzip ~level ~src ~dst =
  let cmd = Printf.sprintf "gzip -n -%d -c %s > %s" level (Filename.quote src) (Filename.quote dst) in
  if Sys.command cmd <> 0 then failwith (cmd ^ " failed")

(* main *)

let () =
  let prefix = ref (Sys.getenv_opt "OPAM_SWITCH_PREFIX") in
  let dry_run = ref false and strict = ref false in
  let strip = ref false and compress = ref false and level = ref 9 in
  let out = ref None in
  Arg.parse (Arg.align [
    "--prefix", Arg.String (fun s -> prefix := Some s),
      "PREFIX the prefix of the opam switch (default: $OPAM_SWITCH_PREFIX)";
    "--dry-run", Arg.Set dry_run, " only print the sizes";
    "--strict", Arg.Set strict, " fail if a file cannot be loaded with 31-bit integers";
    "--strip-opaques", Arg.Set strip, " strip the opaque proofs from the .vo files";
    "--compress", Arg.Set compress,
      " publish the .vo, .cma and .cmo files compressed with gzip (e.g. Foo.voz)";
    "--level", Arg.Set_int level, "N the gzip compression level (default: 9)";
  ]) (fun s -> out := Some s) usage;
  let prefix = match !prefix with
    | Some p -> Unix.realpath p
    | None -> prerr_endline "no --prefix and no OPAM_SWITCH_PREFIX"; exit 2 in
  let out = match !out, !dry_run with
    | Some o, _ -> o
    | None, true -> Filename.get_temp_dir_name ()
    | None, false -> Arg.usage [] usage; exit 2 in
  let lib = Filename.concat prefix "lib" in
  let files = Hashtbl.create 2048 in (* relative path -> size *)
  let add path =
    let path = Unix.realpath path in
    if not (String.starts_with ~prefix:(prefix ^ "/") path) then begin
      Printf.eprintf "%s is not in %s\n" path prefix; exit 1 end;
    let rel = String.sub path (String.length prefix + 1) (String.length path - String.length prefix - 1) in
    Hashtbl.replace files rel (size path) in
  let add_tree d keep = List.iter add (walk d keep []) in

  (* findlib *)
  let findlib_conf = Filename.concat lib "findlib.conf" in
  Unix.putenv "OCAMLFIND_CONF" findlib_conf;
  Findlib.init ~config:findlib_conf ();
  add findlib_conf;
  if Sys.file_exists (findlib_conf ^ ".d") then add_tree (findlib_conf ^ ".d") (fun _ -> true);

  (* Rocq plugins and their dependencies *)
  let pkgs = Fl_package_base.list_packages () |> List.sort compare in
  let deep ps = try Fl_package_base.requires_deeply ~preds:[] ps with _ -> [] in
  let roots = List.filter (fun p -> String.starts_with ~prefix:"rocq-runtime.plugins." p) pkgs in
  (* plugins can be subpackages (e.g. rocq-elpi.elpi, whose parent requires
     nothing), so look at all the packages; the libraries of the language
     server also require Rocq, but they are linked in the server *)
  let roots = roots @ List.filter (fun p ->
    not (has_prefix p ["rocq-runtime"; "vsrocq-language-server"]) &&
    let req = deep [p] in
    List.mem "rocq-runtime.kernel" req || List.mem "rocq-runtime.vernac" req) pkgs in
  let closure = List.sort_uniq compare (roots @ deep roots) in
  (* the packages linked in the programs: only their META is needed *)
  let linked = deep (["rocq-runtime.toplevel"; "rocq-runtime.tactics"] @
    List.filter (fun p -> List.mem p pkgs) ["vsrocq-language-server.server"]) in
  let dirs = List.fold_left (fun dirs p ->
    let d = Findlib.package_directory p in
    let meta = (Fl_package_base.query p).Fl_package_base.package_meta in
    if Sys.file_exists meta then add meta;
    if List.mem p linked then dirs else d :: dirs) [] closure in
  List.iter (fun d ->
    Array.iter (fun n ->
      if has_suffix n [".cma"; ".cmo"] then add (Filename.concat d n)) (Sys.readdir d))
    (List.sort_uniq compare dirs);

  (* Rocq *)
  let coqlib = String.trim (run [|"rocq"; "c"; "-where"|]) in
  add_tree coqlib (fun n -> has_suffix n [".vo"; ".vos"]);
  let rev = Filename.concat lib "rocq-runtime/revision" in
  if Sys.file_exists rev then add rev;

  (* the programs *)
  List.iter (fun pkg ->
    let d = Filename.concat lib pkg in
    if Sys.file_exists d then add_tree d (fun n -> has_suffix n [".js"; ".wasm"]))
    ["vsrocq-language-server-web"; "rocq-web"];

  let rels = Hashtbl.fold (fun k _ acc -> k :: acc) files [] |> List.sort compare in

  (* prefetch: Init, the plugins it loads, the META files *)
  let init = Filename.concat coqlib "theories/Init" in
  let rel_init =
    let r = Unix.realpath init in
    String.sub r (String.length prefix + 1) (String.length r - String.length prefix - 1) in
  let prefetch = List.filter (fun f ->
    String.starts_with ~prefix:(rel_init ^ "/") f || has_suffix f ["META"; "findlib.conf"]) rels in
  let ml_modules v =
    let s = read_file v and key = "Declare ML Module \"" in
    let rec go i acc =
      match Str.search_forward (Str.regexp_string key) s i with
      | j ->
          let b = j + String.length key in
          let e = String.index_from s b '"' in
          go e (String.sub s b (e - b) :: acc)
      | exception Not_found -> acc in
    go 0 [] in
  let prefetch = prefetch @ List.concat_map (fun v ->
    if not (Filename.check_suffix v ".v") then [] else
    List.concat_map (fun m ->
      let d = Findlib.package_directory m in
      List.filter (fun f -> Filename.dirname (Filename.concat prefix f) = d
                            && Filename.check_suffix f ".cma") rels)
      (ml_modules (Filename.concat init v))) (Array.to_list (Sys.readdir init)) in
  let prefetch = List.sort_uniq compare prefetch in

  (* write the files: strip, check, compress *)
  let tmp = Filename.temp_file "make-web-root" ".vo" in
  let compressed = ref [] and unloadable = ref [] and out_size = ref 0 in
  List.iter (fun rel ->
    let src = Filename.concat prefix rel in
    let src =
      if !strip && Filename.check_suffix rel ".vo" then (strip_opaques ~src ~dst:tmp; tmp)
      else src in
    Hashtbl.replace files rel (size src);
    if has_suffix rel [".vo"; ".cma"] then
      Option.iter (fun r -> unloadable := (rel, r) :: !unloadable) (check_int31 src);
    let dst = Filename.concat out rel in
    if !compress && has_suffix rel [".vo"; ".cma"; ".cmo"] then begin
      let dst = if !dry_run then tmp ^ "z" else dst ^ "z" in
      if not !dry_run then mkdir_p (Filename.dirname dst);
      gzip ~level:!level ~src ~dst;
      compressed := (rel, size dst) :: !compressed;
      out_size := !out_size + size dst
    end else begin
      out_size := !out_size + size src;
      if not !dry_run then (mkdir_p (Filename.dirname dst); copy_file src dst)
    end) rels;
  List.iter Sys.remove (List.filter Sys.file_exists [tmp; tmp ^ "z"]);
  let unloadable = List.rev !unloadable and compressed = List.rev !compressed in
  List.iter (fun (rel, r) ->
    Printf.eprintf "warning: %s cannot be loaded with 31-bit integers: %s\n" rel r) unloadable;

  let srv = "lib/vsrocq-language-server-web" in
  let packages = lines (run [|"opam"; "list"; "--installed"; "--short"; "--columns=name,version"|])
    |> List.filter_map (fun l ->
      match String.split_on_char ' ' l |> List.filter ((<>) "") with
      | n :: v :: _ -> Some (n, `String v) | _ -> None) in
  let str s = `String s and assoc l f = `Assoc (List.map (fun (k, v) -> k, f v) l) in
  let manifest = `Assoc ([
    "version", `Int 1;
    "prefix", str prefix;
    "server", str (srv ^ "/vsrocq_web.bc.wasm.js");
    "worker", str (srv ^ "/worker.js");
    "lazyfs", str (srv ^ "/lazyfs.js");
    "runner", str (srv ^ "/runner.js");
    "rocq", `Assoc ["c", str "lib/rocq-web/rocq_c.bc.wasm.js";
                    "dep", str "lib/rocq-web/rocq_dep.bc.wasm.js"];
    "args", `List (List.map str ["-coqlib"; coqlib; "-bytecode-compiler"; "no"]);
    "prefetch", `List (List.map str prefetch);
    "packages", `Assoc packages;
    "files", assoc (List.map (fun r -> r, Hashtbl.find files r) rels) (fun n -> `Int n);
    "unloadable", assoc unloadable str;
  ] @ (if compressed = [] then [] else ["compressed", assoc compressed (fun n -> `Int n)])
    @ (if !strip then ["opaques", `Bool false] else [])) in

  let total = List.fold_left (fun a r -> a + Hashtbl.find files r) 0 rels in
  let pre = List.fold_left (fun a r -> a + Hashtbl.find files r) 0 prefetch in
  let mb n = float_of_int n /. 1e6 in
  Printf.printf "%d files, %.1f MB; prefetch %d files, %.1f MB; published %.1f MB\n"
    (List.length rels) (mb total) (List.length prefetch) (mb pre) (mb !out_size);
  if unloadable <> [] then begin
    Printf.eprintf "%d files cannot be loaded with 31-bit integers\n" (List.length unloadable);
    if !strict then exit 1
  end;
  if not !dry_run then begin
    Out_channel.with_open_text (Filename.concat out "manifest.json") (fun oc ->
      Yojson.Safe.pretty_to_channel oc manifest);
    (* GitHub Pages: do not process the files with Jekyll *)
    write_file (Filename.concat out ".nojekyll") ""
  end
