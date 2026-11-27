(* requires: mathcomp/algebra *)
(* expect: test_ring = *)
From mathcomp Require Import boot order algebra.
Import GRing.Theory.
Local Open Scope ring_scope.

Lemma test_ring (R : comRingType) (a b : R) : (a + b) ^+ 2 = a ^+ 2 + a * b *+ 2 + b ^+ 2.
Proof. by rewrite sqrrD. Qed.
Print test_ring.
