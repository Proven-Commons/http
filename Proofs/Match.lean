/-
  The matcher: `isMatch` decides `Spec.Matches`, through the
  derivative, the simplifying constructors and `nullable`. And a test
  that bounds the octets any string a rule matches can hold.
-/

import Http.Match
import Spec.Abnf

namespace Http.Proofs.Match

open Http Http.Re

theorem matches_empty_iff (s : List UInt8) : Spec.Matches .empty s ↔ False :=
  ⟨fun h => (by cases h), False.elim⟩

theorem matches_eps_iff (s : List UInt8) : Spec.Matches .eps s ↔ s = [] :=
  ⟨fun h => by cases h; rfl, fun h => h ▸ .eps⟩

theorem matches_range_iff (lo hi : UInt8) (s : List UInt8) :
    Spec.Matches (.range lo hi) s ↔ ∃ c, s = [c] ∧ lo ≤ c ∧ c ≤ hi := by
  constructor
  · intro h; cases h with
    | range h1 h2 => exact ⟨_, rfl, h1, h2⟩
  · rintro ⟨c, rfl, h1, h2⟩; exact .range h1 h2

theorem matches_cat_iff (a b : Re) (s : List UInt8) :
    Spec.Matches (.cat a b) s ↔ ∃ s1 s2, s = s1 ++ s2 ∧ Spec.Matches a s1 ∧ Spec.Matches b s2 := by
  constructor
  · intro h; cases h with
    | cat h1 h2 => exact ⟨_, _, rfl, h1, h2⟩
  · rintro ⟨s1, s2, rfl, h1, h2⟩; exact .cat h1 h2

theorem matches_alt_iff (a b : Re) (s : List UInt8) :
    Spec.Matches (.alt a b) s ↔ Spec.Matches a s ∨ Spec.Matches b s := by
  constructor
  · intro h; cases h with
    | altL h => exact Or.inl h
    | altR h => exact Or.inr h
  · rintro (h | h)
    · exact .altL h
    · exact .altR h

theorem matches_star_inv {a : Re} {s : List UInt8} (h : Spec.Matches (.star a) s) :
    s = [] ∨ ∃ s1 s2, s = s1 ++ s2 ∧ s1 ≠ [] ∧ Spec.Matches a s1 ∧ Spec.Matches (.star a) s2 := by
  generalize hr : Re.star a = r at h
  induction h with
  | eps => cases hr
  | range _ _ => cases hr
  | cat _ _ => cases hr
  | altL _ => cases hr
  | altR _ => cases hr
  | starNil => exact Or.inl rfl
  | @starCons a' s t h1 h2 _ ih2 =>
    cases hr
    by_cases hs : s = []
    · subst hs
      exact ih2 rfl
    · exact Or.inr ⟨s, t, rfl, hs, h1, h2⟩

theorem nullable_iff (r : Re) : r.nullable = true ↔ Spec.Matches r [] := by
  induction r with
  | empty => simp [nullable, matches_empty_iff]
  | eps => simp [nullable, matches_eps_iff]
  | range lo hi => simp [nullable, matches_range_iff]
  | cat a b iha ihb =>
    simp only [nullable, Bool.and_eq_true, iha, ihb, matches_cat_iff]
    constructor
    · rintro ⟨h1, h2⟩; exact ⟨[], [], rfl, h1, h2⟩
    · rintro ⟨s1, s2, h, h1, h2⟩
      have h' := h.symm
      rw [List.append_eq_nil_iff] at h'
      obtain ⟨rfl, rfl⟩ := h'
      exact ⟨h1, h2⟩
  | alt a b iha ihb =>
    simp only [nullable, Bool.or_eq_true, iha, ihb, matches_alt_iff]
  | star a => simp only [nullable, true_iff]; exact .starNil

theorem mkCat_iff (a b : Re) (s : List UInt8) :
    Spec.Matches (mkCat a b) s ↔ Spec.Matches (.cat a b) s := by
  have e1 : ∀ b s, Spec.Matches (.cat .empty b) s ↔ False := by
    intro b s; simp [matches_cat_iff, matches_empty_iff]
  have e2 : ∀ a s, Spec.Matches (.cat a .empty) s ↔ False := by
    intro a s; simp [matches_cat_iff, matches_empty_iff]
  have e3 : ∀ b s, Spec.Matches (.cat .eps b) s ↔ Spec.Matches b s := by
    intro b s
    rw [matches_cat_iff]
    constructor
    · rintro ⟨s1, s2, rfl, h1, h2⟩
      rw [matches_eps_iff] at h1
      subst h1
      exact h2
    · intro h
      exact ⟨[], s, rfl, .eps, h⟩
  have e4 : ∀ a s, Spec.Matches (.cat a .eps) s ↔ Spec.Matches a s := by
    intro a s
    rw [matches_cat_iff]
    constructor
    · rintro ⟨s1, s2, rfl, h1, h2⟩
      rw [matches_eps_iff] at h2
      subst h2
      simpa using h1
    · intro h
      exact ⟨s, [], by simp, h, .eps⟩
  cases a <;> cases b <;> simp only [mkCat, e1, e2, e3, e4, matches_empty_iff]

