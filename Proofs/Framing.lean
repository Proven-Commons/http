/-
  Acceptance and framing: `framing` decides `Spec.Accepts`.
-/

import Http.Framing
import Spec.Defs
import Proofs.Match
import Proofs.Fields

namespace Http.Proofs.Framing

open Http

theorem hostValue_eq : Grammar.hostValue = Spec.hostValue := rfl

theorem framing_iff (h : Head) (fr : Framing) : h.framing = some fr ↔ Spec.Accepts h fr := by
  sorry

theorem framing_te_cl (h : Head) (hte : Spec.named h "transfer-encoding" ≠ [])
    (hcl : Spec.named h "content-length" ≠ []) : h.framing = none := by
  sorry

theorem framing_two_cl (h : Head) (h2 : 2 ≤ (Spec.named h "content-length").length) :
    h.framing = none := by
  sorry

end Http.Proofs.Framing
