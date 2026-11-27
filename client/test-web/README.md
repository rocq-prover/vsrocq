# Test of the web extension

Runs in VS Code for the web (`@vscode/test-web`), on a published opam root
served on port 8001 (the settings of the folders point `vsrocq.web.root`
to it):

- `smoke.js` with the `workspace` folder: open a document, check the
  diagnostics;
- `project.js` with the `project` folder: compile the project
  (`_RocqProject`, `B.v` requires `A.v`) with "Rocq: Compile the project",
  then check `C.v`, which requires both.

```sh
npm run build:web
vsrocq-make-web-root /tmp/root
python3 ../../web/test/serve.py ../../web/test /tmp/root &   # root on :8001
npx @vscode/test-web --headless --coi --browser=chromium --extensionDevelopmentPath=.. \
  --extensionTestsPath=$PWD/smoke.js $PWD/workspace
npx @vscode/test-web --headless --coi --browser=chromium --extensionDevelopmentPath=.. \
  --extensionTestsPath=$PWD/project.js $PWD/project
```

The paths must be absolute. Without `--headless`, closing the browser
window stops the test. `project` is checked in continuous mode (by default
the extension is in manual mode, where only the errors found while parsing,
like a missing library, are reported). The `console.log` of the nested workers is not
shown; the tests also post their log to `serve.py`.
