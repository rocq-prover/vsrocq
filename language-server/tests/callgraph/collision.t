Identifier stamps restart in every compilation unit, so Api.entry and
Worker.entry, the first binding of their files, get the same unique name
(entry_<stamp>). Api.entry only calls Worker.safe, so it must not appear to
reach Unix.time. Api sorts before Worker so that, if the two nodes merge,
the merged node keeps Api's name and is reported as a root.

  $ ./static_callgraph.exe collision/.collision.objs/byte/collision__Api.cmt
  direct -> Collision.Worker.entry -> Unix.time
