# vsrocq on the web (wasm_of_ocaml)

This branch builds the vsrocq language server with
[wasm_of_ocaml](https://github.com/ocsigen/js_of_ocaml), and adds a
`browser` entry to the extension, so that VsRocq runs in VS Code for the web
(vscode.dev).

The extension does not bundle Rocq. Rocq and the language server compiled
to WebAssembly come from an opam switch, a trimmed copy of which is
published as static files (e.g. on GitHub Pages); the setting
`vsrocq.web.root` points to it.

## Overview

```
opam switch                         published root (static files)
  rocq-runtime, rocq-core  ──────►   lib/coq/**.vo, plugins .cma, META,
  rocq-web, zarith_stubs_js          findlib.conf, the wasm server,
  vsrocq-language-server(-web)       manifest.json
          vsrocq-make-web-root              │ fetch (CORS)
                                            ▼
VS Code for the web: extension (dist/web) ─► Web Worker (bootstrap.js,
                                              worker.js, lazyfs.js, server)
```

- **The libraries, plugins and `.vo` files are those of the native Rocq.**
  The bytecode of the Rocq libraries works with 31-bit integers (the
  implementation of `Uint63` is chosen at run time), so the wasm programs
  link the installed libraries, and plugins (`.cma`) are loaded with
  `Dynlink` (wasm_of_ocaml compiles their bytecode at load time). A `.vo`
  containing an integer that does not fit in 31 bits fails to load with
  `input_value: integer too large`.
- **No threads, no processes.** Rocq runs in the worker's only thread; there
  is no proof delegation. Interruption is cooperative (see below).
- **Files.** In the worker, the published files are mounted at the prefix
  of the original switch, so the paths compiled in the programs
  (`findlib.conf`, Rocq's coqlib) work unchanged. They are fetched when
  opened (synchronous XHR), except the ones needed at startup, which are
  prefetched in parallel.

## Packages

| Package | Where | Content |
|---|---|---|
| `zarith_stubs_js` | [janestreet/zarith_stubs_js](https://github.com/janestreet/zarith_stubs_js), `master` (the wasm support is not released yet) | The C primitives of Zarith for wasm_of_ocaml (on JavaScript `BigInt`), so that the unmodified `zarith` can be linked, and plugins compiled against it loaded |
| `rocq-web` | Rocq, `web/` | `rocq-web.stubs` (single-threaded `Thread`, `Unix.getpid`), `lib/rocq-web/rocq_c.bc.wasm.js` (`rocq c`) and `rocq_dep.bc.wasm.js` (`rocq dep`) |
| `vsrocq-language-server` | `language-server/` | Now also installs `dm.web`, the implementation of dm for the web |
| `vsrocq-language-server-web` | `web/` | `lib/vsrocq-language-server-web/`: the wasm server, `worker.js`, `runner.js`, `lazyfs.js`, `node-bridge.js`; `bin/vsrocq-make-web-root` |

## Changes upstream

These are separate PRs. Until they are merged, use these branches.

- **Rocq**, branch `web` of [gares/coq](https://github.com/gares/coq/tree/web),
  [rocq-prover/rocq#22875](https://github.com/rocq-prover/rocq/pull/22875):
  - `Uint63`: the implementation is selected at run time (`Sys.int_size`),
    and on 31 bits it also accepts the immediates of native `.vo` files. In
    native code the test is a constant: the functions are still inlined.
  - `kernel/byterun/rocq_wasm.wat`: the kernel primitives used at
    initialization time (the VM is not available);
  - `CObj` no longer inspects a boxed float for `size_of_double`;
  - `Control.set_interrupt_poll`, a hook polled by `check_for_interrupt`;
  - plugins mask their hashes with `0x3FFFFFFF`; the cached hash of universe
    levels is truncated to 30 bits, as `KerName.make` already does;
  - `canonical_path_name` and `rocq dep` compute absolute paths without
    `chdir`, which is not available in workers;
  - the `rocq-web` package.
- **wasm_of_ocaml** (js_of_ocaml), branches of
  [gares/js_of_ocaml](https://github.com/gares/js_of_ocaml) on master:
  `tail-call-stack` ([ocsigen/js_of_ocaml#2642](https://github.com/ocsigen/js_of_ocaml/pull/2642)),
  `jsoo-fs` ([#2643](https://github.com/ocsigen/js_of_ocaml/pull/2643)),
  `jsoo-argv` ([#2644](https://github.com/ocsigen/js_of_ocaml/pull/2644)),
  `jsoo-exit` ([#2645](https://github.com/ocsigen/js_of_ocaml/pull/2645));
  all of them on 6.5.0 in
  [`web-6.5`](https://github.com/gares/js_of_ocaml/tree/web-6.5):
  - `Tail_call.instructions` is tail-recursive: compiling a large plugin
    at run time overflowed the stack of a browser worker;
  - outside of node, the runtime uses the file system given as
    `globalThis.jsoo_fs` (the API of `node:fs`), the command line given
    as `globalThis.jsoo_argv`, like `globalThis.jsoo_env`, and reports the
    exit code to `globalThis.jsoo_exit`.
- **sel**, branch `web` of [gares/sel](https://github.com/gares/sel/tree/web),
  [gares/sel#19](https://github.com/gares/sel/pull/19): `sel` is Unix-free,
  the system events are an extension point (`Sel.System_event`); the Unix
  events and backend are in `sel.unix`; `sel.js` provides a backend and a
  driver (`Sel_js.run`) handling the events from the JavaScript event loop.
  Also adds the non-blocking `pop_ready`/`wait_ready`.
- **Elpi**, branch `wasm-portable-depth` (on v4.1.1) of
  [LPCIC/elpi](https://github.com/LPCIC/elpi/tree/wasm-portable-depth): the indexing depth
  of the inputs of builtin predicates is `2^30-1` instead of `max_int`.
  It is part of the compiled programs that rocq-elpi stores in `.vo`
  files, so native `.vo` files using Elpi (Elpi's apps, Hierarchy Builder,
  hence mathcomp) could not be read with 31-bit integers.
- **micromega-plugin**
  ([rocq-community/micromega-plugin](https://github.com/rocq-community/micromega-plugin)),
  not published yet: in `src/persistent_cache.ml`, hashes are masked with
  `0x3FFFFFFF` instead of `0x7FFFFFFF`, and `pcache_version` is bumped
  (the plugin used to be part of Rocq, where the same change is made). The
  constant `0x7FFFFFFF` does not fit in 31 bits, so the plugin (needed by
  mathcomp) could not be loaded.

### Changes in vsrocq

- dm uses the Unix-free `sel` (`dm/native` also uses `sel.unix`);
  `vsrocqtop` installs the backend of `sel.unix`, the web server runs the
  events with `Sel_js.run`.
- `ProverThread` and `DelegationManager` are virtual
  modules, `dm/native` (threads, memprof-limits, processes) and `dm/web`
  (Rocq runs synchronously and polls for interruptions through
  `Control.set_interrupt_poll`; no delegation, the delegation settings
  fall back to `CheckProofsInMaster`).
- LspManager is a library with a pluggable input and output.
- The memory limit is in megabytes (4GB does not fit in 31 bits).
- `web/`: the web server and its JavaScript glue, the root maker.
- LspManager keeps the URI of the documents (it rebuilt `file:` URIs).
- `client/`: the `browser` entry.
- The web server, like `rocq c` in `rocq-web`, allows plugins whose
  bytecode declares external primitives (`Dynlink.allow_unsafe_modules`):
  bytecode `Dynlink` refuses them by default, native `Dynlink` does not
  check. atdgen-runtime, needed by rocq-elpi, declares one.

## Building the switch

You need binaryen ≥ 119 (`wasm-opt`) and node ≥ 22.

```sh
opam switch create vsrocq-wasm 5.4.1
eval $(opam env --switch=vsrocq-wasm --set-switch)
opam pin add -n wasm_of_ocaml-compiler.6.5.0 "git+https://github.com/gares/js_of_ocaml.git#web-6.5"
opam pin add -n sel "git+https://github.com/gares/sel.git#web"
opam pin add -n zarith_stubs_js "git+https://github.com/janestreet/zarith_stubs_js.git#master"
for p in rocq-runtime rocq-core rocq-web; do opam pin add -n $p "git+https://github.com/gares/coq.git#web"; done
opam pin add -n vsrocq-language-server ./language-server
opam pin add -n vsrocq-language-server-web ./web
opam install vsrocq-language-server-web
```

For libraries beyond Corelib (Stdlib, mathcomp, Iris, ...), add the Rocq
opam repositories to the switch (its Rocq is a development version), the
patched Elpi and micromega-plugin, then install them:

```sh
opam repo add rocq-released https://rocq-prover.org/opam/released --this-switch
opam repo add rocq-core-dev https://rocq-prover.org/opam/core-dev --this-switch
opam repo add rocq-extra-dev https://rocq-prover.org/opam/extra-dev --this-switch
opam pin add -n elpi.4.1.1 "git+https://github.com/LPCIC/elpi.git#wasm-portable-depth"
git clone https://github.com/rocq-community/micromega-plugin.git   # then apply the patch above
opam pin add -n rocq-micromega-plugin.dev ./micromega-plugin
opam install rocq-mathcomp-analysis rocq-iris
```

`web/test/rocq-c/run.sh` then checks that they load.

`.github/workflows/web-root.yml` does the same on GitHub Actions and
publishes the root on GitHub Pages.

## Running

**Under node**, the server speaks LSP on stdio, like `vsrocqtop`:

```sh
L=$OPAM_SWITCH_PREFIX/lib/vsrocq-language-server-web
node $L/node-bridge.js $L/vsrocq_web.bc.wasm.js -coqlib $(rocq c -where) -bytecode-compiler no
R=$OPAM_SWITCH_PREFIX/lib/rocq-web
node $R/rocq_c.bc.wasm.js -bytecode-compiler no -coqlib $(rocq c -where) file.v
node $R/rocq_dep.bc.wasm.js -coqlib $(rocq c -where) file.v
```

**In a browser**:

```sh
vsrocq-make-web-root /tmp/root     # a trimmed copy of the switch, 43 MB
```

`vsrocq-make-web-root` (`web/make-web-root/`, written in OCaml and linked
with Rocq, since it reads and writes `.vo` files) also:

- warns about the `.vo` and `.cma` files that contain an integer that does
  not fit in 31 bits, which cannot be loaded (see "Known limitations"),
  and lists them in `manifest.json` (`unloadable`). `--strict` makes them
  an error;
- with `--strip-opaques`, removes the opaque proofs (the bodies of the
  constants ended by `Qed`) from the `.vo` files. `Print` of such a
  constant then fails, and `Print Assumptions` reports the proofs it
  cannot read. See [docs/web-roots.md](docs/web-roots.md);
- with `--compress`, publishes the `.vo`, `.cma` and `.cmo` files
  compressed with gzip (`Foo.voz`, `Foo.cmaz`), which `lazyfs.js`
  decompresses when it fetches them (`manifest.json`: `compressed`).

For the switch with Stdlib, mathcomp-analysis and Iris the published root
is 398 MB, 313 MB with `--strip-opaques`, 213 MB with `--compress`, and
156 MB with both.

- `web/test/`: the LSP smoke test in a page (`serve.py` serves the root
  like GitHub Pages, with CORS only, and the page cross-origin isolated).
- `web/test/rocq-c/run.sh`: compiles small files using Elpi, Hierarchy
  Builder, mathcomp, mathcomp-analysis and Iris with the wasm `rocq c`,
  under node, and checks their output. A file is skipped when its library
  is not installed in the switch.
- `client/test-web/`: the extension in VS Code for the web
  (`@vscode/test-web --headless`), on a root served on port 8001: a smoke
  test, and the compilation of a small project. Their folders set
  continuous mode: in manual mode, the default, only the errors found
  while parsing (e.g. a missing library) are reported until you step.

## Trying it as a user

The extension is not on the Marketplace in this form, and no `.vsix` is
involved: VS Code for the web loads an extension from a folder served over
HTTP(S) (`client/`, whose `package.json` has the `browser` entry). You need:

1. **The extension, built**:

   ```sh
   cd client && npm install && npm run build --workspaces && npm run build:web
   ```

2. **A root**, the URL of a directory containing `manifest.json`, served
   with `Access-Control-Allow-Origin: *`. Either:
   - locally: `vsrocq-make-web-root ~/vsrocq-root`, then
     `python3 web/test/serve.py web/test ~/vsrocq-root`. The root is
     `http://127.0.0.1:8001/`; port 8000 serves the test page, which you
     don't need here;
   - on GitHub Pages: push this branch to a GitHub repository, set
     *Settings → Pages → Source* to *GitHub Actions*, and run the workflow
     *Publish the web opam root* (Actions tab). The root is
     `https://<owner>.github.io/<repo>/rocq-dev/`.

3. **VS Code for the web with the extension**, either:
   - **locally** (this is what the tests do):

     ```sh
     npx @vscode/test-web --coi --browser=chromium \
       --extensionDevelopmentPath=$PWD/client /path/to/a/folder/of/v/files
     ```

     A browser opens on VS Code for the web, with that folder as its
     workspace;
   - **on vscode.dev** (not tested yet; see
     [Test your web extension in vscode.dev](https://code.visualstudio.com/api/extension-guides/web-extensions#test-your-web-extension-in-vscode.dev)):
     serve `client/` over HTTPS with a `Cross-Origin-Resource-Policy:
     cross-origin` header (vscode.dev is cross-origin isolated, and the
     extension starts a worker from that origin). With
     [mkcert](https://github.com/FiloSottile/mkcert):

     ```sh
     mkcert -install && mkcert localhost      # localhost.pem, localhost-key.pem
     cd client
     echo '{"headers":[{"source":"**/*","headers":[{"key":"Cross-Origin-Resource-Policy","value":"cross-origin"}]}]}' > serve.json
     npx serve --cors -l 5000 --ssl-cert ../localhost.pem --ssl-key ../localhost-key.pem
     ```

     Open <https://vscode.dev/?vscode-coi>, run **Developer: Install
     Extension From Location...**, and give it `https://localhost:5000`.
     Open a folder (or a GitHub repository) containing `.v` files. The
     browser may ask for permission to access the local network
     (`localhost`).

4. **Open a folder that sets `vsrocq.web.root`.** The usual setup is a Rocq
   project that commits the root in its `.vscode/settings.json` (as
   `client/test-web/workspace` does):

   ```json
   {
     "vsrocq.web.root": "https://<owner>.github.io/<repo>/rocq-dev/"
   }
   ```

   - In **desktop VS Code**, with the VsRocq extension of this branch
     installed as usual, nothing changes: the desktop extension ignores
     `vsrocq.web.root` and runs the `vsrocqtop` of your opam switch
     (`vsrocq.path`), with the libraries installed there. Unless
     `"vsrocq.useWasm": true`: then it uses the server of the root,
     compiled to WebAssembly, as in the browser, and nothing needs to be
     installed. `client/web/node-server.js` (in the `.vsix`), run by the
     node of VS Code, downloads the server of the root in the storage of
     the extension and runs it in a worker thread
     (`client/web/node-worker.js`), where the files below the prefix of
     the root are the ones of the root, fetched when Rocq reads them (the
     `lazyfs.js` of the root, its synchronous XHR implemented with
     `Atomics.wait` while the main thread fetches), and the other files
     the ones of the computer. It is slower than `vsrocqtop`.
   - In **VS Code for the web**, the same folder (for example the GitHub
     repository opened at `https://vscode.dev/github/<owner>/<repo>?vscode-coi`)
     uses the root: Rocq, its libraries and plugins all come from there. The
     `.v` and `.vo` files of the folder are visible to Rocq, and
     **Rocq: Compile the project (WebAssembly)** builds the `.vo` files (see "The
     workspace" below). If VS Code opens the folder in Restricted Mode,
     trust it: the extension does not declare support for untrusted
     workspaces.

   The project must be compatible with the Rocq of the root: the root
   provides only what was installed in its switch (here Rocq's Corelib, no
   Stdlib or other libraries). A project that needs more publishes its own
   root, from a switch with those packages installed.

   A root can also be set for all folders in the user settings. Then open a
   `.v` file. The "VsRocq" output channel says which root is used.
   `vsrocq.web.debug` logs the fetched files in the browser console. The
   extension starts in manual mode: step with Alt+↓, or set
   `"vsrocq.proof.mode": 1` for continuous checking.

`?vscode-coi` (or `--coi` for `@vscode/test-web`) makes the page
cross-origin isolated, which interruption needs (see below).

## The workspace

In VS Code for the web:

- the project files (`_RocqProject`, `_CoqProject`), `.v` and `.vo` files
  of the workspace are mirrored in the file system of the server, at the
  path of their URI, and kept up to date: a document can `Require` the
  compiled files of its project;
- **Rocq: Compile the project (WebAssembly)** reads `_RocqProject` (or
  `_CoqProject`) at the root of the workspace, runs `rocq dep`, then
  `rocq c` on the files whose `.vo` is missing or out of date, in
  dependency order, each in a fresh worker (`runner.js`). The `.vo` files
  are written in the workspace (with a GitHub repository, as uncommitted
  changes), the output goes to the "Rocq Compile" channel. The open Rocq
  documents are then reset, so that they use the new `.vo` files.
  In desktop VS Code with `vsrocq.useWasm`, the same command runs the
  `rocq dep` and `rocq c` of the root in node processes
  (`client/web/node-server.js --run`), on the files of the computer: the
  `.vo` files are written next to the `.v` files.

## Interruption

Rocq calls `Control.check_for_interrupt` all over reduction and tactic
execution; every 1000 calls the web `ProverThread` polls an `Int32` in a
`SharedArrayBuffer`, and the deadline of `try_run ~timeout`. While Rocq
computes the worker processes no message, so the client sets the flag with
`Atomics.store` when it sends `prover/interrupt` or edits a document; the
worker clears it when it receives a message while idle. Rocq then raises
`Sys.Break`, reported as an interruption.

`SharedArrayBuffer` needs cross-origin isolation: in vscode.dev, add
`?vscode-coi` to the URL. Without it Rocq can't be interrupted.

## Known limitations and issues

- **No `vm_compute`/`native_compute`.** The server runs with
  `-bytecode-compiler no`.
- **No proof delegation**, and `par:` runs sequentially.
- **Loops that never call `check_for_interrupt` can't be interrupted**,
  e.g. `do 100000000 idtac` (`Tacticals.tclDO`).
- **A JS stack overflow kills the worker** (a `RangeError`, not an OCaml
  `Stack_overflow`), e.g. on deep non-tail recursion in Ltac.
- **`.vo` files containing an integer that does not fit in 31 bits can't
  be loaded** (`input_value: integer too large`): in Corelib
  `Numbers.Cyclic.Int63.Sint63Axioms`, in Stdlib `Numbers.Cyclic.Int63.Uint63`
  and `Sint63` (primitive integers such as `min_int`). The one of `Uint63`
  is in an opaque proof, hence `--strip-opaques` makes it loadable. With the patches
  above, no other `.vo` file of Stdlib, mathcomp, mathcomp-analysis, Elpi,
  Hierarchy Builder, stdpp or Iris contains one.
- **Compiling the project** needs `_RocqProject` at the root of the first
  workspace folder; only `-Q`, `-R`, `-I`, `-arg` and the `.v` files are
  used. Project-local OCaml plugins can't be built.
- Plugins installed by `coq_makefile` have no `.cma`, only `.cmxs`.
