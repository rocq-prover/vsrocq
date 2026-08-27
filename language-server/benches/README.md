# Benchmarks

## Running

From the `/language-server`:

```sh
dune exec benches/benches.exe
```

You can filter in benchmarks by passing a _regex_ pattern:

```sh
dune exec benches/benches.exe "raw_document/create"
```

## Writing

We use [`Bechamel`](https://github.com/mirage/bechamel) for benchmarking. In [`common.ml`](./common.ml) you can find some test case Rocq sources.
