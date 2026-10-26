/-
  Acceptance and framing: `framing` decides `Spec.Accepts`.
-/

import Http.Framing
import Spec.Defs
import Proofs.Match
import Proofs.Fields

namespace Http.Proofs.Framing

open Http

private theorem lower_eq : lower = Spec.lower := by
  funext c
  unfold lower Spec.lower
  by_cases h1 : (0x41 : UInt8) ≤ c <;> by_cases h2 : c ≤ (0x5A : UInt8) <;> simp [h1, h2]

private theorem isNamed_iff (f : Field) (n : List UInt8) : f.isNamed n = true ↔ f.name.map Spec.lower = n := by
  unfold Field.isNamed; rw [lower_eq]; simp

private theorem named_eq (h : Head) (s : String) :
    Spec.named h s = h.fields.filter (·.isNamed (Spec.ascii s)) := by
  unfold Spec.named
  apply List.filter_congr
  intro f _
  rw [Bool.eq_iff_iff, isNamed_iff]
  simp

private theorem digits_iff (v : List UInt8) :
    (!v.isEmpty && v.all isDigit) = true ↔ Spec.Matches Spec.contentLength v := by
  rw [Fields.contentLength_iff]
  cases v <;> simp

theorem hostValue_eq : Grammar.hostValue = Spec.hostValue := rfl

private theorem ite_none_iff {α : Type} {c : Bool} {x : Option α} {y : α} :
    (if c = true then none else x) = some y ↔ c = false ∧ x = some y := by
  cases c <;> simp

private theorem cond_iff (h : Head) (H : List Field) :
    (h.major != 1 || decide (H.length > 1) || (decide (1 ≤ h.minor) && H.length != 1) ||
      !H.all (fun f => Grammar.hostValue.isMatch f.value)) = false ↔
    h.major = 1 ∧ H.length ≤ 1 ∧ (1 ≤ h.minor → H.length = 1) ∧
      ∀ f ∈ H, Spec.Matches Spec.hostValue f.value := by
  simp only [Bool.or_eq_false_iff, bne_eq_false_iff_eq, decide_eq_false_iff_not, Bool.and_eq_false_imp,
    decide_eq_true_eq, Bool.not_eq_false', List.all_eq_true, Match.isMatch_iff, hostValue_eq]
  constructor
  · rintro ⟨⟨⟨h1, h2⟩, h3⟩, h4⟩
    exact ⟨h1, by omega, h3, h4⟩
  · rintro ⟨h1, h2, h3, h4⟩
    exact ⟨⟨⟨h1, by omega⟩, h3⟩, h4⟩

theorem framing_iff (h : Head) (fr : Framing) : h.framing = some fr ↔ Spec.Accepts h fr := by
  have eh : Spec.named h "host" = h.fields.filter (·.isNamed hostName) := named_eq h "host"
  have et : Spec.named h "transfer-encoding" = h.fields.filter (·.isNamed transferEncodingName) :=
    named_eq h "transfer-encoding"
  have ec : Spec.named h "content-length" = h.fields.filter (·.isNamed contentLengthName) :=
    named_eq h "content-length"
  have ech : Spec.ascii "chunked" = chunkedName := rfl
  unfold Head.framing Spec.Accepts Spec.HostOK
  cases fr with
  | chunked =>
    simp only [Spec.FramedAs]
    rw [eh, et, ec, ech]
    generalize h.fields.filter (·.isNamed hostName) = H
    generalize h.fields.filter (·.isNamed transferEncodingName) = T
    generalize h.fields.filter (·.isNamed contentLengthName) = C
    rw [ite_none_iff, cond_iff, and_assoc]
    apply and_congr_right
    intro _
    apply and_congr_right
    intro _
    rcases T with _ | ⟨t, _ | ⟨t2, T⟩⟩ <;> rcases C with _ | ⟨c, _ | ⟨c2, C⟩⟩ <;>
      simp [lower_eq]
  | length n =>
    simp only [Spec.FramedAs]
    rw [eh, et, ec]
    generalize h.fields.filter (·.isNamed hostName) = H
    generalize h.fields.filter (·.isNamed transferEncodingName) = T
    generalize h.fields.filter (·.isNamed contentLengthName) = C
    rw [ite_none_iff, cond_iff, and_assoc]
    apply and_congr_right
    intro _
    apply and_congr_right
    intro _
    rcases T with _ | ⟨t, _ | ⟨t2, T⟩⟩ <;> rcases C with _ | ⟨c, _ | ⟨c2, C⟩⟩ <;>
      simp [← digits_iff, decimal, Spec.decimal]
    all_goals (intros; exact eq_comm)

theorem framing_te_cl (h : Head) (hte : Spec.named h "transfer-encoding" ≠ [])
    (hcl : Spec.named h "content-length" ≠ []) : h.framing = none := by
  cases hf : h.framing with
  | none => rfl
  | some fr =>
    have ⟨_, _, hfr⟩ := (framing_iff h fr).1 hf
    cases fr with
    | chunked => exact absurd hfr.2.1 hcl
    | length n => exact absurd hfr.1 hte

theorem framing_two_cl (h : Head) (h2 : 2 ≤ (Spec.named h "content-length").length) :
    h.framing = none := by
  cases hf : h.framing with
  | none => rfl
  | some fr =>
    have ⟨_, _, hfr⟩ := (framing_iff h fr).1 hf
    cases fr with
    | chunked => rw [hfr.2.1] at h2; simp at h2
    | length n =>
      rcases hfr.2 with ⟨hc, _⟩ | ⟨f, hc, _⟩ <;> rw [hc] at h2 <;> simp at h2

end Http.Proofs.Framing
