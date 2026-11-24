# Design note: Rocq without an installation, from published web roots

Status: proposal. Builds on the web port described in
[README.wasm.md](../README.wasm.md).

## Summary

A *web root* is a Rocq toolchain compiled to WebAssembly, published as
static files: the language server, `rocq c`, `rocq dep`, the `.vo` files
and the plugins of the packages of an opam switch. `vsrocq-make-web-root`
makes one from a switch.

The proposal is to publish web roots, for every Rocq release and for every
Rocq Platform package pick, at a standard location with an index. VsRocq
then offers one whenever no local Rocq is available:

- on desktop, when no `vsrocqtop` is found;
- on the web (vscode.dev), always, since there is never a local Rocq.

A web root is **not** a toolchain pin. Installing, choosing and pinning a
Rocq toolchain remains the job of opam (and of the Rocq Platform, which is
built on opam). A web root only says *where a WebAssembly build of an
opam-defined toolchain can be found*, so that Rocq works where it is not
installed.

## Problem

Today:

- **Desktop:** without a `vsrocqtop` in the `PATH` (or in `vsrocq.path`),
  VsRocq cannot do anything. Newcomers first have to install opam and
  Rocq, or the Rocq Platform, before they see a single goal.
- **Web:** the user must find a web root and set `vsrocq.web.root` to its
  URL. Only one root exists (`rocq-dev`, built by
  `.github/workflows/web-root.yml`), and it only provides Rocq's Corelib.

## Terminology

The term *web root* (`manifest.json` calls the whole directory a root) is
used here on purpose. These artifacts are a little like a devcontainer
image: a ready-made environment, published once and used by many. However,
the name "WebContainer" is already taken by StackBlitz, for a Node.js
runtime that runs in the browser, which is a different thing.

## Publishing

### What is published

One web root per toolchain that users actually install:

- **each Rocq release**: an opam switch with `rocq-core` at that version
  and nothing else (Corelib only), e.g. `rocq-9.1.0`;
- **each Rocq Platform package pick**: an opam switch with the packages of
  that pick (Rocq, Stdlib, and the libraries and plugins of the Platform),
  e.g. `platform-2025.08.0`. These are what most users want: `From Stdlib
  Require Import ZArith.` just works.

