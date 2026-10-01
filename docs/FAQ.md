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

    You need to install both the VsRocq language server and the VS Code extension.

    - **Language Server (`vsrocq-language-server`):**

      After creating an opam switch (optional), install the server using:
      `opam install vsrocq-language-server`

      Verify `vsrocqtop` is in your PATH by running `which vsrocqtop`.

    - **VS Code Extension:**

      Search for "vsrocq" (by `rocq-prover.vsrocq`) in the VS Code Marketplace or VSCodium's Open VSX Registry and install it.

1.  **How do I install a pre-release version?**

    For a pre-release of the language server, pin the preferred version (e.g., `v2.1.5`) via:
    `opam pin add vscoq-language-server.2.1.5  https://github.com/coq/vscoq/releases/download/v2.1.5/vscoq-language-server-2.1.5.tar.gz`

    For the VS Code extension, go to the extensions page, click the gear icon on VsRocq, and select "Install Another Version..." or "Switch to Pre-Release Version".

1.  **VS Code says `vsrocqtop` not found or the extension doesn't load.**

    This is usually a PATH issue or an issue with how VS Code was launched.

    - Ensure your opam environment is active in the terminal from which you launch VS Code (run `eval $(opam env)`).
    - The most reliable method is to set the explicit full path to `vsrocqtop` in the `vsrocq.path` extension setting.
    - On macOS, fully restarting VS Code (Quit and Relaunch) after installation might be necessary.
    - If you see `Unable to start coqtop` or `coqtop-stderr: Don't know what to do with -ideslave`,
      an old VsCoq version (e.g., `siegebell.vscoq`) is interfering. This happens when updating
      from a very old version. Uninstall it; if the error persists, run
      "Extensions: Open Extensions Folder" from the command palette and delete the
      `siegebell.vscoq-<version>` folder. Also make sure `vsrocq.path` points to `vsrocqtop`, not `coqtop`.

1.  **How does VsRocq handle `_CoqProject` files for finding `.vo` files?**

    - VsRocq needs to know how to resolve `Require Import` statements. It does this by looking for a `_CoqProject` file.
    - Older versions (around 2.0.x - 2.2.1) primarily looked for `_CoqProject` in the root of your VS Code workspace.
    - Newer versions aim to find the `_CoqProject` file closest to the `.v` file you are editing, supporting multiple sub-projects within a workspace.
    - If your `_CoqProject` is not in the workspace root (e.g., in a `theories/` subdirectory), ensure your VsRocq and language server versions are recent enough or open the subdirectory as the workspace root.
    - **VsRocq does not compile your project.** You must compile your `.v` files (e.g., using `make` or `dune build`) separately for VsRocq to find the `.vo` files specified by `_CoqProject`.
    - If changes to `.vo` files are not picked up after a rebuild, use the "Developer: Reload Window" command in VS Code. To reload new `Require Import`s, you'll need to re-evaluate those lines (e.g., "Reset" then "Interpret to point").
    - You can pass `-R` or `-Q` arguments directly via `"vsrocq.args"` in `settings.json` if needed.
    - To debug which `_CoqProject` is loaded, check the "Rocq Language Server" output channel in VS Code.

1.  **The extension prompts me to upgrade the language server, but I think it's correct.**

    The message "This version of VsRocq requires version X.Y.Z of vsrocq-language-server. Found version: A.B.C" means your `vsrocq-language-server` opam package needs an update, not the VS Code extension itself. Run `opam update && opam upgrade vsrocq-language-server`.

    If you wish to stay on the current version of `vsrocq-language-server` that you have, you may need to disable auto-updates for the VS Code extension and utilized "Install a specific version" to pin your extension to match your desired language server version.

1.  **How do I use different Rocq versions with VsRocq for different projects?**

    Use opam switches to manage different Rocq installations.

    - You can launch VS Code from a terminal where the desired opam switch is activated (after `eval $(opam env)`). VsRocq will use `vsrocqtop` from that switch if `vsrocq.path` is empty or correctly set.
    - `opam switch link <SWITCH_NAME> .` can associate a switch with a project directory.
    - The `vsrocq-language-server` is often compatible with multiple Rocq versions due to conditional compilation. If there's a mismatch between the extension and server capabilities, VsRocq might prompt you.

---

## 2. Usage and Features

1.  **My settings are not being applied.**

    First, ensure you are editing the correct `settings.json` file.

    Additionally, if you had settings from an older version of VsCoq, they might not be compatible with the new version. Check the [VsRocq README](README.md) for updated settings.

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

If your question isn't answered here, please check the [VsRocq README](README.md), search the [VsRocq Zulip chat archives](https://rocq-prover.zulipchat.com/#narrow/stream/237662-VsCoq-devs-.26-users), or consider [opening an issue](https://github.com/rocq-prover/vsrocq/issues) on our GitHub repository.
