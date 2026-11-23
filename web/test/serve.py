#!/usr/bin/env python3
"""Test servers: the page on :8000 (cross-origin isolated, like vscode.dev
with ?vscode-coi), the opam root on :8001 (only CORS, like GitHub Pages).
POST /result on :8000 prints the body and stops."""
import http.server, sys, threading, functools, os
page_dir, root_dir = sys.argv[1], sys.argv[2]
done = threading.Event()
class Page(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()
    def do_POST(self):
        n = int(self.headers["Content-Length"]); body = self.rfile.read(n).decode()
        print(body, flush=True)
        self.send_response(200); self.end_headers()
        if self.path == "/result": done.set()
    def log_message(self, *a): pass
class Root(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        super().end_headers()
    def log_message(self, fmt, *a):
        if os.environ.get("LOG"): sys.stderr.write("root: " + fmt % a + "\n")
for port, h, d in ((8000, Page, page_dir), (8001, Root, root_dir)):
    s = http.server.ThreadingHTTPServer(("127.0.0.1", port), functools.partial(h, directory=d))
    threading.Thread(target=s.serve_forever, daemon=True).start()
done.wait(float(os.environ.get("TIMEOUT", "300")))
