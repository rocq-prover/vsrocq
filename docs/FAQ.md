# VsRocq Frequently Asked Questions (FAQ)

Welcome to the VsRocq FAQ! This document aims to answer common questions and help troubleshoot issues you might encounter while using the VsRocq extension for VS Code with the Rocq/Coq Theorem Prover.

## Table of Contents

- [VsRocq Frequently Asked Questions (FAQ)](#vsrocq-frequently-asked-questions-faq)
  - [Table of Contents](#table-of-contents)
  - [1. Installation and Setup](#1-installation-and-setup)
  - [2. Usage and Features](#2-usage-and-features)
  - [3. Troubleshooting Common Issues](#3-troubleshooting-common-issues)

---

## 1. Installation and Setup

1.  **How do I install VsRocq?**

    See [Installing VsRocq](../README.md#installing-vsrocq) in the README.

1.  **How do I install a pre-release version?**

    See the "Pre-release versions" subsections of the README, for the
    [language server](../README.md#pre-release-versions) and for the
    [extension](../README.md#pre-release-versions-1).

1.  **VS Code says `vsrocqtop` not found or the extension doesn't load.**

    See [Language server not found](../README.md#language-server-not-found) in the README.

    - On macOS, if VsRocq still can't find `vsrocqtop` after installing it, fully quit
      VS Code (Cmd+Q) and start it again. Reloading the window isn't always enough.

1.  **VsRocq says "Could not launch language server".**

    VsRocq found `vsrocqtop`, but it failed when VsRocq started it. When it starts,
    VsRocq runs `vsrocqtop -where` and `vsrocqtop -v` to find your Rocq installation.
    To see the full error, run the same commands in a terminal, adding any
    arguments from your `vsrocq.args` setting:

    ```shell
    $ vsrocqtop -where
    $ vsrocqtop -v
    ```

    Common causes:
    - An invalid argument in the `vsrocq.args` setting. VsRocq passes these
      arguments to both commands.
    - A broken or incomplete Rocq installation in your opam switch.
    - `vsrocq.path` points to a different program, such as `coqtop` or `rocq`,
      instead of `vsrocqtop`.

1.  **I used VsCoq before. What do I need to change?**

    VsCoq was renamed to VsRocq in version 2.3.0. Everything that had `vscoq` in its
    name now has `vsrocq`:

    | | VsCoq (up to 2.2.6) | VsRocq (2.3.0 and later) |
    |---|---|---|
    | VS Code extension | `maximedenes.vscoq` | `rocq-prover.vsrocq` |
    | opam package | `vscoq-language-server` | `vsrocq-language-server` |
    | Language server | `vscoqtop` | `vsrocqtop` |
    | Settings | `vscoq.*` | `vsrocq.*` |

    - Uninstall the VsCoq extension and install VsRocq. Don't keep both enabled.
    - The VsRocq extension needs `vsrocqtop`. If your Rocq installation only provides
      `vscoqtop` (for example, an older Rocq Platform), install the language server
      with opam as described in [Installing the language server](../README.md#installing-the-language-server).
    - Rename your `vscoq.*` settings to `vsrocq.*`, and point `vsrocq.path` to
      `vsrocqtop`, not `vscoqtop`.
    - If you see `Unable to start coqtop` or `coqtop-stderr: Don't know what to do with -ideslave`,
      an old VsCoq version (e.g., `siegebell.vscoq`) is interfering. This happens when updating
      from a very old version. Uninstall it; if the error persists, run
      "Extensions: Open Extensions Folder" from the command palette and delete the
      `siegebell.vscoq-<version>` folder. Also make sure `vsrocq.path` points to `vsrocqtop`, not `coqtop`.
    - If you use Coq 8.17 or older, use [VsCoq Legacy](https://github.com/coq-community/vscoq-legacy) instead.

1.  **How does VsRocq find my `_RocqProject` or `_CoqProject` file?**

    VsRocq uses your project file to resolve `Require Import` statements.

    - For each `.v` file, it looks for a `_RocqProject` file in the file's folder and its
      parent folders. If it finds none, it looks for a `_CoqProject` file the same way.
      This lets a workspace contain several sub-projects.
    - With Coq 8.18–8.20, or with language server versions older than 2.2.2, VsRocq
      only uses the project file found from the root of your VS Code workspace.
      If your project file is in a subfolder (e.g., `theories/`), open that subfolder
      as the workspace.
    - **VsRocq does not compile your project.** Compile your `.v` files separately
      (e.g., with `make` or `dune build`) so that VsRocq can find the `.vo` files.
    - If VsRocq doesn't pick up rebuilt `.vo` files, run "Developer: Reload Window".
      To reload a `Require Import`, re-evaluate it (e.g., "Reset", then "Interpret to point").
    - You can also pass `-R` or `-Q` arguments directly in the `vsrocq.args` setting.
    - To see which project file VsRocq loaded, add `"-vsrocq-d", "args"` to
      `vsrocq.args`, reload the window, and look for `Arguments from project file`
      in the "Rocq Language Server" output channel.

1.  **The extension asks me to upgrade the language server.**

    Your extension and language server versions don't match. See
    [Server and extension versions mismatch](../README.md#server-and-extension-versions-mismatch)
    in the README.

    If you want to stay on your current language server version, also turn off
    [automatic updates](https://code.visualstudio.com/docs/configure/extensions/extension-marketplace#_extension-auto-update)
    for the VsRocq extension. Otherwise VS Code updates it and the mismatch comes back.

1.  **How do I use different Rocq versions for different projects?**

    Use one opam switch per Rocq version, and install `vsrocq-language-server` in
    each switch. Each `vsrocqtop` only works with the Rocq version it was built with.

    VsRocq doesn't follow opam switch changes: it uses the `vsrocqtop` it finds when
    it starts. To use the right one for each project, either:

    - **Set `vsrocq.path` in the Workspace settings of each project.** Open the
      project, open the Settings editor (F1, then "Preferences: Open Workspace Settings"),
      make sure the **Workspace** tab is selected, search for `vsrocq.path`, and enter
      the `vsrocqtop` of that project's switch. To find it, run
      `opam exec --switch=<switch> -- which vsrocqtop`.
      VS Code saves the setting in the project's `.vscode/settings.json`. If you set it
      in the **User** tab instead, it applies to all your projects.
    - **Start VS Code from a terminal where the right switch is active**, and leave
      `vsrocq.path` empty. For example, link the switch to the project folder once
      with `opam switch link <switch> .`, and then, from that folder, run
      `eval $(opam env)` and `code .`.

    After changing `vsrocq.path`, run "Developer: Reload Window". After changing
    your switch, fully quit VS Code and start it again.

---

## 2. Usage and Features

1.  **My settings are not being applied.**

    First, ensure you are editing the correct `settings.json` file.

    Additionally, if you had settings from an older version of VsCoq, they might not be compatible with the new version. Check [Settings](../README.md#settings) in the README for updated settings.

    In particular, settings `vscoq.*` have transitioned to `vsrocq.*` in the new version.

1.  **How do I step through proofs?**

    Proof navigation mode is governed by the setting `"vsrocq.proof.mode"`

    - **Manual Mode (default)** (`"vsrocq.proof.mode": 0`):: Use commands like "Rocq: Step Forward" (Alt+Down), "Rocq: Step Backward" (Alt+Up), "Rocq: Interpret to Point", and "Rocq: Interpret to End". These are in the command palette (F1) and often have toolbar buttons.
    - **Continuous Mode** (`"vsrocq.proof.mode": 1`): VsRocq always attempts to check the document as you scroll or edit up to the point of your cursor.

1.  **The Proof View / Goal Panel isn't showing.**

    - Ensure VsRocq is installed correctly and "VsRocq: Path" points to `vsrocqtop`.
    - The panel typically appears when you step into a proof (e.g., after "Rocq: Step Forward" on a `Proof.` command).
    - If it turned grey and unresponsive, it might be a renderer crash (possibly OOM). Try closing and reopening the panel, or "Developer: Reload Window".

1.  **How do I see output from `Print`, `Check`, `Search`, `Locate`, `About`, `Time`?**

    - VsRocq has a dedicated **Query Panel** for `Search`, `Check`, `About`, `Locate`, and `Print`. You can type queries there or use shortcuts/context menus.
    - For commands executed inline in your `.v` file (like `Print nat.`), the output appears as a message in the **Goal Panel**. Hovering over the executed command (which will have a blue squiggly underline) also shows the output.
    - If messages from `Print`, `Check` etc. are not displayed in the goal panel, check the `"vsrocq.goals.messages.full"` setting (default is `true`).
    - For `Time`, output might also go to the "Rocq Log" or messages panel, depending on the specific Rocq version and VsRocq handling.
    - If `Search` results are unreadable (e.g., invisible text), it might be a theme conflict or a custom `editorInfo.foreground` color setting. Try a default theme or check your `workbench.colorCustomizations`.

1.  **How do I see debug messages (e.g., from `Set Typeclasses Debug` or `Feedback.msg_debug`)?**

    These messages are typically routed to the **"Rocq Log" output channel** in VS Code, not the main Goal Panel. Some tactics like `debug auto` might print to the goal panel (as "Notice" level), while `debug eauto` prints to the "Rocq Log" (as "Debug" level) because of how Rocq itself categorizes these messages.

1.  **How can I see the full proof term for `Show Proof.` if it shows `[...]`?**

    - Increase `"vsrocq.goals.maxDepth"` in settings (default 17).
    - In the Goal Panel, Alt+Click on `[...]` expands it.

      Shift+Alt+Click expands it fully.

1.  **Is there a shortcut for queries like `Search` without selecting text first?**

    VsRocq has commands like `Rocq: Search selection` which use the currently selected text. To search for arbitrary text without prior selection, you'd typically open the Query Panel manually and type into its input field.

1.  **How are multiple goals displayed? Contexts for goals other than the first are hidden.**

    Yes, if multiple goals are generated, only the context of the first goal is expanded by default. Other goals appear collapsed but can be expanded by clicking the "eye" icon next to them.

    You can choose between `"List"` or `"Tabs"` for `"vsrocq.goals.display"`.

---

## 3. Troubleshooting Common Issues

1.  **Which output channel should I look at?**

    VsRocq writes to three output channels (View → Output, then pick one from the dropdown):

    - **VsRocq**: messages from the extension itself, such as problems finding or starting
      `vsrocqtop` and the version check. "Rocq: Troubleshooting: Show Log Output" opens it.
    - **Rocq Language Server**: messages from the language server, including errors,
      backtraces, and the debug output you enable with `-vsrocq-d` in `vsrocq.args`.
    - **Rocq Log**: debug messages from Rocq itself, such as the output of
      `Set Typeclasses Debug`.

1.  **VsRocq / The Language Server keeps crashing or restarting frequently.**

    This is a common frustration and can have several causes:

    - **Memory Usage:** `vsrocqtop` can be memory-intensive, especially with large files or libraries like MetaCoq. Try increasing the memory limit for your VS Code/system if possible, or close other demanding applications. VsRocq has a setting `"vsrocq.memory.limit"` (default 4GB) that attempts to free memory by discarding states of closed documents when the limit is hit, but this might not always prevent high usage during active processing.
    - **Diagnosing Crashes:**
      - Check the **"Rocq Language Server" output channel** in VS Code for error messages and backtraces.
      - For more detail, add `"-vsrocq-d", "all"` and `"-bt"` to `"vsrocq.args"` in your `settings.json`.
    - **Restarting the Server:** If VsRocq tells you "The Rocq Language Server server crashed 5 times in the last 3 minutes. The server will not be restarted.", use the "Developer: Reload Window" command (F1, then type the command) to fully restart. You might also need to manually kill stray `vsrocqtop` processes.

1.  **Hover information only works if all preceding code has been checked.**

    Hover details often rely on Rocq providing information about the term at the current state, which means the document needs to be processed up to that point. If hover isn't working as expected, ensure the relevant previous parts of the file is checked (green).

1.  **My file has a parsing error, but VsRocq allows me to continue executing commands.**

    This was a bug in older versions. If "Block on first error" mode is on (`"vsrocq.proof.block": true`, default since v2.1.7), VsRocq should halt. Version 2.2.4 specifically fixed parse errors being treated correctly for this mode.

1.  **The Language Server seems to get out of sync, with "Wrong bullet" errors.**

    This indicates a temporary desynchronization. Saving the file, or sometimes removing and re-adding the problematic bullet and then saving, can help resynchronize.

    Additionally, reloading the VS Code window (F1, then "Developer: Reload Window") can often resolve these issues.

1.  **The extension hangs: the query panel shows a loading bar and shortcuts don't work.**

    This can be caused by an old VS Code version. Make sure VS Code is up to date.

---

If your question isn't answered here, please check the [VsRocq README](../README.md), search the [VsRocq Zulip chat archives](https://rocq-prover.zulipchat.com/#narrow/channel/237662-VsRocq-devs-.26-users), or consider [opening an issue](https://github.com/rocq-prover/vsrocq/issues) on our GitHub repository.
