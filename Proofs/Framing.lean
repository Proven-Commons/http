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

private theorem decimal_eq : decimal = Spec.decimal := rfl

private theorem digits_iff (v : List UInt8) :
    (!v.isEmpty && v.all isDigit) = true ↔ Spec.Matches Spec.contentLength v := by
  rw [Fields.contentLength_iff]
  cases v <;> simp

theorem hostValue_eq : Grammar.hostValue = Spec.hostValue := rfl

theorem chunkedList_eq : Grammar.chunkedList = Spec.listOne (Re.litCI "chunked") := rfl

theorem authorityForm_eq : Grammar.authorityForm = Spec.authorityForm := rfl

private theorem colon_eq : Re.litCI ":" = .range 0x3A 0x3A := rfl

/-- An authority-form target is a host, a colon and a port. -/
private theorem authorityForm_iff (t : List UInt8) :
    Spec.Matches Spec.authorityForm t ↔
      ∃ host port, t = host ++ [0x3A] ++ port ∧ Spec.Matches Spec.uriHost host ∧
        Spec.Matches Spec.port port := by
  simp only [Spec.authorityForm, Re.seq, colon_eq, Match.matches_cat_iff, Match.matches_range_iff]
  constructor
  · rintro ⟨host, _, rfl, hh, _, port, rfl, ⟨c, rfl, h1, h2⟩, hp⟩
    have hc : c = 0x3A := UInt8.le_antisymm h2 h1
    subst hc
    exact ⟨host, port, by simp, hh, hp⟩
  · rintro ⟨host, port, rfl, hh, hp⟩
    exact ⟨host, [0x3A] ++ port, by simp, hh, [0x3A], port, rfl, ⟨0x3A, rfl, by decide, by decide⟩, hp⟩

/-- In a target `host ":" port`, `portOf` finds the port, since a colon
    is not a digit. -/
private theorem portOf_eq {host port : List UInt8} (hp : ∀ c ∈ port, isDigit c = true) :
    portOf (host ++ [0x3A] ++ port) = port := by
  unfold portOf
  rw [List.reverse_append, List.reverse_append,
    List.takeWhile_append_of_pos (fun c hc => hp c (List.mem_reverse.1 hc))]
  simp [isDigit]

theorem connectOK_iff (h : Head) : h.connectOK = true ↔ Spec.ConnectOK h := by
  have ec : Spec.ascii "CONNECT" = connectName := rfl
  unfold Head.connectOK Spec.ConnectOK
  rw [ec]
  generalize h.method = m
  generalize h.target = t
  simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, Bool.and_eq_true, decide_eq_true_eq,
    Match.isMatch_iff, authorityForm_eq, authorityForm_iff]
  constructor
  · rintro (hm | ⟨⟨⟨host, port, rfl, hh, hp⟩, h1⟩, h2⟩) hc
    · exact absurd hc hm
    · rw [portOf_eq ((Fields.port_iff port).1 hp)] at h1 h2
      exact ⟨host, port, rfl, hh, hp, h1, h2⟩
  · intro hc
    by_cases hm : m = connectName
    · obtain ⟨host, port, rfl, hh, hp, h1, h2⟩ := hc hm
      rw [portOf_eq ((Fields.port_iff port).1 hp), decimal_eq]
      exact .inr ⟨⟨⟨host, port, rfl, hh, hp⟩, h1⟩, h2⟩
    · exact .inl hm

private theorem ite_none_iff {α : Type} {c : Bool} {x : Option α} {y : α} :
    (if c = true then none else x) = some y ↔ c = false ∧ x = some y := by
  cases c <;> simp

private theorem ite_some_iff {α : Type} {c : Bool} {x y : α} :
    (if c = true then some x else none) = some y ↔ c = true ∧ x = y := by
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

private theorem connect_cond_iff (h : Head) : (!h.connectOK) = false ↔ Spec.ConnectOK h := by
  rw [Bool.not_eq_false', connectOK_iff]

theorem framing_iff (h : Head) (fr : Framing) : h.framing = some fr ↔ Spec.Accepts h fr := by
  have eh : Spec.named h "host" = h.fields.filter (·.isNamed hostName) := named_eq h "host"
  have et : Spec.named h "transfer-encoding" = h.fields.filter (·.isNamed transferEncodingName) :=
    named_eq h "transfer-encoding"
  have ec : Spec.named h "content-length" = h.fields.filter (·.isNamed contentLengthName) :=
    named_eq h "content-length"
  unfold Head.framing Spec.Accepts Spec.HostOK
  rw [ite_none_iff, cond_iff, ite_none_iff, connect_cond_iff, and_assoc, eh]
  apply and_congr_right
  intro _
  apply and_congr_right
  intro _
  apply and_congr_right
  intro _
  cases fr with
  | chunked =>
    simp only [Spec.FramedAs]
    rw [et, ec]
    generalize h.fields.filter (·.isNamed transferEncodingName) = T
    generalize h.fields.filter (·.isNamed contentLengthName) = C
    rcases T with _ | ⟨t, T⟩ <;> rcases C with _ | ⟨c, _ | ⟨c2, C⟩⟩ <;>
      (try simp only [ite_some_iff]) <;> simp [Match.isMatch_iff, chunkedList_eq, Spec.combined]
  | length n =>
    simp only [Spec.FramedAs]
    rw [et, ec]
    generalize h.fields.filter (·.isNamed transferEncodingName) = T
    generalize h.fields.filter (·.isNamed contentLengthName) = C
    rcases T with _ | ⟨t, T⟩ <;> rcases C with _ | ⟨c, _ | ⟨c2, C⟩⟩ <;>
      simp [← digits_iff, decimal_eq]
    all_goals (intros; exact eq_comm)

theorem framing_te_cl (h : Head) (hte : Spec.named h "transfer-encoding" ≠ [])
    (hcl : Spec.named h "content-length" ≠ []) : h.framing = none := by
  cases hf : h.framing with
  | none => rfl
  | some fr =>
    have ⟨_, _, _, hfr⟩ := (framing_iff h fr).1 hf
    cases fr with
    | chunked => exact absurd hfr.2.1 hcl
    | length n => exact absurd hfr.1 hte

theorem framing_two_cl (h : Head) (h2 : 2 ≤ (Spec.named h "content-length").length) :
    h.framing = none := by
  cases hf : h.framing with
  | none => rfl
  | some fr =>
    have ⟨_, _, _, hfr⟩ := (framing_iff h fr).1 hf
    cases fr with
    | chunked => rw [hfr.2.1] at h2; simp at h2
    | length n =>
      rcases hfr.2 with ⟨hc, _⟩ | ⟨f, hc, _⟩ <;> rw [hc] at h2 <;> simp at h2

end Http.Proofs.Framing
