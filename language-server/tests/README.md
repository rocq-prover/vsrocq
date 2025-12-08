Survival guide
==============

To enable logging of, say, `document.diff`:
```shell
VSROCQ_ARGS=-vsrocq-d,document.diff dune test
```

To run only one test, edit `dune` and uncomment:
```lisp
  (inline_tests 
    ; (flags (-only-test d_tests.ml:28))
  )
```
the syntax is `<file_name>:<line_of_let%test..>`, i.e. line 28 of `d_test.ml` has:
```ocaml
let%test_unit "diff.3" = 
```
