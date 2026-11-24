# Design note: a project's Rocq toolchain from a published root

Status: proposal. Builds on the web port described in
[README.wasm.md](../README.wasm.md).

## Problem

A published root (made by `vsrocq-make-web-root`) contains a complete
Rocq toolchain compiled to WebAssembly: the language server, `rocq c`,
`rocq dep`, the `.vo` files, and the plugins. Today a project names it with
the VS Code setting `vsrocq.web.root`, and only VS Code for the web uses
it. Desktop VS Code ignores the setting and runs the `vsrocqtop` of the
user's opam switch.

So the same folder behaves differently on desktop and on the web, and
nothing tells the user which toolchain is running. Yet a published root is
exactly what a project would want to pin: a known Rocq, with known
libraries, that needs no installation.

## Prior art

Two established ideas combine here.

- **Pinned toolchain files.** A file at the root of a project names the
  exact toolchain, and a toolchain manager downloads it on first use:
  - Lean: `lean-toolchain` (e.g. `leanprover/lean4:v4.9.0`), read by
    `elan` and by the VS Code Lean extension. This is the closest
    precedent, and it comes from a proof assistant;
  - Rust: `rust-toolchain.toml`, read by `rustup`. The precedence is an
    explicit override (`RUSTUP_TOOLCHAIN`, `rustup override`), then the
    file, then the user's default;
  - Go: the `toolchain` line of `go.mod` (Go ≥ 1.21);
  - also the Gradle and Maven wrappers, `.nvmrc`, and `.tool-versions`
    (asdf, mise).

  In all of these, the pin belongs to the project, not to an editor:
  the command line, CI, and every editor see the same toolchain.
