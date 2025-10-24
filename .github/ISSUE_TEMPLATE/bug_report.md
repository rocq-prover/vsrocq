---
name: Bug Report
about: Create a report to help us improve VsRocq
title: "[BUG] Brief description of the bug"
labels: bug
assignees: ""
---

**IMPORTANT: Before You Submit This Issue**

- [ ] I have searched the [existing VsRocq issues](https://github.com/rocq-prover/vsrocq/issues)
- [ ] I have reviewed the [VsRocq FAQ.md](https://github.com/rocq-prover/vsrocq/blob/main/FAQ.md) and my issue is not addressed there.

**Describe the Bug**

A clear and concise description of what the bug is.

**To Reproduce**

Steps to reproduce the behavior:

1. Go to '...'
2. Click on '....'
3. Scroll down to '....'
4. See error

**Expected vs. Actual Behavior**

A clear and concise description of what you expected to happen vs.
what actually happened. Include any error messages or stack traces.

If applicable, add screenshots and code to help explain your problem.

**Environment (paste the result of `Rocq: Troubleshooting: Show Setup`):**

<!-- Replace the below with your actual environment details. -->

| Debug Information        | Value |
| ------------------------ | ----- |
| Rocq Installation        | ...   |
| Rocq Path                | ...   |
| VsRocq Extension Version | ...   |
| VsRocqTop Version        | ...   |
| VsRocqTop Path           | ...   |
| OS                       | ...   |
| VSCode Version           | ...   |

**Rocq Log Output (if applicable)**

If the issue involves a server crash or unexpected Rocq behavior, please provide logs from the "Rocq Language Server" output channel in VS Code.
To get detailed logs:

1. Open your VS Code `settings.json`.
2. Add/modify the `vsrocq.args` setting:
   ```json
   "vsrocq.args": [
       "-bt",
       "-vsrocq-d",
       "all"
   ]
   ```
3. Reproduce the bug and copy the relevant output from the "Rocq Language Server" channel here.
   ```
   <LOG OUTPUT HERE>
   ```
