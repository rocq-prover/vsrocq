Callgraph Tool
==============

This directory contains a static callgraph tool for the Document Manager and a
cram test that checks its output against a checked-in reference report. The objective is to ensure all Rocq stateful APIs are serialized via Dm.ProverThread APIs.

Files
-----

- `static_callgraph.ml`: OCaml program that reads typed `.cmt` files and emits
  call chains on standard output.
- `static_callgraph_whitelist.txt`: line-based whitelist of regular
  expressions used to suppress selected terminal entries from the report.
- `run.t`: cram test that runs the tool on `Dm__DocumentManager.cmt` and
  compares the output with the checked-in reference.

What The Tool Does
------------------

The tool analyzes OCaml typed ASTs from `.cmt` files produced by the build and
computes call chains rooted in the same library as the input module.

Example call:

```shell
dune exec tests/callgraph/static_callgraph.exe -- `find _build  -path */byte/dm__DocumentManager.cmt
```

The output is a text report on standard output, one call chain per line. The tool accepts a `--whitelist path/to/file` option to prune call chains ending in whitelisted entries.

Whitelist Format
----------------

The whitelist file is line-based.

- Empty lines are ignored.
- Lines whose first non-space content is `#` are ignored.
- Trailing comments starting with `#` are stripped before parsing the regex.
- Remaining non-empty content is interpreted as an OCaml `Str.regexp`.

Examples:

```text
# External libraries
Unix\..*
Pp\..*     # pretty-printing helpers
```

Provenance
----------

This section was also written by GitHub Copilot using GPT-5.4.

The code in this directory, in particular `static_callgraph.ml`, was generated
by GitHub Copilot using GPT-5.4 during interactive development in this
repository.

No external source file was copied verbatim into this directory.

The main sources of inspiration were:

- OCaml's public `compiler-libs` APIs and data structures, especially the
  modules and concepts exposed through `Cmt_format`, `Typedtree`,
  `Tast_iterator`, `Path`, and `Ident`.
- OCaml's `Str` library API for whitelist regex handling.
- The structure and naming conventions already present in this repository,
  especially the `dm/` modules being analyzed and the existing Dune / test
  layout under `tests/`.

In other words, the tool was written against those APIs and repository-local
conventions, but it is not a verbatim copy of OCaml compiler code, Dune code,
or code from another repository.

License
-------

At the time of writing, in the USA, the code of `static_callgraph.ml` cannot be copyrighted since it has been produced by generative AI.

Other files are under MIT license, copyrighted by the authors of VSRocq.