open Bechamel
open Toolkit

let benchmark tests =
  let ols = Analyze.ols ~bootstrap:0 ~r_square:true ~predictors:Measure.[| run |] in
  let instances = Instance.[ monotonic_clock ] in
  let cfg = Benchmark.cfg ~quota:(Time.second 5.) () in
  let raw_results = Hashtbl.create (List.length tests) in
  List.iter
    (fun test ->
      let results = Benchmark.run cfg instances test in
      Hashtbl.add raw_results (Test.Elt.name test) results)
    tests;
  let results = List.map (fun instance -> Analyze.all ols instance raw_results) instances in
  Analyze.merge ols instances results

let print results =
  let format_time ns =
    if ns < 1000.0 then Printf.sprintf "%7.2f ns/run" ns
    else if ns < 1_000_000.0 then Printf.sprintf "%7.2f us/run" (ns /. 1000.0)
    else if ns < 1_000_000_000.0 then Printf.sprintf "%7.2f ms/run" (ns /. 1_000_000.0)
    else Printf.sprintf "%7.2f  s/run" (ns /. 1_000_000_000.0)
  in
  let get_estimate target_predictor analyze =
    match Analyze.OLS.estimates analyze with
    | None -> None
    | Some estimates ->
        let predictors = Analyze.OLS.predictors analyze in
        List.fold_left2 (fun acc est pred ->
          if String.equal pred target_predictor then Some est else acc
        ) None estimates predictors
  in

  match Hashtbl.find_opt results "monotonic-clock" with
  | None -> print_endline "Error: No monotonic-clock results found."
  | Some tests ->
      let tests_list = Hashtbl.fold (fun k v acc -> (k, v) :: acc) tests [] in
      let sorted_tests = List.sort (fun (name1, _) (name2, _) -> String.compare name1 name2) tests_list in
      let max_name_len =
        List.fold_left (fun acc (name, _) -> max acc (String.length name)) 20 tests_list
      in

      Printf.printf "\n%-*s %s\n" max_name_len "Test Name" "Time";
      Printf.printf "%s\n" (String.make (max_name_len + 16) '-');

      List.iter (fun (test_name, analyze) ->
        match get_estimate Measure.run analyze with
        | Some time_per_run ->
            Printf.printf "%-*s %s\n" max_name_len test_name (format_time time_per_run)
        | None ->
            Printf.printf "%-*s %s\n" max_name_len test_name "N/A (Metric missing)"
      ) sorted_tests

let filter_suite pattern suite =
  let is_match elt =
    let name = Test.Elt.name elt in
    try
      let _ = Str.search_forward pattern name 0 in
      true
    with Not_found -> false
  in
  List.filter is_match (Test.elements suite)

let () =
  let pattern =
    if Array.length Sys.argv > 1 then Sys.argv.(1) else ".*"
  in
  let suite = Test.make_grouped ~name:"" [Entries.suite; Text.suite] in
  let tests = filter_suite (Str.regexp pattern) suite in
  let merged = benchmark tests in
  print merged
