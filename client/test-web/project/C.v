From P Require Import A B.
Check double_double.
Lemma ok : double 3 = 6. Proof. reflexivity. Qed.
Lemma bad : double 3 = 7. Proof. reflexivity. Qed.
