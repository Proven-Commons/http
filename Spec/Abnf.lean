/-
  What a rule of the grammar notation in `Http/Abnf.lean` matches. Part
  of the approved specification, with `Spec.lean`.
-/

import Http.Abnf

open Http

/-- The strings each rule matches, by the usual meaning of each form of
    regular expression. -/
inductive Spec.Matches : Re → List UInt8 → Prop where
  | eps : Spec.Matches .eps []
  | range {lo hi c : UInt8} : lo ≤ c → c ≤ hi → Spec.Matches (.range lo hi) [c]
  | cat {a b : Re} {s t : List UInt8} :
      Spec.Matches a s → Spec.Matches b t → Spec.Matches (.cat a b) (s ++ t)
  | altL {a b : Re} {s : List UInt8} : Spec.Matches a s → Spec.Matches (.alt a b) s
  | altR {a b : Re} {s : List UInt8} : Spec.Matches b s → Spec.Matches (.alt a b) s
  | starNil {a : Re} : Spec.Matches (.star a) []
  | starCons {a : Re} {s t : List UInt8} :
      Spec.Matches a s → Spec.Matches (.star a) t → Spec.Matches (.star a) (s ++ t)
