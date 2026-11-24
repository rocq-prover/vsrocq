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
  unloadable  the .vo and .cma files that cannot be loaded with 31-bit
            integers (see check_int31), with the reason

wasm_of_ocaml represents OCaml integers as 31-bit i31ref values. A file
written by a native (63-bit) program that contains a larger integer, e.g.
max_int in a .vo file or a large literal in the bytecode of a plugin,
fails to load with "input_value: integer too large". Such files are
reported, and --strict makes them an error.

Usage: make-web-root.py [--prefix PREFIX] OUTDIR
"""
import argparse, json, os, re, shutil, struct, subprocess, sys

def run(*cmd):
    return subprocess.run(cmd, check=True, capture_output=True, text=True).stdout

# OCaml's Marshal format (runtime/caml/intext.h)
MAGIC_SMALL, MAGIC_BIG, MAGIC_COMPRESSED = 0x8495A6BE, 0x8495A6BF, 0x8495A6BD
INT31 = 1 << 30

def large_ints_in_marshal(buf, pos):
    """Scan the marshaled value starting at pos; return (end, n) where n is
    the number of integers that do not fit in 31 bits."""
    magic = struct.unpack_from(">I", buf, pos)[0]
    if magic == MAGIC_SMALL:
        pos += 20
    elif magic == MAGIC_BIG:
        pos += 32
    else:
        raise ValueError("compressed marshaled data" if magic == MAGIC_COMPRESSED
                         else "not marshaled data")
    todo, n = 1, 0  # values still to read
    while todo:
        todo -= 1
        c = buf[pos]; pos += 1
        if c >= 0x80:                          # small block
            todo += (c >> 4) & 0x7
        elif c >= 0x40:                        # small int
            pass
        elif c >= 0x20:                        # small string
            pos += c & 0x1F
        elif c in (0x02, 0x03):                # int32, int64
            w = 4 if c == 0x02 else 8
            v = int.from_bytes(buf[pos:pos + w], "big", signed=True); pos += w
            n += not (-INT31 <= v < INT31)
        elif c in (0x00, 0x04): pos += 1       # int8, shared8
        elif c in (0x01, 0x05): pos += 2       # int16, shared16
        elif c == 0x06: pos += 4               # shared32
        elif c == 0x14: pos += 8               # shared64
        elif c == 0x08:                        # block32
            todo += struct.unpack_from(">I", buf, pos)[0] >> 10; pos += 4
        elif c == 0x13:                        # block64
            todo += struct.unpack_from(">Q", buf, pos)[0] >> 10; pos += 8
        elif c in (0x09, 0x0A, 0x15):          # string8, string32, string64
            w = {0x09: 1, 0x0A: 4, 0x15: 8}[c]
            pos += w + int.from_bytes(buf[pos:pos + w], "big")
        elif c in (0x0B, 0x0C): pos += 8       # double
        elif c in (0x0D, 0x0E): pos += 1 + 8 * buf[pos]  # double array8
        elif c in (0x07, 0x0F):                # double array32
            pos += 4 + 8 * struct.unpack_from(">I", buf, pos)[0]
        elif c in (0x16, 0x17):                # double array64
            pos += 8 + 8 * struct.unpack_from(">Q", buf, pos)[0]
        elif c in (0x12, 0x18, 0x19):          # custom blocks
            e = buf.index(0, pos); ident = buf[pos:e]; pos = e + 1
            if c == 0x18:                      # custom_len
                pos += 4 + 8 + struct.unpack_from(">Q", buf, pos + 4)[0]
            elif ident == b"_j": pos += 8      # Int64
            elif ident == b"_i": pos += 4      # Int32
            elif ident == b"_n": pos += 1 + (4 if buf[pos] == 1 else 8)  # Nativeint
            else:
                raise ValueError(f"unknown custom block {ident!r}")
        else:
            raise ValueError(f"unknown code {c:#x}")
    return pos, n

def check_int31(path):
    """None if the marshaled data in the file (.vo segments, .cma
    descriptors and constants) only contains integers fitting in 31 bits,
    else the reason."""
    buf = open(path, "rb").read()
    n, pos = 0, 0
    magics = (MAGIC_SMALL.to_bytes(4, "big"), MAGIC_BIG.to_bytes(4, "big"))
    while True:
        starts = [i for i in (buf.find(m, pos) for m in magics) if i >= 0]
        if not starts:
            break
        start = min(starts)
        try:
            pos, k = large_ints_in_marshal(buf, start)
            n += k
        except (ValueError, IndexError, struct.error):
            pos = start + 4  # not a marshaled value after all
    return f"{n} integers do not fit in 31 bits" if n else None

def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--prefix", default=os.environ.get("OPAM_SWITCH_PREFIX"),
                    help="the prefix of the opam switch (default: $OPAM_SWITCH_PREFIX)")
    ap.add_argument("--dry-run", action="store_true", help="only print the sizes")
    ap.add_argument("--strict", action="store_true",
                    help="fail if a file cannot be loaded with 31-bit integers")
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
    # plugins can be subpackages (e.g. rocq-elpi.elpi, whose parent requires
    # nothing), so look at all the packages; the libraries of the language
    # server also require Rocq, but they are linked in the server
    for p in pkgs:
        if p.startswith(("rocq-runtime", "vsrocq-language-server")):
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

    # files that a program with 31-bit integers cannot load
    unloadable = {}
    for rel in sorted(files):
        if rel.endswith((".vo", ".cma")):
            reason = check_int31(os.path.join(prefix, rel))
            if reason:
                unloadable[rel] = reason
    for rel, reason in unloadable.items():
        print(f"warning: {rel} cannot be loaded with 31-bit integers: {reason}",
              file=sys.stderr)

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
        "unloadable": unloadable,
    }

    total = sum(files.values())
    pre = sum(files[f] for f in manifest["prefetch"])
    print(f"{len(files)} files, {total / 1e6:.1f} MB; prefetch {len(manifest['prefetch'])} files, "
          f"{pre / 1e6:.1f} MB")
    if unloadable:
        print(f"{len(unloadable)} files cannot be loaded with 31-bit integers", file=sys.stderr)
        if a.strict:
            sys.exit(1)
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
