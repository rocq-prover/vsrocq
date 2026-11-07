# Development

This page is intended for software developers who wish to help with the VsRocq2 development effort.

The two main building blocks are the language server and the client (the vscode extension, namely).

## Language server

The language server is developed in ocaml and makes it possible to link from the client directly to the Rocq API and exploit [LSP](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/).

### Architecture

The *document* data structure holds:
- the text
- the parsed document (AST of each sentence, mapping between text positions and sentences)
- the checked document (each sentence comes with a checking result)
- the feedback (each message by the prover is attached to the corresponding sentence)

The architecture is organized in the following components.
* **VsCoqtop:** This component handles the main event loop.
* **LSPManager:** This component handles the JSONRPC encoding, LSP requests, notifications and responses as well as LSP events dispatch.
* **DocumentManager:** The document manager handles everything that pertains to document representation and parsing, handles feedbacks.
* **Document:** Raw and parsed document representations.
* **Scheduler:** Incremental static dependency analysis.
* **QueryManager:** This handles the Rocq queries (Search, About, etc... hover, completion)
* **Checking manager:** document checking, exec overview
* **Execution manager:** Handles execution of the Rocq interpreter
* **Delegation manager:** Handles worker tasks

```mermaid
flowchart TD
    A[vsrocqtop]
    B[LSPManager]

    C["DocumentManager
       (document)"]
    D["ExecutionManager
       (schedule2task, exec promise)"]
    D1[(Rocq Interpreter)]
    E["DelegationManager
       (spawn, kill)"]
    F[QueryManager]
    F1[(Rocq API)]
    G["Document
       (parser state, outline)"]
    G1[(Rocq Parser)]
    H[Scheduler]
    I["CheckingManager
       (observe_id, checking overview)"]
    J[\"proverThread
        (sequentialize, interrupt)"/]
    K[\proverWorker/]
    A --> B
    B --> C
    I --> D
    D --> E
    C --> F
    C --> G
    C --> H
    C --> I
    D --- J
    J ---|stateful| D1
    F --- J
    J ---|stateful| F1
    G --- J
    J ---|stateful| G1
    E --- K
    K ---|stateful| D1
    H ---|pure| F1
    style D1 fill: #f3ef1d
    style F1 fill: #f3ef1d
    style G1 fill: #f3ef1d
    style J fill: #75e15c
    style K fill: #75e15c

```

### Building

#### With opam

