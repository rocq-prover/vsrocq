(* requires: elpi *)
(* expect: Hello wasm *)
(* expect: Goal: forall n : nat, n + 0 = n *)
From elpi Require Import elpi.

Elpi Command hello.
Elpi Accumulate lp:{{
  main [str S] :- coq.say "Hello" S.
}}.
Elpi hello "wasm".

Elpi Tactic show_goal.
Elpi Accumulate lp:{{
  solve (goal _ _ Ty _ _) _ :- coq.say "Goal:" {coq.term->string Ty}.
}}.

Goal forall n : nat, n + 0 = n.
Proof.
  elpi show_goal.
  intros n; induction n as [|n IHn]; simpl; [reflexivity | rewrite IHn; reflexivity].
Qed.