- **Development containers** ([containers.dev](https://containers.dev),
  `.devcontainer/devcontainer.json`). A project declares its environment,
  and the editor offers to enter it, after Workspace Trust and with a
  visible indicator. This is the model for the UX. The environment itself
  is much heavier: an OS image, run by Docker or in a cloud VM.

This is not a WebContainer (StackBlitz). WebContainers run a Node.js
environment inside a browser tab, which is an execution engine. Here, the
engine is whatever runs WebAssembly: node on desktop, the browser on the
web.

What is new here is that the pinned toolchain is WebAssembly: one artifact
runs on every host, with no per-platform builds. Opam's local switches
(`_opam`) are the closest Rocq-world mechanism, but they build the
toolchain from source on each machine.

## Proposal

### The `rocq-toolchain` file

A project pins its toolchain in a file named `rocq-toolchain` at its root.
It contains the URL of a root (the directory containing `manifest.json`):

```
https://rocq-prover.github.io/roots/rocq-9.1.0-2026-11-24/
```

Blank lines and lines starting with `#` are ignored. The URL is the only
required content. A later version may add an expected manifest `id` (see
[Root format](#root-format)), or short names resolved through an index of
roots (like Lean's `leanprover/lean4:v4.9.0`).

The file is editor-independent. VsRocq reads it, and so could a
command-line tool or CI (see [Other clients](#other-clients)).

### Precedence

Following `rustup`:

1. `vsrocq.toolchain.root` in the **workspace** settings: an explicit
   override for this workspace. `none` forces the local `vsrocqtop` on
   desktop.
2. The `rocq-toolchain` file of the workspace folder.
3. `vsrocq.toolchain.root` in the **user** settings: the default root,
   for folders without a file. It is required on the web, where there is no
   local toolchain. On desktop it is optional, and when it is unset the
   default is the local `vsrocqtop`.

`vsrocq.web.root` remains a deprecated alias of `vsrocq.toolchain.root`
for one release.

## Goals

- One pin, with the same meaning everywhere: "the Rocq toolchain of this
  project".
- Desktop VS Code can run a project's root without opam, and says that it
  does so.
- The user stays in control on desktop: explicit consent, a visible
  indicator, and an easy way back to their local `vsrocqtop`.
- Reproducible: a project can pin an immutable root, which keeps working
  offline once cached.

Non-goals: native-code roots (per-platform binaries), building roots from
the project's dependencies.

## User experience

### Desktop

When a workspace pins a root:

1. **Workspace Trust.** In Restricted Mode, the root is not used, and the
   status bar says so. On desktop the server is not sandboxed (see
   [Security](#security)), so the root is used only in trusted workspaces.
2. **Consent, once per workspace and root**, with a notification:

   > This project uses the Rocq toolchain at `<url>` (Rocq 9.1.0, 44 MB,
   > runs in WebAssembly: slower, no `vm_compute`, no proof delegation).
   > [Use it] [Use my vsrocqtop] [Always use project toolchains]

   The answer is kept in the workspace state, keyed by the root's `id`, so
   that a different root asks again. *Always* is a user setting
   (`vsrocq.toolchain.useProjectRoot`: `ask` (the default), `always`,
   `never`). A root chosen by the user (precedence 1 or 3) needs no
   consent.
3. **Preparation**, like "Starting Dev Container": a progress
   notification downloads the root into the cache, checking the sizes and
   hashes of the manifest. Then the server starts. A root that is already
   cached starts with no network access.
4. **Indicator.** A status bar item shows the running toolchain and where
   it comes from, e.g. `Rocq 9.1.0 (rocq-toolchain)` or `Rocq 9.1.0
   (local)`. Clicking it runs **Rocq: Select the toolchain**, which offers
   the same choices as the notification, and the cache commands (*clear*,
   *re-download*). The "VsRocq" output channel logs the root, its `id`,
   the precedence rule that selected it, and the cache directory.

`vsrocq.path` and `vsrocq.args` apply only to the local toolchain. With a
root, the command line is `manifest.args`.

Changes to `rocq-toolchain` are watched: the user is asked to restart the
server with the new root (and to consent again, if the `id` changed).

### Web

There is no other toolchain, and the server runs in the browser sandbox,
so a pinned root is used without a consent prompt. It gets the same status
bar item. In Restricted Mode, neither the workspace setting nor the file
is used, as on desktop.

### Without a pin

Nothing changes: desktop runs `vsrocqtop`, and the web extension asks for
`vsrocq.toolchain.root`.

## Running a root on desktop

The pieces already exist. `worker.js` runs the server in a node
`worker_threads` worker, and `node-bridge.js` uses it to speak LSP on
stdio. The desktop extension would start the same worker from its node
extension host, and connect `vscode-languageclient` to it with a
`MessageReader`/`MessageWriter` pair. `ProverThread` (`dm/web`) and the
interruption flag (`SharedArrayBuffer`, which node always provides) work
as they do in the browser.

The problem is the file system. The programs in a root contain absolute
paths of the switch that built it (`manifest.prefix`, e.g.
`/home/runner/.opam/default`): the path to `findlib.conf` and the paths
inside it, and the `-coqlib` in `manifest.args`. In the browser,
`lazyfs.js` mounts the root at that prefix. On desktop there are two
options.

### Option (a), recommended: a relocated copy on disk

Download the whole root into `<globalStorage>/roots/<id>/`, and make the
paths point there:

- **`findlib.conf`**: rewrite `destdir` and `path` (replace the prefix by
  the cache directory) when downloading. Rocq calls `Findlib.init`, which
  reads the file named by `OCAMLFIND_CONF`, so the worker gets
  `OCAMLFIND_CONF=<cache>/lib/findlib.conf` in its environment. The `META`
  files only use relative directories, so they need no change.
- **`-coqlib`**: rewrite the prefix in `manifest.args`. The same goes for
  the command line of `rocq c` and `rocq dep`.
- **Nothing else** contains the prefix: `.vo` files record logical paths,
  and plugins are found through findlib. In today's root, only
  `manifest.json`, `lib/findlib.conf` and `lib/rocq-runtime/revision`
  (build information; to be checked) contain the prefix. The wasm
  programs do not.

`make-web-root.py` already knows which files carry the prefix. It should
list them in the manifest (e.g. `"relocate": ["lib/findlib.conf"]`, and
`args`), so that the client does not hard-code them.

Pros:

- **No change to js_of_ocaml.** Under node, the runtime uses `node:fs`
  directly.
- Files are read at disk speed, and the server works offline once the
  root is cached.
- The server sees the real file system, so the workspace mirror of the
  web build is not needed. `Require` sees the project's `.vo` files where
  they are, and **Rocq: Compile the project** can write them in place.
- The cache layout is what a command-line tool needs too (see
  [Other clients](#other-clients)).

Cons:

- The whole root is downloaded before the first start (44 MB today), even
  though a session typically reads a fraction of it. That is acceptable
  for a once-per-root, devcontainer-like preparation step, and it is what
  `elan` and `rustup` do.

### Option (b): lazy loading in node

Reuse `lazyfs.js` in the node worker, backed by the disk cache, so that
files are downloaded when opened, as in the browser.

**Why (b) needs another js_of_ocaml patch.** The wasm runtime chooses its
file system once, at startup (`runtime/wasm/runtime.js`, branch `web-6.5`):

```js
const fs = isNode ? require("node:fs") : globalThis.jsoo_fs;
```

The `jsoo-fs` patch ([ocsigen/js_of_ocaml#2643](https://github.com/ocsigen/js_of_ocaml/pull/2643))
only lets a host provide `globalThis.jsoo_fs` *outside of node*. A node
worker thread is node (`process.versions.node` is set), so a `jsoo_fs`
installed by `worker.js` would be ignored, and every `open` would go to
the real disk, where the prefix does not exist. To make (b) work, the
runtime must prefer a provided file system everywhere:

```js
const fs = globalThis.jsoo_fs ?? (isNode ? require("node:fs") : undefined);
```

That is a small change, which could be folded into #2643 ("a host can
provide the file system"), but it widens what that PR promises. The
other node-specific choices in that runtime would also need a decision:

- `on_windows` is `isNode && process.platform === "win32"`, and switches
  the runtime to Windows path handling. A `jsoo_fs` that mounts POSIX
  paths (the prefix of a Linux-built root) would then be addressed with
  Windows conventions;
- `getcwd` returns `process.cwd()` under node, a real directory that the
  mounted file system knows nothing about.

(b) also needs a synchronous fetch in node, because OCaml's `open_in`
returns synchronously. Browsers have synchronous `XMLHttpRequest` in
workers, which `lazyfs.js` uses, but node does not. It would have to block
on `Atomics.wait` while a second worker downloads the file.

So (b) costs a runtime patch that upstream has to accept, Windows path
questions, and a blocking-fetch helper. In exchange it saves a one-time
download. It may become worth it if roots grow large, for example with
many libraries. Until then, (a) is simpler.

## Root format

Changes to `manifest.json` (written by `make-web-root.py`):

- `version`, today the format version (`1`), becomes `format`. A new
  `id` is a content hash of the manifest's file list, and keys the cache
  and the consent;
- a `sha256` for each file, next to its size, which the desktop download
  checks;
- `relocate`: the files that contain the prefix (option (a));
- `rocq`: the Rocq version, shown in the consent prompt and in the status
  bar (today it only appears among `packages`).

## Publishing immutable roots

`.github/workflows/web-root.yml` publishes `rocq-dev/`, a moving target.
For reproducibility it should publish versioned directories,
e.g. `rocq-9.1.0-<date>/`, and keep `rocq-dev/` as an alias (a copy, or a
manifest that points to the latest one). A project pins a versioned URL in
its `rocq-toolchain`, like a Lean project pins a release. A root that
changes under the same URL gets a new `id`, so the cache and the consent
notice the change.

## Other clients

Because the pin is a file, and option (a) leaves a relocated root on
disk, a small command-line tool (in the spirit of `elan`) can give the
same toolchain outside VS Code:

```sh
rocq-root run -- rocq c theories/A.v     # reads ./rocq-toolchain, downloads, runs under node
rocq-root run -- vsrocqtop               # for other LSP clients
```

It would share the cache with the extension, and it lets CI check a
project with exactly the toolchain its users see in the editor. It is not
needed for the first version.

## Security

- **Web:** the server runs in a Web Worker of the vscode.dev origin. It can
  only fetch with CORS, and only sees the files it is given (the root and
  the workspace mirror). A malicious root can at worst give wrong answers.
- **Desktop:** the server runs in node, with `node:fs`. Under option (a) it
  can read and write any file the user can, just like a `vsrocqtop` from
  an unknown source. A `rocq-toolchain` file is as powerful as a
  devcontainer definition or a `rust-toolchain.toml`: opening the folder
  must not be enough to run it. This is why the root is used only in
  trusted workspaces, after explicit consent naming the URL, and why
  downloads are checked against the manifest's hashes. Restricting the
  worker (e.g. with node's permission model, `--permission` with
  `--allow-fs-read` and `--allow-fs-write` limited to the cache and the
  workspace) is worth investigating, but it would require starting a
  separate node process instead of a worker thread.

## Open questions

- **Windows.** A root built on Linux, run by node on Windows under option
  (a): `findlib.conf` would contain Windows paths, and `Sys.os_type` and
  `Filename` follow `on_windows`. This needs testing, and maybe a
  `--prefix` style relocation that avoids drive letters.
- **Multi-root workspaces.** One server serves all the folders, so their
  `rocq-toolchain` files must agree. Otherwise the first folder's pin wins,
  and a warning is shown.
- **Pinning by content.** Should `rocq-toolchain` be able to carry the
  expected `id`, so that a root changed under a versioned URL is refused
  rather than re-consented?
- **Names.** Is an index of roots (short names such as
  `rocq-9.1.0+stdlib`) worth having, or are URLs enough?

## Work items

1. `make-web-root.py`: `id`, `sha256`, `relocate`, `rocq` in the manifest;
   versioned output in the workflow.
2. Client: read `rocq-toolchain` and apply the precedence; rename the
   setting (with the alias); a toolchain selector shared by the desktop and
   web entries; the status bar item and command; watch the file.
3. Desktop: download and cache with progress and hashes; relocation; start
   `worker.js` in a worker thread, with `OCAMLFIND_CONF` and the rewritten
   args; consent and trust.
4. Desktop: **Rocq: Compile the project** with `rocq-web` from the root
   (`runner.js` in a worker thread, on the real file system).
5. Tests: the `client/test-web` tests with a `rocq-toolchain` file instead
   of the setting, plus a desktop test (`@vscode/test-electron`) with a
   local root.
6. Later: the `rocq-root` command-line tool.