You need [opam](https://opam.ocaml.org/doc/Install.html). The commands below
assume the switch's environment is active in your shell (see `opam env`). On
Windows, also set `ROCQLIB` to the output of `rocq -where`, otherwise a server
run from `_build` cannot find Rocq's library.

1. Create a switch for VsRocq development:

   ```shell
   # Any name and OCaml version work, as long as OCaml is 4.14 or newer.
   opam switch create vsrocq-dev 4.14.4
   ```

2. From the root of the repository, install the dependencies of the language
   server, Rocq included:

   ```shell
   # Naming rocq-core makes opam pick Rocq 9 rather than Coq 8.x.
   # --with-test adds what the test suite needs.
   opam install ./language-server --deps-only --with-test rocq-core
   opam install rocq-core
   ```

3. Generate the `dune` files, which depend on the installed Rocq version:

   ```shell
   make -C language-server dune-files
   ```

4. Build the server:

   ```shell
   cd language-server
   dune build
   # Prints the Rocq and OCaml versions the server was built with.
   _build/install/default/bin/vsrocqtop -v
   ```

5. Run the tests, still from `language-server`:

   ```shell
   make test
   ```

#### With nix

If you have nix installed, you can do a full developer build of the language server by running:

```
nix develop .#vsrocq-language-server -c bash -c "cd language-server && dune build"
```

### Composing the build with Rocq

To build a VsRocq with a local version of Rocq, from the modified Rocq directory:

1. Build Rocq, e.g. with `make world` to build Rocq and set up dune
2. Clone the VsRocq repository in `rocq/vsrocq/` (next to, say, `kernel/`).
3. Then `dune build vsrocq/language-server` will build the server, typically in
`_build/install/default/bin/vsrocqtop` (next to the rocq binaries).
4. Set the (absolute) path to the local build `"vsrocq.path": "path/rocq/_build/install/default/bin/vsrocqtop"` in user settings.
5. Reload VsCode.
6. Whenever you change the Rocq sources `dune build` will now also rebuild vsrocqtop.
  If you specify a more specific dune target, remember that vsrocqtop is *linked* to Rocq,
  so if you don't rebuild it it will not work.

### Debugging

## Client

The client is the VSCode extension in itself. Apart from the usual [VSCode](https://code.visualstudio.com/api) lingo, we develop two web apps that are used within separate panels in the extension and are specific to Rocq, namely the goal-view-ui and the search-view-ui.

### Design pattern for the web apps

Both of the two Rocq exclusive panels are react apps. We use the [atomic design pattern](https://atomicdesign.bradfrost.com/table-of-contents/) and the [VSCode webview UI toolkit](https://github.com/microsoft/vscode-webview-ui-toolkit).

### Building

* Make sure you have up to date `npm` and `node.js`. For example, at the time of writing this guide, `node.js` version 19.0.1
* From the client folder run `npm install` which will ensure all dependencies are installed for the extension and the web apps.
* Still from the client folder, run `npm run build --workspaces` to build the extension and all the sub-web apps.
* To package the extension run `npm run package`
* To make an installable `.vsx` package, `npx vsce package`.
  This package can be installed locally in any code workspace or all (not recommended, as it can overwrite an existing
  globally installed vsx `code --install-extension vsrocq-*.vsix`)
* For publishing to VSCode market place use the [vsce tool](https://code.visualstudio.com/api/working-with-extensions/publishing-extension)

### Debugging

You can debug the web apps independently. From the client folder just run `npm run start -w goal-view-ui` or `npm run start -w search-ui`. This will launch the corresponding web app in local development server. You can then access it through your usual browser or the VSCode browser.

Note that both the apps can also be built independently through the `npm run build -w goal-view-ui` or `npm run build -w search-ui` commands.

To launch the extension in debug mode, assuming you have built the language server:

1. From a shell where the switch's environment is active, open the `client`
   folder with `code .`. Close other VS Code windows first, otherwise `code`
   reuses their environment. With nix, run `nix develop .#vsrocq-client -c code .`
   instead.
2. Press F5 (**Run Extension**). A second VS Code window opens with your build of
   the extension.
3. In that window, set `vsrocq.path` to the absolute path of the server you
   built, `<repository>/language-server/_build/install/default/bin/vsrocqtop`.

## E2E tests

From the client folder run `npm test`. To pass arguments to the language
server you can use the `VSROCQARGS` env variable, e.g.

```shell
VSROCQARGS='-vsrocq-d all' npm test
```
Remember that if the language server fails to initialize, the log is not
displayed in the output panel as usual, but rather written to a file named
like `/tmp/vsrocq_init_log.xxx`.

By default the tests run `language-server/_build/install/default/bin/vsrocqtop`.
To run them on another server, set `VSROCQPATH` to its binary.

# Release process

To release a new version of VsRocq, create a new commit (and PR) with the following changes:

1. First make sure to bump the version number in the four following files:
    - `flake.nix`: look for the first `version` key
    - `client/package.json`: look for the `version` key
    - `client/package-lock.json`: look for the top level `version` key and the `version` key in package `vsrocq`
    - `language-server/vsrocqtop/lspManager.ml`: look for the `server_info` let-definition

2. Add a new row in the version requirements constant `versionRequirements`, in `client/src/utilities/versioning.ts`.

3. Open the PR, wait for approval, and merge it with a merge commit (not squash or rebase).

4. Create a signed tag on the merge commit of the release PR. Version semantics are `v2.#.#` (ex: `v2.2.2`).
   The tag name must start with `v` (because the release workflow only runs for tags matching `v*.*.*`).
```shell
    git tag -s v2.X.Y -m "release 2.X.Y"
    # To tag a specific commit instead:
    # git tag -s v2.X.Y -m "release 2.X.Y" <commit-hash>
```

5. Push the tag. This will automatically launch a workflow to generate the release.
```shell
    git push origin v2.X.Y
```

6. Once the CI has run, a **draft** release will be automatically created. Open it and edit the change log to your liking.
Finally, light a candle, do a little prayer and click release !

7. Publishing the release on Github fires the `cd.yml` job that, in turn, opens a PR on the [opam repository](https://github.com/ocaml/opam-repository).
   Wait for the opam maintainers to merge it.

8. Once the opam package is published, run the `publish-extension.yml` workflow manually from the Actions tab (in Github) to publish the extension on the VsCode marketplace and on Open VSX (used by VsCodium).
   In "Use workflow from", select the release tag, not `main`, and uncheck "Make this a pre-release ?", which is checked by default.

# CI update

The version of nixpkgs used in the CI is pinned by flake, to update it to current nixpkgs-unstable, do
```shell
nix flake update
```

# CI/CD pipeline for release process

The CI pipeline (```ci.yml```) handles creating the draft release (with a tarball archive) when a tag is pushed. This is done in the ```create-release``` job.

The CD pipeline (```cd.yml```) automatically publishes the release to opam once the draft is released. Don't forget to fill out the change log
appropriately before hitting release. If it is a pre-release, the pipeline will publish to ```rocq-prover/opam``` instead of ```opam/opam-repository```.

There are two manual pipelines:
- ```publish-server.yml``` allows to publish a release on opam manually (if the automatic pipeline goes wrong). The user only need to give the tag (with the correct version semantics) and specify if it is a release or pre-release.
- ```publish-extension.yml``` handles publishing the extension on the vscode market place as well as vscodium. **This is always done manually because the opam release process might take some time. The extensions should only be published once the package is on opam.**
