# Builtin indices

We scrape the official Rocq documentation to collect metadata that can be used to serve completions to LSP users.

While some things can be collected by semantic analysis (such as user defined or library defined lemmas/definitions), a large part of core Rocq are compiler builtins. This includes [commands](https://rocq-prover.org/doc/V9.2.0/refman/rocq-cmdindex.html) (like `Hint Rewrite`), [options](https://rocq-prover.org/doc/V9.2.0/refman/rocq-optindex.html) (like `Set Printing All`), [Ltac1 tactics](https://rocq-prover.org/doc/V9.2.0/refman/rocq-tacindex.html) (like `eapply`), and even [attributes](https://rocq-prover.org/doc/V9.2.0/refman/rocq-attrindex.html) (like `#[refine]`).

The documentation and grammar for these builtins cannot be queried from `rocq-runtime` and thus need to be maintained separately. To do so, we first extend the doc generator for the official Rocq documentation to additionally generate JSON metadata description of all builtins. Then, we use those metadata files (called "indices") to serve completions to the user in a best-effort manner.

## Generating indices

We modify the Sphinx Rocq domain python generator to not only output the final HTML/PDF files of the entire documentation, but to additionally output those JSON indices. By directly inspecting the source documentation RST files, we can extract the grammar and documentation of builtins. This generator should be run and the indices stored in `indices/VERSION/*.json` for each Rocq version separately.

At the moment, this generator is implemented in a fork: https://github.com/shilangyu/rocq/tree/mw/computer-indices. Ideally this would be merged to the official Rocq repository.

To generate indices, simply run `make refman-indices`.

## Usage by `vsrocqtop`

The indices are embedded in the final `vsrocqtop` binary to be used to serve completion requests. See [completionItems.ml](../completionItems.ml) to see the embedding.

Then, throughout different places these parsed indices are used to answer LSP requests.

## Known limitations

- The collected documentation for builtins can have wonky formatting. For example, sometimes the documentation can have plain-text ascii tables which do not render well. This can be improved with further heuristics when turning the official docs into index files.
- Completion snippets might not give an optimal experience. Again, can be improved with better heuristics.
