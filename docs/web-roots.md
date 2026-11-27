# Design note: Rocq without an installation, from published web roots

Status: proposal. Builds on the web port described in
[README.wasm.md](../README.wasm.md).

## Summary

A *web root* is a Rocq toolchain compiled to WebAssembly, published as
static files: the language server, `rocq c`, `rocq dep`, the `.vo` files
and the plugins of the packages of an opam switch. `vsrocq-make-web-root`
makes one from a switch.

The proposal is to publish a web root for every Rocq Platform release, at a
standard location with an index. VsRocq
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

One web root per **Rocq Platform release**: an opam switch with the
packages of that release (Rocq, Stdlib, and the libraries and plugins of
the Platform), e.g. `platform-2025.08.0`. If a release offers several
package picks (e.g. for two Rocq versions), each pick gets its own root.
This is what users actually install, and what newcomers want: `From
Stdlib Require Import ZArith.` just works.

No roots are published for bare Rocq releases (Corelib only). A Corelib
root is still useful for testing, and CI builds one (`rocq-dev`), but it
is not in the standard index. A project that needs a newer Rocq than the
latest Platform release needs a local installation, or a custom index.

Each root is built by CI from an opam switch, with `vsrocq-make-web-root`,
and is **immutable**: a fix produces a new root, with a new `id` (see
[Root format](#root-format)).

### Standard location and index

The roots live under one standard base URL, owned by the Rocq project
(e.g. the GitHub Pages of the `rocq-prover` organization, or
`rocq-prover.org`; to be decided), with an index:

```
<base>/index.json
<base>/platform-2025.08.0/manifest.json, ...
<base>/platform-2025.01.0/manifest.json, ...
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
    { "name": "platform-2025.01.0", "url": "platform-2025.01.0/",
      "id": "…", "rocq": "9.0.0", "platform": "2025.01.0",
      "packages": { "…": "…" }, "size": 290000000 }
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
3. **The recommended root** of the index (the latest Rocq Platform
   release).

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
  with their Rocq version, Platform release, size, and whether they satisfy
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

`vsrocq-make-web-root` already knows which files carry the prefix. It should
list them in the manifest (e.g. `"relocate": ["lib/findlib.conf"]`, and
`args`), so that the client does not hard-code them.

Pros: no change to js_of_ocaml (under node, the runtime uses `node:fs`);
files are read at disk speed; the server sees the real file system, so the
workspace mirror of the web build is not needed, and **Rocq: Compile the
project** can write `.vo` files in place.

Cons: the whole root is downloaded before the first start. That is fine
for a Corelib root (44 MB), but a Rocq Platform root is several hundred
MB (see [Smaller roots](#smaller-roots-without-opaque-proofs)), while a
session typically reads a small fraction of it.

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

Start with (a), since it is simple, and test it with the Corelib root.
Move to (b) before the standard index goes public: the published roots
are all Rocq Platform roots, whose size makes a full download a poor
first experience. (b) also unifies desktop and web: one `lazyfs.js`,
backed by a disk cache on desktop and by a browser cache on the web (see
[Caching](#caching-lazy-loading-with-a-persistent-cache)).

## Caching: lazy loading with a persistent cache

Today, `lazyfs.js` fetches a file when it is opened, with a synchronous
`XMLHttpRequest`, and keeps it in memory for the session. Across sessions
it relies on the browser's HTTP cache, which synchronous XHRs do use.
GitHub Pages serves every file with `Cache-Control: max-age=600` and an
`ETag`, so after 10 minutes each file costs a revalidation round trip (a
`304`) on its next use, and the browser may evict the files at any time.

There is no ready-made implementation to adopt instead:

- [ZenFS](https://github.com/zen-fs/core) (formerly BrowserFS) has a
  `Fetch` backend driven by an `index.json`, like our manifest. Its cache
  is an in-memory map. Its synchronous reads only work on cached data
  (they throw `EAGAIN` and fetch in the background otherwise), so it
  downloads every file at startup unless told not to. That does not suit
  OCaml's synchronous `open_in` with a root of hundreds of MB.
- Emscripten's [`createLazyFile`](https://emscripten.org/docs/porting/files/Synchronous-Virtual-XHR-Backed-File-System-Usage.html)
  uses synchronous XHRs (in chunks, with range requests) and an in-memory
  cache, like `lazyfs.js`. It is tied to Emscripten's FS. WasmFS has fetch
  and OPFS backends, but they rely on Emscripten's pthreads proxying.
- JupyterLite answers synchronous XHRs from a Service Worker backed by
  IndexedDB. A web extension cannot register a Service Worker on the
  vscode.dev origin, so that is not an option here.

So `lazyfs.js` stays, and gains a persistent layer:

- **Store:** the Origin Private File System (OPFS) in the worker, or Cache
  Storage, under the root's `id`. Roots are immutable, so entries never
  need revalidation, and a root is deleted as a whole.
- **Reads stay synchronous:** OPFS reads through a
  `FileSystemSyncAccessHandle` are synchronous, but opening a handle (and
  everything in Cache Storage) is asynchronous. So the cache is filled
  asynchronously, after a synchronous XHR has fetched a file, and read
  asynchronously at startup: the worker records the files a session
  opened (its *working set*), and the next start loads them from the
  store, together with `manifest.prefetch`, before the server runs.
  Misses fall back to a synchronous XHR, as today.
- **Desktop (option (b)):** the same layer, backed by the cache directory
  through `node:fs`, which is synchronous, so the working-set trick is not
  needed there.
- **Persistence:** `navigator.storage.persist()` asks the browser not to
  evict the store. The quota is per origin (vscode.dev), and is shared
  with VS Code's own storage.

Range requests (GitHub Pages sends `Accept-Ranges: bytes`) would let
`lazyfs.js` fetch only the segments of a `.vo` file that Rocq reads. In
particular it could skip the opaque proofs, which Rocq reads only when it
needs them (see below). That makes reads more complex (a file is no
longer all or nothing), and stripping the proofs when the root is made
gives the same saving more simply.

## Smaller roots without opaque proofs

A `.vo` file is made of segments (`lib/objFile.ml`): `summary`,
`library`, `opaques` (the bodies of the constants ended by `Qed`), and
`vmlibrary`. Rocq reads `opaques` only when it needs an opaque body:
`Print` of such a constant, `Print Assumptions`, extraction. Checking a
proof that uses a lemma only needs the lemma's statement.

In the root with Stdlib, mathcomp-analysis and Iris (1225 `.vo` files,
333 MB):

| segment     | size     | share |
|-------------|----------|-------|
| `library`   | 243.0 MB | 73%   |
| `opaques`   |  84.4 MB | 25%   |
| `vmlibrary` |   4.6 MB |  1%   |
| `summary`   |   0.5 MB |  0%   |

The share depends on the library. Opaque proofs make up 25% of mathcomp
(and analysis), 37% of Stdlib, about 50% of Iris and stdpp, and nothing in
Elpi and HB. Compressed with gzip, they are 56 MB of 173 MB (33%), because
proof terms compress less well than the rest. Stripping them takes the
root from 398 MB to about 314 MB.

### Stripping

`make-web-root` replaces the `opaques` segment of each `.vo` file by an
array of `None` of the same length. That value already means "the body is
not available" (it is what a delayed proof looks like in `-vos` mode).

**Checksums.** Each segment ends with its MD5, and the segment table at the
end of the file repeats it. Both must be rewritten for the new `opaques`
segment: Rocq compares them when it fetches the opaque table, and reports
the file as corrupted otherwise. The digest that identifies a library,
which the files that `Require` it record and check, is the MD5 of the
`library` segment only (`intern_from_file` in `vernac/library.ml`).
Stripping does not touch that segment, so the dependencies stay
consistent and nothing else needs recompiling.

**Behaviour.** Tested with a prototype on Stdlib, with the native
`rocq c`:

- `Require`, tactics (`lia`), `Check`, `Print` of transparent
  definitions, and `Eval compute` work as before;
- `Print Assumptions` reports the opaque bodies it cannot read ("Cannot
  access the opaque body of `ZMicromega.ZTautoChecker_sound`, its
  assumptions are unknown"), so its answer is incomplete;
- `Print` of an opaque constant fails ("Cannot access opaque delayed
  proof").

That is acceptable for a browser IDE, but should be a choice made when
the root is made (`--strip-opaques`), and recorded in the manifest
(`"opaques": false`), so that VsRocq can say why `Print Assumptions`
gives up. A root could also keep the stripped proofs as separate files,
to be fetched on demand, at the cost of a patch to Rocq.

**Bonus:** the integer that makes Stdlib's `Uint63.vo` unloadable with
31-bit integers is in its `opaques` segment, so stripping makes that file
loadable. The ones in `Sint63` and `Sint63Axioms` are in `library` and
`vmlibrary`.

### `vsrocq-make-web-root` in OCaml

`vsrocq-make-web-root` (`web/make-web-root/`) is written in OCaml and
linked with `rocq-runtime`, and implements `--strip-opaques`:

- it reads and writes `.vo` files with Rocq's own `ObjFile`, which keeps
  the segment hashes right by construction, and follows changes to the
  format (the segment ids, `Coq_config.vo_version`). The other segments
  are copied byte for byte;
- `Opaques.opaque_disk` is abstract, but it is an `option array`: the tool
  unmarshals the segment as such and writes an array of `None` of the same
  length;
- with findlib as a library, it computes the plugins and their
  dependencies directly, without running `ocamlfind` hundreds of times
  (2 s instead of 10 s for the root above, and the same output as the
  Python prototype it replaces).

It must be built with the Rocq of the switch. It could move to `rocq-web`,
next to `rocq c`. The 31-bit check parses the generic Marshal format.

## Compressed files

GitHub Pages compresses text formats (it gzips `image/svg+xml`, for
example). `.vo` and `.cma` files have no registered media type, and are
most likely served uncompressed (not checked yet on a published root). So
`--compress` publishes the `.vo`, `.cma` and `.cmo` files compressed with
gzip, at their path followed by `z` (`Foo.voz`), and lists them in the
manifest (`compressed`, with their compressed size). The size in `files`
remains the decompressed one, which `stat` reports.

The decompression is in the file system layer: `lazyfs.js` fetches
`Foo.voz` when the program opens `Foo.vo`, and decompresses it. Reads are
synchronous, and the browser's `DecompressionStream` is asynchronous, so
`lazyfs.js` has its own `gunzip` (inflate decoded as in zlib's `puff`,
120 lines). It decompresses about 100 MB/s in V8, against 450 MB/s for
node's zlib: 0.3 s for the 30 MB a session with mathcomp reads, much less
than the download time. It was checked against zlib on the 1276 compressed
files of the root above.

| root (Stdlib, mathcomp-analysis, Iris) | published |
|----------------------------------------|-----------|
| as is                                  | 398 MB    |
| `--strip-opaques`                      | 313 MB    |
| `--compress`                           | 213 MB    |
| `--strip-opaques --compress`           | 156 MB    |

Compression also helps the persistent cache, which can store the
compressed files.

## Root format

Changes to `manifest.json` (written by `vsrocq-make-web-root`):

- `version`, today the format version (`1`), becomes `format`. A new
  `id` is a content hash of the manifest's file list, and keys the cache;
- a `sha256` for each file, next to its size, which the desktop download
  checks;
- `relocate`: the files that contain the prefix (option (a));
- `rocq` (the Rocq version) and `platform` (the Rocq Platform release),
  shown in the prompt and the status bar. `packages` (already there) is
  copied to the index for choosing a root;
- `opaques`: `false` if the opaque proofs were stripped.

## Security

- **Web:** the server runs in a Web Worker of the vscode.dev origin. It can
  only fetch with CORS, and only sees the files it is given (the root and
  the workspace mirror). A malicious root can at worst give wrong answers.
- **Desktop:** the server runs in node, with `node:fs`, so it can read and
  write any file the user can, just like a `vsrocqtop`. Roots from the
  standard index are trusted like the Rocq Platform releases they are
  built from: they come from the same publisher, and are checked against
  the hashes of their manifest. A custom root (`vsrocq.web.root`, a custom index) is
  trusted like a custom `vsrocq.path`: in a workspace setting, it is only
  used in a trusted workspace (Workspace Trust), after an explicit consent
  naming the URL. Restricting the worker (e.g. node's permission model,
  `--permission` with `--allow-fs-read`/`--allow-fs-write` limited to the
  cache and the workspace) is worth investigating, but it requires a
  separate node process instead of a worker thread.

## Open questions

- **Size of Rocq Platform roots**, and whether to split them (layered
  roots: a base Rocq root plus one per library). For
  reference, a root with Stdlib, mathcomp-analysis (and the mathcomp it
  needs, Elpi and Hierarchy Builder) and Iris is 1312 files, 398 MB
  (198 MB gzipped): mathcomp 132 MB, mathcomp-analysis 79 MB, Elpi and HB
  68 MB (of which 8 MB of examples), Stdlib 46 MB, Rocq plugins 23 MB, the
  programs 21 MB, Iris 16 MB, stdpp 10 MB. A Corelib root is 44 MB. In
  the browser, only 6 MB are fetched at startup either way. Stripping the
  opaque proofs saves 84 MB, and the Elpi examples (8 MB) are not needed.
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

1. `vsrocq-make-web-root`: `id`, `sha256`, `relocate`, `rocq`,
   `platform` in the manifest (`opaques`, `compressed`,
   `--strip-opaques` and `--compress` are done).
2. CI: build and publish a root per Rocq Platform release (per pick),
   immutable, plus `index.json`, at the standard location.
3. `lazyfs.js`: the persistent cache (OPFS or Cache Storage, working
   set).
4. Client: the toolchain selector shared by the desktop and web entries
   (index, opam constraints, user choice, status bar item, command).
5. Desktop: the "Rocq is not installed" offer; download and cache with
   progress and hashes; start `worker.js` in a worker thread; option (a),
   then (b).
6. Desktop: **Rocq: Compile the project** with `rocq-web` from the root
   (`runner.js` in a worker thread, on the real file system). Done for
   `vsrocq.useWasm` (`client/web/node-server.js --run`).
7. Tests: the `client/test-web` tests with an index instead of
   `vsrocq.web.root`, plus a desktop test (`@vscode/test-electron`) with a
   local index and no `vsrocqtop` in the `PATH`.
