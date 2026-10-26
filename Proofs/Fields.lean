/-
  Tokens, field values, optional whitespace, and the field lines.
-/

import Http.Head
import Spec.Defs

namespace Http.Proofs.Fields

open Http

theorem isToken_iff (s : List UInt8) : isToken s = true ↔ Spec.Matches Spec.token s := by
  sorry

theorem isFieldValue_iff (v : List UInt8) :
    isFieldValue v = true ↔ Spec.Matches Spec.fieldValue v := by
  sorry

theorem OWS_iff (w : List UInt8) : Spec.Matches Spec.OWS w ↔ ∀ c ∈ w, isWs c = true := by
  sorry

theorem contentLength_iff (v : List UInt8) :
    Spec.Matches Spec.contentLength v ↔ v ≠ [] ∧ ∀ c ∈ v, isDigit c = true := by
  sorry

theorem parseField_iff (line : List UInt8) (f : Field) :
    parseField line = some f ↔ Spec.FieldValid f ∧ Spec.FieldLineText f line := by
  sorry

theorem parseFields_iff (fuel : Nat) (bs : List UInt8) (fs : List Field) (r : List UInt8)
    (hfuel : bs.length < fuel) :
    parseFields fuel bs = some (fs, r) ↔
      (∀ f ∈ fs, Spec.FieldValid f) ∧ ∃ t, Spec.FieldsText fs t ∧ bs = t ++ r := by
  sorry

end Http.Proofs.Fields
