/-
  The matcher: `isMatch` decides `Spec.Matches`, through the
  derivative, the simplifying constructors and `nullable`. And a test
  that bounds the octets any string a rule matches can hold.
-/

import Http.Match
import Spec.Abnf

namespace Http.Proofs.Match

open Http Http.Re

theorem isMatch_iff (r : Re) (s : List UInt8) : r.isMatch s = true ↔ Spec.Matches r s := by
  sorry

/-- Every octet in every range of the rule passes `p`. -/
def allBytes (p : UInt8 → Bool) : Re → Bool
  | .empty => true
  | .eps => true
  | .range lo hi => (List.range 256).all fun n => !(lo ≤ n.toUInt8 && n.toUInt8 ≤ hi) || p n.toUInt8
  | .cat a b => allBytes p a && allBytes p b
  | .alt a b => allBytes p a && allBytes p b
  | .star a => allBytes p a

theorem matches_bytes (p : UInt8 → Bool) (r : Re) (h : allBytes p r = true) {s : List UInt8}
    (hm : Spec.Matches r s) : ∀ c ∈ s, p c = true := by
  sorry

end Http.Proofs.Match
