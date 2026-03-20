[![CI][action-shield]][action-link]
[![Contributing][contributing-shield]][contributing-link]
[![Code of Conduct][conduct-shield]][conduct-link]
[![Zulip][zulip-shield]][zulip-link]

[action-shield]: https://github.com/rocq-prover/vsrocq/actions/workflows/ci.yml/badge.svg
[action-link]: https://github.com/rocq-prover/vsrocq/actions/workflows/ci.yml

[contributing-shield]: https://img.shields.io/badge/contributions-welcome-%23f7931e.svg
[contributing-link]: https://github.com/rocq-prover/vsrocq/manifesto/blob/master/CONTRIBUTING.md

[conduct-shield]: https://img.shields.io/badge/%E2%9D%A4-code%20of%20conduct-%23f15a24.svg
[conduct-link]: https://github.com/rocq-prover/vsrocq/manifesto/blob/master/CODE_OF_CONDUCT.md

[zulip-shield]: https://img.shields.io/badge/chat-on%20zulip-%23c1272d.svg
[zulip-link]: https://rocq-prover.zulipchat.com/#narrow/channel/237662-VsRocq-devs-.26-users

VsRocq is an extension for [Visual Studio Code](https://code.visualstudio.com/)
(VS Code) and [VSCodium](https://vscodium.com/) which provides support for the [Rocq Interactive Theorem Prover](https://rocq-prover.org/). It is built around a language server which natively speaks the [LSP protocol](https://learn.microsoft.com/en-us/visualstudio/extensibility/language-server-protocol?view=vs-2022).

## Supported Rocq versions

**VsRocq** supports all recent Rocq/Coq versions >= 8.18.
If you are running an Coq < 8.18 you should use [VsCoq Legacy](https://github.com/coq-community/vscoq-legacy).

## Installing VsRocq

To use VsRocq, you need to (1) install the VsRocq language server
and (2) install and configure the VsRocq extension in either VS Code or VSCodium.

### Installing the language server

**Version check (recommended).** Before installing the language server, check the installed VsRocq extension version in VS Code (Extensions view → “VsRocq” → version). 
The VS Code extension and the opam package `vsrocq-language-server` are released independently; if their versions are mismatched, the language server may fail during LSP initialization and commands like "Interpret to point" may appear to do nothing.

After creating an opam switch, pin Rocq,
and install the `vsrocq-language-server` package:
```shell
$ opam pin add rocq-core 9.1.0 # replace with correct version 
# For Coq 8.x: use coq / coq-core packages instead of rocq-core
$ opam install vsrocq-language-server.2.3.4 # replace "2.3.4" with correct version
```

or on nixos

```shell
nix profile install nixpkgs#coq_8_18 nixpkgs#coqPackages_8_18.vscoq-language-server
```

If you need a pre-release version, pin a specific release tarball (see "Pre-release versions" below).

After installation, check that you have `vsrocqtop` in your shell
and note the path to this executable:
```shell
$ which vsrocqtop
```


#### Pre-release versions

We often roll out pre-release versions. To get the correct language server version please pin the git repo. For example,
for pre-release ```v2.3.1```:
```shell
$ opam pin add vsrocq-language-server.2.3.1  https://github.com/rocq-prover/vsrocq/releases/download/v2.3.1/vsrocq-language-server-2.3.1.tar.gz
```
When pinning a pre-release language server, ensure you also select the matching VsRocq extension version in VS Code.

### Installing and configuring the extension

To install the [VS Code](https://marketplace.visualstudio.com/items?itemName=rocq-prover.vsrocq)
or [VSCodium extension](https://open-vsx.org/extension/rocq-prover/vsrocq), first run `code`
or `codium`. Then press F1 to open the command palette, start typing
"Extensions: Install Extension", press enter, and search for "vsrocq". Switch to
the **pre-release version** of the extension and enable it. Finally, go to the extension
settings and enter the `vsrocqtop` full path from above in the field "Vsrocq: Path".

If you want asynchronous processing of Rocq files, you can go to
the "Proof: Mode" and select "Continuous". Otherwise, processing will step by step and top-down as in VsCoq1.

#### Pre-release versions

In VsCode, from the extensions page, either use the drop down menu from the ```Uninstall``` button and select ```Install another version```, or click on ```Switch to pre-release```.

### Troubleshooting

Check out the [FAQ](./docs/FAQ.md) for common issues and troubleshooting tips.

#### Known problems

- Getting an ```Unable to start coqtop``` or ```coqtop-stderr: Don't know what to do with -ideslave``` error.
This is a known issue if you are updating from a very old version.
Solution: navigate to your extensions folder (```Extensions: Open Extensions Folder``` from the command palette) and then delete the ```siegbell.vscoq-**version**``` folder.

- Extension hanging: query panel shows a loading bar and shortcuts fail
This could be due to an old ```vscode``` version. Make sure ```vscode``` is up to date.

#### Getting help

If you are unable to set-up vsrocq, feel free to contact us on the ```VsRocq Devs and Users``` [channel in zulip](https://rocq-prover.zulipchat.com/#narrow/channel/237662-VsRocq-devs-.26-users).

## Features
* Syntax highlighting
* Asynchronous proof checking
* Continuous and incremental checking of Rocq documents

Vsrocq allows users to opt for continuous checking, see the goal panel update as you scroll or edit your document.
![](gif/continuous-mode.gif)

By default, vsrocq is configured to use classic step by step checking mode. 
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

* Supports \_CoqProject

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
* `"vsrocq.goals.diff.mode": on | off | removed` -- Toggles diff mode. If set to `removed`, only removed characters are shown (defaults to `off`)
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

## For extension developers 
See [Dev docs](https://github.com/rocq-prover/vsrocq/blob/main/docs/developers.md)

## Maintainers

This extension is currently developed and maintained by
[Enrico Tassi](https://github.com/gares),
[Romain Tetley](https://github.com/rtetley).

## License
Unless mentioned otherwise, files in this repository are [distributed under the MIT License](LICENSE).

The following files are also distributed under the MIT License, Copyright (c) Christian J. Bell and contributors:
* `client/syntax/coq.tmLanguage.json`
* `client/syntax/rocq.tmLanguage.json`
* `client/coq.language-configuration.json`
* `client/rocq.language-configuration.json`
