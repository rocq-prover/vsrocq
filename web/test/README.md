# Browser test

Runs the LSP smoke test in a browser, against a published opam root, as in
VS Code for the web: the page is cross-origin isolated, the root is served
from another origin with only `Access-Control-Allow-Origin: *` (like GitHub
Pages), the worker script is the extension's `client/web/bootstrap.js`.

```sh
vsrocq-make-web-root /tmp/root          # from the switch
python3 serve.py . /tmp/root &          # page on :8000, root on :8001
chromium --headless=new "http://127.0.0.1:8000/index.html?debug"
```

`serve.py` prints the log of the page and stops when it posts a result
(`OK ...` or `FAIL ...`). Parameters of `index.html`: `root` (the URL of the
root, default `http://127.0.0.1:8001/`), `text` (the document), `debug`.
