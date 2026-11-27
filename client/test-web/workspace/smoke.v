Definition x := 1 + 1.
Lemma l : x = 2. Proof. reflexivity. Qed.
From Corelib Require Import ssreflect.
Lemma u (b : bool) : b = b. Proof. by case: b. Qed.
Lemma bad : 1 = 2. Proof. reflexivity. Qed.
