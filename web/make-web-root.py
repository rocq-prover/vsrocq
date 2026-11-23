#!/usr/bin/env python3
"""Make a trimmed copy of an opam switch, to be served as static files
(e.g. GitHub Pages) to the web language server (lazyfs.js, worker.js).

It keeps what the wasm language server reads at run time:
- the .vo files of Rocq's coqlib (Corelib and user-contrib);
- findlib.conf, the META files and the bytecode (.cma, .cmo) of the
  findlib packages needed by Rocq plugins (the plugins of rocq-runtime and
  of the packages depending on it);
- the wasm language server (vsrocq-language-server-web) and rocq-web.

It writes manifest.json at the root of the output:
  prefix    the prefix of the switch: the files are mounted there, so that
            the absolute paths compiled in the programs keep working
  files     the files, relative to the prefix, with their size
  server    the server (relative path), worker and lazyfs: the JS files
  rocq      the programs of rocq-web (rocq c, rocq dep), runner: their JS glue
  args      the command line of the server
  prefetch  files to fetch before starting the server
  packages  the versions of the installed opam packages

Usage: make-web-root.py [--prefix PREFIX] OUTDIR
"""
import argparse, json, os, re, shutil, subprocess, sys

def run(*cmd):
    return subprocess.run(cmd, check=True, capture_output=True, text=True).stdout

def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--prefix", default=os.environ.get("OPAM_SWITCH_PREFIX"),
                    help="the prefix of the opam switch (default: $OPAM_SWITCH_PREFIX)")
    ap.add_argument("--dry-run", action="store_true", help="only print the sizes")
    ap.add_argument("out")
    a = ap.parse_args()
    if not a.prefix:
        sys.exit("no --prefix and no OPAM_SWITCH_PREFIX")
    prefix = os.path.realpath(a.prefix)
    lib = os.path.join(prefix, "lib")
    files = {}  # relative path -> size

    def add(path):
        path = os.path.realpath(path)
        rel = os.path.relpath(path, prefix)
        if rel.startswith(".."):
            sys.exit(f"{path} is not in {prefix}")
        files[rel] = os.path.getsize(path)

    def add_tree(d, keep):
        for root, _, names in os.walk(d):
            for n in names:
                if keep(n):
                    add(os.path.join(root, n))

    env = dict(os.environ, OCAMLFIND_CONF=os.path.join(lib, "findlib.conf"))

    # findlib
    add(os.path.join(lib, "findlib.conf"))
    if os.path.isdir(os.path.join(lib, "findlib.conf.d")):
        add_tree(os.path.join(lib, "findlib.conf.d"), lambda n: True)

    # Rocq plugins and their dependencies
    pkgs = [l.split()[0] for l in run("ocamlfind", "list").splitlines() if l.strip()]
    roots = [p for p in pkgs if p.startswith("rocq-runtime.plugins.")]
    for p in pkgs:
        if "." in p or p.startswith("rocq-runtime"):
            continue
        req = run("ocamlfind", "query", "-r", "-format", "%p", p).split()
        if "rocq-runtime.kernel" in req or "rocq-runtime.vernac" in req:
            roots.append(p)
    closure = set(run("ocamlfind", "query", "-r", "-format", "%p", *roots).split())
    # the packages linked in the programs: only their META is needed
    linked = set(run("ocamlfind", "query", "-r", "-format", "%p", "rocq-runtime.toplevel",
                     "rocq-runtime.tactics", *[p for p in ("vsrocq-language-server.server",)
                                               if p in pkgs]).split())
    dirs = set()
    for p in closure:
        d = run("ocamlfind", "query", "-format", "%d", p).strip()
        if p not in linked:
            dirs.add(d)
        top =run("ocamlfind", "query", "-format", "%d", p.split(".")[0]).strip()
        for meta in (os.path.join(top, "META"), os.path.join(lib, p.split(".")[0], "META")):
            if os.path.exists(meta):
                add(meta)
                break
    for d in dirs:
        for n in os.listdir(d):
            if n.endswith((".cma", ".cmo")):
                add(os.path.join(d, n))

    # Rocq
    coqlib = run("rocq", "c", "-where").strip()
    add_tree(coqlib, lambda n: n.endswith((".vo", ".vos")))
    rev = os.path.join(lib, "rocq-runtime", "revision")
    if os.path.exists(rev):
        add(rev)

    # the programs
    for pkg in ("vsrocq-language-server-web", "rocq-web"):
        d = os.path.join(lib, pkg)
        if os.path.isdir(d):
            add_tree(d, lambda n: n.endswith((".js", ".wasm")))

    # prefetch: Init, the plugins it loads, the META files
    init = os.path.join(coqlib, "theories", "Init")
    rel_init = os.path.relpath(os.path.realpath(init), prefix)
    prefetch = [f for f in files if f.startswith(rel_init + "/") or f.endswith("META")
                or f.endswith("findlib.conf")]
    for v in os.listdir(init):
        if v.endswith(".v"):
            for m in re.findall(r'Declare ML Module "([^"]+)"', open(os.path.join(init, v)).read()):
                d = run("ocamlfind", "query", "-format", "%d", m).strip()
                prefetch += [f for f in files if os.path.dirname(os.path.join(prefix, f)) == d
                             and f.endswith(".cma")]

    srv = "lib/vsrocq-language-server-web"
    packages = dict(l.split()[:2] for l in run(
        "opam", "list", "--installed", "--short", "--columns=name,version").splitlines()
        if l.strip())
    manifest = {
        "version": 1,
        "prefix": prefix,
        "server": srv + "/vsrocq_web.bc.wasm.js",
        "worker": srv + "/worker.js",
        "lazyfs": srv + "/lazyfs.js",
        "runner": srv + "/runner.js",
        "rocq": {"c": "lib/rocq-web/rocq_c.bc.wasm.js",
                 "dep": "lib/rocq-web/rocq_dep.bc.wasm.js"},
        "args": ["-coqlib", coqlib, "-bytecode-compiler", "no"],
        "prefetch": sorted(set(prefetch)),
        "packages": packages,
        "files": dict(sorted(files.items())),
    }

    total = sum(files.values())
    pre = sum(files[f] for f in manifest["prefetch"])
    print(f"{len(files)} files, {total / 1e6:.1f} MB; prefetch {len(manifest['prefetch'])} files, "
          f"{pre / 1e6:.1f} MB")
    if a.dry_run:
        return
    os.makedirs(a.out, exist_ok=True)
    for rel in files:
        dst = os.path.join(a.out, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(os.path.join(prefix, rel), dst)
    with open(os.path.join(a.out, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1)
    # GitHub Pages: do not process the files with Jekyll
    open(os.path.join(a.out, ".nojekyll"), "w").close()

if __name__ == "__main__":
    main()
