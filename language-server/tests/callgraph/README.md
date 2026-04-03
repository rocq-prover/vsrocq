Callgraph Tool
==============

This directory contains a static callgraph tool for the Document Manager and a
cram test that checks its output against a checked-in reference report.
The objective is to ensure all Rocq stateful APIs are serialized via Dm.ProverThread APIs.

What The Tool Does
------------------

The tool analyzes OCaml typed ASTs from `.cmt` files produced by the build and
computes call chains rooted in the same library as the input module.

Example call:

```shell
dune exec tests/callgraph/static_callgraph.exe -- `find _build  -path */byte/dm__DocumentManager.cmt
```

Whitelist Format
----------------

The whitelist file is line-based, `#` starts a comment.

Example:

```text
# External libraries
Unix\..*
Pp\..*     # pretty-printing helpers
```

License
-------

The file `static_callgraph.ml` was generated with help from
GPT-5.4. At the time of writing, in the USA, the code of `static_callgraph.ml`
cannot be copyrighted since it has been produced by generative AI.

Other files are under MIT license, copyrighted by the authors of VSRocq.
