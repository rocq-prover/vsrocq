(* requires: HB *)
(* expect: Monoid.type *)
From HB Require Import structures.

HB.mixin Record IsMonoid T := {
  op : T -> T -> T;
  unit : T;
  opA : forall x y z, op x (op y z) = op (op x y) z;
}.
HB.structure Definition Monoid := { T of IsMonoid T }.

Lemma addA (x y z : nat) : x + (y + z) = (x + y) + z.
Proof. induction x as [|x IHx]; simpl; [reflexivity | rewrite IHx; reflexivity]. Qed.

HB.instance Definition _ := IsMonoid.Build nat Nat.add 0 addA.

Check Monoid.type.
Lemma test (x : nat) : op x unit = x + 0.
Proof. reflexivity. Qed.
