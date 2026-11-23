From P Require Import A.
From Corelib Require Import ssreflect.
Lemma double_double n : double (double n) = n + n + (n + n).
Proof. by []. Qed.