Each root is built by CI from an opam switch, with `vsrocq-make-web-root`,
and is **immutable**: a fix produces a new root, with a new `id` (see
[Root format](#root-format)).

### Standard location and index

The roots live under one standard base URL, owned by the Rocq project
(e.g. the GitHub Pages of the `rocq-prover` organization, or
`rocq-prover.org`; to be decided), with an index:

```
<base>/index.json
<base>/rocq-9.1.0/manifest.json, ...
<base>/platform-2025.08.0/manifest.json, ...
```

`index.json` lists the roots and what is needed to choose between them,
without downloading their manifests (the versions and sizes in this note
are illustrative):

```json
{
  "format": 1,
  "roots": [
    { "name": "platform-2025.08.0", "url": "platform-2025.08.0/",
      "id": "…", "rocq": "9.0.0", "platform": "2025.08.0",
      "packages": { "rocq-core": "9.0.0", "rocq-stdlib": "9.0.0", "…": "…" },
      "size": 312000000, "recommended": true },
    { "name": "rocq-9.1.0", "url": "rocq-9.1.0/",
      "id": "…", "rocq": "9.1.0", "packages": { "…": "…" },
      "size": 44000000 }
  ]
}
```

The base URL is a VsRocq setting (`vsrocq.webRoots.index`), with the
standard location as its default. Organizations and courses can publish
their own index, e.g. a root with the libraries of a course.

## Choosing a root

The root must suit the project. VsRocq chooses, in order:

1. **The user's explicit choice** for this workspace (remembered in the
   workspace state, see below), or `vsrocq.web.root` if set (a custom root
   URL, as today).
2. **The project's own opam constraints**, when the project has opam
   files: the dependencies of its `*.opam` files (e.g. `rocq-core {>=
   "9.0"}`, `rocq-mathcomp-ssreflect`) select the roots that provide those
   packages at suitable versions. This reuses what the project already
   declares for opam. Nothing new is declared for web roots.
3. **The recommended root** of the index (the latest Rocq Platform pick).

When no root satisfies the constraints, VsRocq says so (e.g. "this project
needs `rocq-equations`, which no published web root provides") and offers
the closest ones.

## User experience

### Desktop

When VsRocq starts and finds no `vsrocqtop` (neither `vsrocq.path` nor the
`PATH`), it shows a notification instead of the current error:

> Rocq is not installed. You can use a WebAssembly build of Rocq
> Platform 2025.08.0 (Rocq 9.0.0, 312 MB download, slower than a native
> installation, no `vm_compute`, no proof delegation).
> [Use it] [Choose another…] [How to install Rocq]

- *Use it* downloads the root into the cache (`<globalStorage>/roots/<id>/`)
  with a progress notification, checks the files against the manifest's
  hashes, and starts the server. A cached root starts with no network
  access.
- *Choose another…* opens a quick pick listing the roots of the index,
  with their Rocq version, Platform pick, size, and whether they satisfy
  the project's opam constraints.
- *How to install Rocq* opens the installation instructions (the Rocq
  Platform). Installing Rocq is still the recommended path for regular
  use.

The choice is remembered per workspace. As soon as a `vsrocqtop` appears
(e.g. the user installed Rocq afterwards), it takes precedence again, and
VsRocq says so once.

A status bar item shows the running toolchain, e.g. `Rocq 9.0.0
(web root platform-2025.08.0)` or `Rocq 9.0.0 (local)`. Clicking it runs
**Rocq: Select the toolchain**, which offers the local `vsrocqtop` (if
any), the roots of the index, a custom URL, and the cache commands
(*clear*, *re-download*). The "VsRocq" output channel logs the root, its
`id`, why it was chosen, and the cache directory.

`vsrocq.path` and `vsrocq.args` apply only to the local toolchain. With a
web root, the command line is `manifest.args`.

### Web

There is no local toolchain, so the same choice is made on every start,
without the "not installed" wording: the root is chosen as above, and the
status bar item shows it. Choosing one needs no download step, as files are
fetched when opened. `vsrocq.web.root` remains the way to force a custom
root.

### When a local Rocq is installed

Nothing changes: desktop runs `vsrocqtop`. Web roots are only offered
explicitly, through **Rocq: Select the toolchain**.

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

### Option (a): a relocated copy on disk

Download the whole root into the cache, and make the paths point there:

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

Pros: no change to js_of_ocaml (under node, the runtime uses `node:fs`);
files are read at disk speed; the server sees the real file system, so the
workspace mirror of the web build is not needed, and **Rocq: Compile the
project** can write `.vo` files in place.

Cons: the whole root is downloaded before the first start. That is fine
for a Corelib root (44 MB), but a Rocq Platform root is much larger (to be
measured), while a session typically reads a small fraction of it.

### Option (b): lazy loading in node

Reuse `lazyfs.js` in the node worker, backed by the disk cache, so that
files are downloaded when first opened, as in the browser, and kept.

This needs the runtime to use a provided file system under node. The wasm
runtime chooses its file system once, at startup
(`runtime/wasm/runtime.js`). In js_of_ocaml 6.5.0, and in the first
version of the `jsoo-fs` patch, a provided `globalThis.jsoo_fs` was only
used outside of node:

```js
const fs = isNode ? require("node:fs") : globalThis.jsoo_fs;
```

A node worker thread is node (`process.versions.node` is set), so a
`jsoo_fs` installed by `worker.js` would be ignored, and every `open` would
go to the real disk, where the prefix does not exist. The `jsoo-fs` patch
([ocsigen/js_of_ocaml#2643](https://github.com/ocsigen/js_of_ocaml/pull/2643),
branch `web-6.5`) now prefers a provided file system everywhere:

```js
const fs = globalThis.jsoo_fs ?? (isNode ? require("node:fs") : undefined);
```

Two node-specific choices of the runtime remain, and option (b) must live
with them:

- `on_windows` is `isNode && process.platform === "win32"`, and switches
  the runtime to Windows path handling. A `jsoo_fs` that mounts POSIX
  paths (the prefix of a Linux-built root) would then be addressed with
  Windows conventions;
- `getcwd` returns `process.cwd()` under node, a real directory that the
  mounted file system must also serve (e.g. by passing through to
  `node:fs` outside the prefix).

(b) also needs a synchronous fetch in node, because OCaml's `open_in`
returns synchronously. Browsers have synchronous `XMLHttpRequest` in
workers, which `lazyfs.js` uses, but node does not. It would block on
`Atomics.wait` while a second worker downloads the file.

### Recommendation

Start with (a), for Corelib roots, since it is simple. Move to (b) before
publishing Rocq Platform roots, whose size makes a full download a poor
first experience. (b) also unifies desktop and web: one `lazyfs.js`,
backed by a disk cache on desktop and by the browser's HTTP cache on the
web.

## Root format

Changes to `manifest.json` (written by `make-web-root.py`):

- `version`, today the format version (`1`), becomes `format`. A new
  `id` is a content hash of the manifest's file list, and keys the cache;
- a `sha256` for each file, next to its size, which the desktop download
  checks;
- `relocate`: the files that contain the prefix (option (a));
- `rocq` (the Rocq version) and `platform` (the Rocq Platform pick, if
  any), shown in the prompt and the status bar. `packages` (already
  there) is copied to the index for choosing a root.

## Security

- **Web:** the server runs in a Web Worker of the vscode.dev origin. It can
  only fetch with CORS, and only sees the files it is given (the root and
  the workspace mirror). A malicious root can at worst give wrong answers.
- **Desktop:** the server runs in node, with `node:fs`, so it can read and
  write any file the user can, just like a `vsrocqtop`. Roots from the
  standard index are trusted like the Rocq releases they are built from:
  they come from the same publisher, and are checked against the hashes of
  their manifest. A custom root (`vsrocq.web.root`, a custom index) is
  trusted like a custom `vsrocq.path`: in a workspace setting, it is only
  used in a trusted workspace (Workspace Trust), after an explicit consent
  naming the URL. Restricting the worker (e.g. node's permission model,
  `--permission` with `--allow-fs-read`/`--allow-fs-write` limited to the
  cache and the workspace) is worth investigating, but it requires a
  separate node process instead of a worker thread.

## Open questions

- **Size of Rocq Platform roots**, and whether to split them (a root per
  pick, or layered roots: a base Rocq root plus one per library). For
  reference, a root with Stdlib, mathcomp-analysis (and the mathcomp it
  needs, Elpi and Hierarchy Builder) and Iris is 1312 files, 398 MB
  (198 MB gzipped): mathcomp 132 MB, mathcomp-analysis 79 MB, Elpi and HB
  68 MB (of which 8 MB of examples), Stdlib 46 MB, Rocq plugins 23 MB, the
  programs 21 MB, Iris 16 MB, stdpp 10 MB. A Corelib root is 44 MB. In
  the browser, only 6 MB are fetched at startup either way.
- **Windows.** A root built on Linux, run by node on Windows: paths in
  `findlib.conf` (option (a)), or the `on_windows` path handling of the
  runtime (option (b)). This needs testing.
- **Matching opam constraints** without opam: a small solver over the
  `packages` of the index is enough for `=`/`>=`/`<` constraints, but
  should VsRocq call `opam` when it is installed (e.g. Rocq not installed,
  but opam is)?
- **Multi-root workspaces.** One server serves all the folders: the first
  folder's constraints win, and a warning is shown if the others disagree.
- **Mixing toolchains.** `.vo` files compiled by a local Rocq do not load
  in a root of another version (and vice versa). VsRocq should report
  this clearly, and offer **Rocq: Compile the project** with the root.

## Work items

1. `make-web-root.py`: `id`, `sha256`, `relocate`, `rocq`, `platform` in
   the manifest.
2. CI: build and publish a root per Rocq release and per Rocq Platform
   pick, immutable, plus `index.json`, at the standard location.
3. Client: the toolchain selector shared by the desktop and web entries
   (index, opam constraints, user choice, status bar item, command).
4. Desktop: the "Rocq is not installed" offer; download and cache with
   progress and hashes; start `worker.js` in a worker thread; option (a),
   then (b).
5. Desktop: **Rocq: Compile the project** with `rocq-web` from the root
   (`runner.js` in a worker thread, on the real file system).
6. Tests: the `client/test-web` tests with an index instead of
   `vsrocq.web.root`, plus a desktop test (`@vscode/test-electron`) with a
   local index and no `vsrocqtop` in the `PATH`.