theorem mkAlt_iff (a b : Re) (s : List UInt8) :
    Spec.Matches (mkAlt a b) s ↔ Spec.Matches (.alt a b) s := by
  unfold mkAlt
  split
  · simp [matches_alt_iff, matches_empty_iff]
  · simp [matches_alt_iff, matches_empty_iff]
  · split
    · rename_i h; subst h; simp [matches_alt_iff]
    · split
      · split
        · rename_i h; subst h; simp only [matches_alt_iff, or_assoc, or_self]
        · exact Iff.rfl
      · exact Iff.rfl

theorem deriv_iff (c : UInt8) (r : Re) (s : List UInt8) :
    Spec.Matches (deriv c r) s ↔ Spec.Matches r (c :: s) := by
  induction r generalizing s with
  | empty => simp [deriv, matches_empty_iff]
  | eps => simp [deriv, matches_empty_iff, matches_eps_iff]
  | range lo hi =>
    simp only [deriv, matches_range_iff]
    split
    · rename_i h
      rw [matches_eps_iff]
      constructor
      · rintro rfl; exact ⟨c, rfl, h.1, h.2⟩
      · rintro ⟨d, hd, _⟩
        cases hd
        rfl
    · rename_i h
      simp only [matches_empty_iff, false_iff]
      rintro ⟨d, hd, h1, h2⟩
      cases hd
      exact h ⟨h1, h2⟩
  | cat a b iha ihb =>
    simp only [deriv]
    split
    · rename_i hn
      rw [mkAlt_iff, matches_alt_iff, mkCat_iff, matches_cat_iff, ihb, matches_cat_iff]
      constructor
      · rintro (⟨s1, s2, rfl, h1, h2⟩ | h)
        · exact ⟨c :: s1, s2, rfl, (iha s1).1 h1, h2⟩
        · exact ⟨[], c :: s, rfl, (nullable_iff a).1 hn, h⟩
      · rintro ⟨s1, s2, hs, h1, h2⟩
        cases s1 with
        | nil => exact Or.inr (by simpa using hs ▸ h2)
        | cons d s1 =>
          simp only [List.cons_append, List.cons.injEq] at hs
          obtain ⟨rfl, rfl⟩ := hs
          exact Or.inl ⟨s1, s2, rfl, (iha s1).2 h1, h2⟩
    · rename_i hn
      rw [mkCat_iff, matches_cat_iff, matches_cat_iff]
      constructor
      · rintro ⟨s1, s2, rfl, h1, h2⟩
        exact ⟨c :: s1, s2, rfl, (iha s1).1 h1, h2⟩
      · rintro ⟨s1, s2, hs, h1, h2⟩
        cases s1 with
        | nil => exact absurd ((nullable_iff a).2 h1) hn
        | cons d s1 =>
          simp only [List.cons_append, List.cons.injEq] at hs
          obtain ⟨rfl, rfl⟩ := hs
          exact ⟨s1, s2, rfl, (iha s1).2 h1, h2⟩
  | alt a b iha ihb =>
    simp only [deriv]
    rw [mkAlt_iff, matches_alt_iff, matches_alt_iff, iha, ihb]
  | star a iha =>
    simp only [deriv]
    rw [mkCat_iff, matches_cat_iff]
    constructor
    · rintro ⟨s1, s2, rfl, h1, h2⟩
      exact .starCons ((iha s1).1 h1) h2
    · intro h
      rcases matches_star_inv h with h | ⟨s1, s2, hs, hne, h1, h2⟩
      · cases h
      · cases s1 with
        | nil => exact absurd rfl hne
        | cons d s1 =>
          simp only [List.cons_append, List.cons.injEq] at hs
          obtain ⟨rfl, rfl⟩ := hs
          exact ⟨s1, s2, rfl, (iha s1).2 h1, h2⟩

theorem isMatch_iff (r : Re) (s : List UInt8) : r.isMatch s = true ↔ Spec.Matches r s := by
  induction s generalizing r with
  | nil => simp only [isMatch]; exact nullable_iff r
  | cons c cs ih => simp only [isMatch]; rw [ih, deriv_iff]

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
  induction hm with
  | eps => intro c hc; cases hc
  | @range lo hi c h1 h2 =>
    intro d hd
    simp only [List.mem_singleton] at hd
    subst hd
    simp only [allBytes, List.all_eq_true, List.mem_range] at h
    have := h d.toNat (UInt8.toNat_lt d)
    simp only [UInt8.ofNat_toNat] at this
    have h1' : decide (lo ≤ d) = true := decide_eq_true h1
    have h2' : decide (d ≤ hi) = true := decide_eq_true h2
    simpa [h1', h2'] using this
  | cat _ _ iha ihb =>
    simp only [allBytes, Bool.and_eq_true] at h
    intro c hc
    rcases List.mem_append.1 hc with hc | hc
    · exact iha h.1 c hc
    · exact ihb h.2 c hc
  | altL _ ih =>
    simp only [allBytes, Bool.and_eq_true] at h
    exact ih h.1
  | altR _ ih =>
    simp only [allBytes, Bool.and_eq_true] at h
    exact ih h.2
  | starNil => intro c hc; cases hc
  | starCons _ _ iha ihb =>
    intro c hc
    rcases List.mem_append.1 hc with hc | hc
    · exact iha h c hc
    · exact ihb h c hc

end Http.Proofs.Match
