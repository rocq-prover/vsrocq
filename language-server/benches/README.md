# Benchmarks

## Running

From `/language-server`:

```sh
dune exec benches/benches.exe
```

Running all benches takes a few **minutes**.
You can filter-in benchmarks by passing a _regex_ pattern:

```sh
dune exec benches/benches.exe "raw_document/create"
```

## Writing

We use [`Bechamel`](https://github.com/mirage/bechamel) for benchmarking. In [`common.ml`](./common.ml) you can find some test case Rocq sources.
