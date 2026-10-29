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

## Installing VsRocq

To use VsRocq, you need to:
1. Install the VsRocq language server, and
2. install and configure the VsRocq extension, in either VS Code or VSCodium.

The VS Code extension and the opam package `vsrocq-language-server` are installed and updated separately, and they may stop working if their versions don't match.
See [Extension and language server compatibility](https://github.com/rocq-prover/vsrocq/blob/main/docs/compatibility.md) for which versions work together.
To check which versions you have, run **Rocq: Troubleshooting: Show setup** from the command palette (F1).
See the [troubleshooting](#troubleshooting) section in case of problems.


### Installing the language server

**Installation (Opam)**

After creating an opam switch, pin Rocq, and install the `vsrocq-language-server` package:
```shell
$ opam pin add rocq-core 9.1.0 # replace with correct version
# For Coq 8.x: use coq / coq-core packages instead of rocq-core
$ opam install vsrocq-language-server
# For a specific version, e.g. v2.3.4: opam install vsrocq-language-server.2.3.4
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
When pinning a pre-release language server, ensure you also select the same VsRocq extension version in VS Code.

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
[Language server not found](#language-server-not-found).

#### Pre-release versions

To install a [pre-release version](https://code.visualstudio.com/docs/configure/extensions/extension-marketplace#_install-a-pre-release-extension-version)
or a [specific version](https://code.visualstudio.com/docs/configure/extensions/extension-marketplace#_install-an-extension)
of the extension, see the VS Code guide.
Make sure you also install the same language server version.

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
* `"vsrocq-language-server.trace.server": off | messages | compact | verbose` -- Toggles the tracing of communications between the server and client (defaults to `off`)

#### Memory management (since >= 2.1.7)
* `"vsrocq.memory.limit": int` -- specifies how much memory (in Gb) the server can use before it discards the execution state of closed documents. The check runs each time a document is closed. Defaults to 4Gb.

#### Interrupts
* `"vsrocq.interrupt.preempt": bool` -- Lets hovering and other queries preempt checking tasks (defaults to `false`; recommended for Rocq >= 9.3)

#### Goal and info view panel
* `"vsrocq.goals.auto": bool` -- A toggle to automatically display the goal view when navigating a Rocq document (defaults to `true`)
* `"vsrocq.goals.display": Tabs | List` -- Decide whether to display goals in separate tabs or as a list of collapsibles (defaults to `List`)
* `"vsrocq.goals.messages.full": bool` -- A toggle to include warnings and errors in the proof view (defaults to `true`)
* `"vsrocq.goals.maxDepth": int` -- A setting to determine at which point the goal display starts elliding. Defaults to 17. (since version >= 2.1.7)

#### Proof checking
* `"vsrocq.proof.mode": 0 | 1` -- Decide whether documents should be checked using the classic navigation commands (`0`, Manual) or continuously (`1`, Continuous). Defaults to `0`.
* `"vsrocq.proof.pointInterpretationMode": 0 | 1` -- Determines the point to which the proof should be checked when using the 'Interpret to point' command: up to the last command before the cursor (`0`, Cursor) or through the command after the cursor (`1`, NextCommand). Defaults to `0`.
* `"vsrocq.proof.cursor.sticky": bool` -- a toggle to specify whether the cursor should move as Rocq interactively navigates a document (step forward, backward, etc...). Defaults to `true`.
* `"vsrocq.proof.delegation": None | Skip | Delegate` -- Decides which delegation strategy should be used by the server (defaults to `None`).
  `Skip` allows to skip proofs which are out of focus and should be used in manual mode. `Delegate` allocates a settable amount of workers
  to delegate proofs.
* `"vsrocq.proof.workers": int` -- Determines how many workers should be used for proof checking in `Delegate` mode (defaults to `1`)
* `"vsrocq.proof.block": bool` -- Determines if the execution of a document should halt on the first error.  Defaults to `true` (since version >= 2.1.7).
* `"vsrocq.proof.display-buttons": bool` -- A toggle to control whether buttons related to Rocq (step forward/back, reset, etc.) are displayed in the editor actions menu (defaults to `true`)

#### Code completion (experimental)
* `"vsrocq.completion.enable": bool` -- Toggle code completion (defaults to `false`)
* `"vsrocq.completion.algorithm": 0 | 1` -- Which completion ranking algorithm to use: `0` (SplitTypeIntersection) or `1` (StructuredSplitUnification). Defaults to `1`.
* `"vsrocq.completion.unificationLimit": int` -- Sets the limit for how many theorems unification is attempted (defaults to `100`)

#### Diagnostics
* `"vsrocq.diagnostics.full": bool` -- Toggles the printing of `Info` level diagnostics (defaults to `false`)

## Troubleshooting

This section covers the most common setup problems. For other questions, see the [FAQ](./docs/FAQ.md).

### Diagnosing problems

VsRocq includes two commands to help you find out what is wrong. Run them from
the command palette (F1):

- **Rocq: Troubleshooting: Show setup** shows the versions and paths of your
  VsRocq extension, language server (`vsrocqtop`), Rocq, OS, and VS Code,
  with a button to copy them to the clipboard.
- **Rocq: Troubleshooting: Show Log Output** opens the **VsRocq** output
  channel, where the extension reports problems with finding and starting
  the language server.

Both commands work even if the language server didn't start. In that case,
**Show setup** shows the language server version as "not available".

### Server and extension versions mismatch

The VS Code extension and the opam package `vsrocq-language-server` are installed
and updated separately, and they may stop working if their versions don't match. VS Code
updates extensions automatically, so a mismatch can appear without you changing anything.

Typical symptoms:
- An error saying "This version of VsRocq requires version X of vsrocq-language-server".
- Commands such as "Interpret to point" seem to do nothing.

To check your versions, run **Rocq: Troubleshooting: Show setup** (see [Diagnosing problems](#diagnosing-problems)).
It shows the extension, language server, and Rocq versions together.
If the language server version shows as "not available", check the versions
installed in your current opam switch:
  ```shell
  $ opam list vsrocq-language-server rocq-core coq-core
  ```

If they differ, install the same version of both: either upgrade the language server
(`opam update && opam upgrade vsrocq-language-server`), or
[install the extension version](https://code.visualstudio.com/docs/configure/extensions/extension-marketplace#_install-an-extension)
that matches your language server.
Some other combinations also work. See
[Extension and language server compatibility](https://github.com/rocq-prover/vsrocq/blob/main/docs/compatibility.md)
for the minimum language server version each extension version requires.

### Language server not found

If VsRocq shows a "No language server found" error, it couldn't find `vsrocqtop`.
The **VsRocq** output channel shows `[Toolchain] Did not find vsrocqtop path`.

First, run `which vsrocqtop` in a terminal:

- **It prints nothing:** the language server isn't installed in your current opam
  switch, or the opam environment isn't loaded in that terminal. Run
  `eval $(opam env)` and try again; if it still prints nothing, see
  [Installing the language server](#installing-the-language-server).
- **It prints a path:** VS Code isn't seeing the same `PATH` as your terminal.
  This happens, for example, when VS Code is started from the desktop instead
  of a terminal where the opam environment is loaded. To fix it, either:
  - start VS Code from that terminal (`code .`), or
  - set the "Vsrocq: Path" setting (`vsrocq.path`) to the path printed by
    `which vsrocqtop`.

After changing `vsrocq.path`, run **Developer: Reload Window** from the command
palette (F1). VsRocq only looks for `vsrocqtop` when it starts.
If you change your opam switch instead, fully quit VS Code and start it again, so
that it picks up the new `PATH`.

### Getting help

If you can't set up VsRocq, feel free to ask on the `VsRocq Devs and Users`
[channel in Zulip](https://rocq-prover.zulipchat.com/#narrow/channel/237662-VsRocq-devs-.26-users).
To report a bug, [open an issue](https://github.com/rocq-prover/vsrocq/issues).

In both cases, include the output of **Rocq: Troubleshooting: Show setup**
(see [Diagnosing problems](#diagnosing-problems)).

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
