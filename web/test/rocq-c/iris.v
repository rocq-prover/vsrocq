(* requires: iris *)
(* expect: test_sep = *)
From iris.proofmode Require Import proofmode.

Lemma test_sep {PROP : bi} (P Q : PROP) : P ∗ Q ⊢ Q ∗ P.
Proof. iIntros "[HP HQ]". iFrame. Qed.
Print test_sep.
