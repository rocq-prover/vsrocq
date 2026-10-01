[![CI][action-shield]][action-link]
[![Zulip][zulip-shield]][zulip-link]

[action-shield]: https://github.com/rocq-prover/vsrocq/actions/workflows/ci.yml/badge.svg
[action-link]: https://github.com/rocq-prover/vsrocq/actions/workflows/ci.yml

[zulip-shield]: https://img.shields.io/badge/chat-on%20zulip-%23c1272d.svg
[zulip-link]: https://rocq-prover.zulipchat.com/#narrow/channel/237662-VsRocq-devs-.26-users

VsRocq is an extension for [Visual Studio Code](https://code.visualstudio.com/)
(VS Code) and [VSCodium](https://vscodium.com/) which provides support for the [Rocq Interactive Theorem Prover](https://rocq-prover.org/). It is built around a language server which natively speaks the [LSP protocol](https://learn.microsoft.com/en-us/visualstudio/extensibility/language-server-protocol?view=vs-2022).

## Supported Rocq versions

**VsRocq** supports all recent Rocq/Coq versions >= 8.18.
If you are running an Coq < 8.18 you should use [VsCoq Legacy](https://github.com/coq-community/vscoq-legacy).
For the exact versions supported by each release, see the [compatibility matrix](#compatibility-matrix).

## Installing VsRocq

To use VsRocq, you need to:
1. Install the VsRocq language server, and
2. install and configure the VsRocq extension, in either VS Code or VSCodium.

The opam package `vsrocq-language-server` and the VS Code extension are released independently, and they may stop working if their versions don't match.
For the exact compatible versions supported by each release, see the [compatibility matrix](#compatibility-matrix).
See the [troubleshooting](#troubleshooting) section in case of problems.


### Installing the language server

**Installation (Opam)**

After creating an opam switch, pin Rocq, and install the `vsrocq-language-server` package:
```shell
$ opam pin add rocq-core 9.1.0 # replace with correct version
# For Coq 8.x: use coq / coq-core packages instead of rocq-core
$ opam install vsrocq-language-server.2.3.4 # replace "2.3.4" with correct version
```

**Installation (nixos)**

```shell
nix profile install nixpkgs#coq_8_18 nixpkgs#coqPackages_8_18.vscoq-language-server
```

**Verify installation**

After the previous steps, check that you have `vsrocqtop` in your shell:
```shell
$ which vsrocqtop
```


#### Pre-release versions

We often roll out pre-release versions. To get the correct language server version please pin the git repository. For example,
for pre-release ```v2.3.1```:
```shell
$ opam pin add vsrocq-language-server.2.3.1  https://github.com/rocq-prover/vsrocq/releases/download/v2.3.1/vsrocq-language-server-2.3.1.tar.gz
```
When pinning a pre-release language server, ensure you also select the matching VsRocq extension version in VS Code ([compatibility matrix](#compatibility-matrix)).

#### Using a Local Version of Rocq

See the developers [documentation](https://github.com/rocq-prover/vsrocq/blob/main/docs/developers.md#composing-the-build-with-rocq).

### Installing and configuring the extension

Install VsRocq from the [VS Code Marketplace](https://marketplace.visualstudio.com/items?itemName=rocq-prover.vsrocq)
or, for VSCodium, from [Open VSX](https://open-vsx.org/extension/rocq-prover/vsrocq).
In the Extensions view, search for "vsrocq" and pick the one published by `rocq-prover`.
If you haven't installed an extension before, see the VS Code guide on
[installing extensions](https://code.visualstudio.com/docs/configure/extensions/extension-marketplace).

By default, VsRocq uses the `vsrocqtop` found in your `PATH`, so no further
configuration is needed. If VsRocq can't find it, see
[Language server not found](#troubleshooting).

#### Pre-release versions

To install a [pre-release version](https://code.visualstudio.com/docs/configure/extensions/extension-marketplace#_install-a-pre-release-extension-version)
or a [specific version](https://code.visualstudio.com/docs/configure/extensions/extension-marketplace#_install-an-extension)
of the extension, see the VS Code guide.
Make sure the language server version matches (see the [compatibility matrix](#compatibility-matrix)).

### Troubleshooting

We list some common problems here, otherwise check out the [FAQ](./docs/FAQ.md) for more issues and troubleshooting tips.

**Server and extension versions mismatch**

The opam package `vsrocq-language-server` and the VS Code extension are released independently, and they may stop working if their versions don't match.
To pick matching versions:
1. Check the installed VsRocq extension version in VS Code (Extensions view → “VsRocq” → version).
2. Check the language server and Rocq versions installed in your current opam switch:
  ```shell
  $ opam list vsrocq-language-server rocq-core coq-core
  ```
3. Compare using the [compatibility matrix](#compatibility-matrix).

**Language server not found**

If VsRocq shows a "No language server found" error even though `which vsrocqtop`
works in your shell, VS Code is probably not seeing the same `PATH` as your shell.
This happens, for example, when VS Code is started from the desktop instead of a
terminal where the opam environment is loaded.
To fix it, either start VS Code from that terminal (`code .`), or set the full path
to `vsrocqtop` (the output of `which vsrocqtop`) in the "Vsrocq: Path" setting
(`vsrocq.path`).


#### Known problems

- Getting an ```Unable to start coqtop``` or ```coqtop-stderr: Don't know what to do with -ideslave``` error.
This is a known issue if you are updating from a very old version.
Solution: navigate to your extensions folder (```Extensions: Open Extensions Folder``` from the command palette) and then delete the ```siegbell.vscoq-**version**``` folder.

- Extension hanging: query panel shows a loading bar and shortcuts fail
This could be due to an old ```vscode``` version. Make sure ```vscode``` is up to date.

#### Getting help

If you are unable to set-up VsRocq, feel free to contact us on the ```VsRocq Devs and Users``` [channel in zulip](https://rocq-prover.zulipchat.com/#narrow/channel/237662-VsRocq-devs-.26-users).

## Features
* Syntax highlighting
* Asynchronous proof checking
* Continuous and incremental checking of Rocq documents

Vsrocq allows users to opt for continuous checking, see the goal panel update as you scroll or edit your document.
![](gif/continuous-mode.gif)

By default, vsrocq is configured to use classic step by step checking mode.
To switch between the two, change the "Proof: Mode" setting (`vsrocq.proof.mode`).
![](gif/manual-mode.gif)

* Customisable goal panel

Users can choose their preferred display mode, see goals in accordion lists...
![](gif/goals-accordion.gif)

... Or organized in tabs.
![](gif/goals-tab.gif)

* Dedicated panel for queries and their history

We now support a dedicated panel for queries. We currently support Search, Check, About, Locate and Print with plans
to add more in the future.
![](gif/query-panel.gif)

* Messages in the goal panel

We also support inline queries which then trigger messages in the goal panel.
![](gif/messages.gif)

* Supports \_RocqProject/\_CoqProject

### Since version 2.1.7

* Outline

We now support a document outline, which displays theorems and definitions in the document.

![](gif/outline.gif)

* Ellipsis for the goal panel

Goals can now be ellided. First through the `"vsrocq.goals.maxDepth"` setting which ellides a goal if the display becomes to large.
Finally by clicking on the goal view as showcased here.
The following modifiers can be used:
- ```Alt + Click```: open/close an ellipsis (only opens partially).
- ```Shift + Alt + Click```: fully open an ellipsis (all children are also opened).

![](gif/goal-ellipsis.gif)

* Quickfixes (only for Rocq/Coq >= 8.21)

We have added support for quickfixes. However, quickfixes rely on some Rocq API which will only make it in the 8.21 release.
Developpers are encouraged to list and add their own quickfixes in the Rocq source code.

![](gif/quickfix.gif)

* Block on first error

We support the classic block on error mode, in which the execution of a document is halted upon reaching an error. This affects both checking modes (Continuous and Manual). A user can opt out of this execution mode by setting it to false in the user settings.

![](gif/block-on-error.gif)

### Settings
After installation and activation of the extension:

(Press `F1` and start typing "settings" to open either workspace/project or user settings.)
#### Rocq configuration
* `"vsrocq.path": ""` -- specify the path to `vsrocqtop` (e.g. `path/to/vsrocq/bin/vsrocqtop`)
* `"vsrocq.args": []` -- an array of strings specifying additional command line arguments for `vsrocqtop` (typically accepts the same flags as `rocqtop`)
* `"vsrocq-language-server.trace.server": off | messages | verbose` -- Toggles the tracing of communications between the server and client

#### Memory management (since >= 2.1.7)
* `"vsrocq.memory.limit: int` -- specifies the memory limit (in Gb) over which when a user closes a tab, the corresponding document state is discarded in the server to free up memory. Defaults to 4Gb.

#### Goal and info view panel
* `"vsrocq.goals.display": Tabs | List` -- Decide whether to display goals in separate tabs or as a list of collapsibles.
* `"vsrocq.goals.messages.full": bool` -- A toggle to include warnings and errors in the proof view (defaults to `false`)
* `"vsrocq.goals.maxDepth": int` -- A setting to determine at which point the goal display starts elliding. Defaults to 17. (since version >= 2.1.7)

#### Proof checking
* `"vsrocq.proof.mode": Continuous | Manual` -- Decide whether documents should checked continuously or using the classic navigation commmands (defaults to `Manual`)
* `"vsrocq.proof.pointInterpretationMode": Cursor | NextCommand` -- Determines the point to which the proof should be check to when using the 'Interpret to point' command.
* `"vsrocq.proof.cursor.sticky": bool` -- a toggle to specify whether the cursor should move as Rocq interactively navigates a document (step forward, backward, etc...)
* `"vsrocq.proof.delegation": None | Skip | Delegate` -- Decides which delegation strategy should be used by the server.
  `Skip` allows to skip proofs which are out of focus and should be used in manual mode. `Delegate` allocates a settable amount of workers
  to delegate proofs.
* `"vsrocq.proof.workers": int` -- Determines how many workers should be used for proof checking
* `"vsrocq.proof.block": bool` -- Determines if the the execution of a document should halt on first error.  Defaults to true (since version >= 2.1.7).
* `"vsrocq.proof.display-buttons": bool` -- A toggle to control whether buttons related to Rocq (step forward/back, reset, etc.) are displayed in the editor actions menu (defaults to `true`)

#### Code completion (experimental)
* `"vsrocq.completion.enable": bool` -- Toggle code completion (defaults to `false`)
* `"vsrocq.completion.algorithm": StructuredSplitUnification | SplitTypeIntersection` -- Which completion algorithm to use
* `"vsrocq.completion.unificationLimit": int` -- Sets the limit for how many theorems unification is attempted

#### Diagnostics
* `"vsrocq.diagnostics.full": bool` -- Toggles the printing of `Info` level diagnostics (defaults to `false`)

## Compatibility matrix

The VsRocq extension and the `vsrocq-language-server` opam package are
released separately. To pick matching versions:

1. Find your extension version in the first table. It gives the minimum
   language server version that you need.
2. In the second table, pick a language server version at or above that
   minimum that supports your Rocq version.

When in doubt, use the latest extension with the latest language server.

**Extension and server versions**

| Extension version | Minimum language server version |
|---|---|
| 2.5.0 | 2.3.3 |
| 2.4.3 | 2.3.3 |
| 2.4.0 – 2.4.2 | 2.4.0 |
| 2.3.3 – 2.3.4 | 2.3.3 |
| 2.3.0 – 2.3.2 | 2.3.0 |
| 2.2.6 | 2.2.6 |
| 2.2.5 | 2.2.5 |
| 2.2.4 | 2.2.4 |
| 2.2.2 – 2.2.3 | 2.2.2 |
| 2.2.1 | 2.2.1 |
| 2.1.7 – 2.2.0 | 2.1.7 |
| 2.1.5 – 2.1.6 | 2.1.5 |
| 2.1.3 | 2.1.3 |
| 2.1.2 | 2.1.2 |
| 2.1.1 | 2.1.1 |
| 2.0.3 – 2.1.0 | 2.0.3 |
| 2.0.0 – 2.0.2 | 2.0.0 |

**Language server and Rocq/Coq versions**

| Language server version | Coq (`coq-core`) | Rocq (`rocq-core`) |
|---|---|---|
| 2.5.0 | 8.18 – 8.20 | 9.0 – 9.3, `dev` |
| 2.4.0 – 2.4.3 | 8.18 – 8.20 | 9.0 – 9.2, `dev` |
| 2.3.0 – 2.3.4 | 8.18 – 8.20 | 9.0 – 9.1, `dev` |
| 2.1.7 – 2.2.6 | 8.18 – 8.20 | — |
| 2.1.0 – 2.1.6 | 8.18 – 8.19 | — |
| 2.0.0 – 2.0.3 | 8.18 | — |

All language server versions from 2.1.7 onwards require OCaml >= 4.14.

If the installed language server is older than the extension requires,
the extension shows an error at startup that names the required version.

## For extension developers
See [Dev docs](https://github.com/rocq-prover/vsrocq/blob/main/docs/developers.md)

## Maintainers

This extension is currently developed and maintained by
[Enrico Tassi](https://github.com/gares),
[Romain Tetley](https://github.com/rtetley).

## License
Unless mentioned otherwise, files in this repository are [distributed under the MIT License](LICENSE).

The following files are also distributed under the MIT License, Copyright (c) Christian J. Bell and contributors:
* `client/syntax/rocq.tmLanguage.json`
* `client/syntax/rocq.language-configuration.json`
