/-
  Lines, empty lines, the three parts of the request line, and the
  version.
-/

import Http.Head
import Spec.Defs

namespace Http.Proofs.Lines

open Http

theorem takeLine_iff (bs l r : List UInt8) :
    takeLine bs = some (l, r) ↔ (0x0D ∉ l ∧ 0x0A ∉ l) ∧ bs = l ++ Spec.crlf ++ r := by
  induction bs generalizing l with
  | nil =>
    simp [takeLine, Spec.crlf]
  | cons c rest ih =>
    by_cases hc : c = 0x0D
    · subst hc
      cases l with
      | nil =>
        cases rest with
        | nil => simp [takeLine, Spec.crlf]
        | cons d rest' =>
          by_cases hd : d = 0x0A
          · subst hd; simp [takeLine, Spec.crlf]
          · simp [takeLine, Spec.crlf, hd]
      | cons x l' =>
        constructor
        · intro h
          cases rest with
          | nil => simp [takeLine] at h
          | cons d rest' =>
            by_cases hd : d = 0x0A
            · subst hd; simp [takeLine] at h
            · simp [takeLine, hd] at h
        · rintro ⟨⟨h1, _⟩, h2⟩
          simp at h2
          exact absurd (h2.1 ▸ List.mem_cons_self) h1
    · by_cases hc' : c = 0x0A
      · subst hc'
        constructor
        · intro h; simp [takeLine] at h
        · rintro ⟨⟨h1, h1'⟩, h2⟩
          cases l with
          | nil => simp [Spec.crlf] at h2
          | cons x l' =>
            simp at h2
            exact absurd (h2.1 ▸ List.mem_cons_self) h1'
      · have e : takeLine (c :: rest) = (takeLine rest).map fun p => (c :: p.1, p.2) := by
          simp [takeLine, hc, hc']
        rw [e]
        cases l with
        | nil =>
          simp [Spec.crlf, hc]
        | cons x l' =>
          constructor
          · intro h
            simp only [Option.map_eq_some_iff] at h
            obtain ⟨⟨p1, p2⟩, hp, he⟩ := h
            simp at he
            obtain ⟨⟨rfl, rfl⟩, rfl⟩ := he
            have := (ih p1).mp hp
            have hc1 : ¬ (13 : UInt8) = c := fun h => hc h.symm
            have hc2 : ¬ (10 : UInt8) = c := fun h => hc' h.symm
            simp_all
          · rintro ⟨⟨h1, h1'⟩, h2⟩
            simp at h2
            obtain ⟨rfl, h3⟩ := h2
            have : takeLine rest = some (l', r) :=
              (ih l').mpr ⟨⟨by simp_all, by simp_all⟩, by simp [h3]⟩
            simp [this]

private theorem skipEmpty_crlf_cons (bs : List UInt8) :
    skipEmpty (0x0D :: 0x0A :: bs) = skipEmpty bs := by
  rw [skipEmpty.eq_1]; simp

theorem skipEmpty_crlf (k : Nat) (bs : List UInt8) :
    skipEmpty ((List.replicate k Spec.crlf).flatten ++ bs) = skipEmpty bs := by
  induction k with
  | zero => simp
  | succ k ih =>
    rw [List.replicate_succ, List.flatten_cons, List.append_assoc]
    rw [← ih]
    exact skipEmpty_crlf_cons _

theorem skipEmpty_eq (bs : List UInt8) :
    ∃ k, bs = (List.replicate k Spec.crlf).flatten ++ skipEmpty bs := by
  fun_induction skipEmpty with
  | case1 c d rest h ih =>
    obtain ⟨k, hk⟩ := ih
    refine ⟨k + 1, ?_⟩
    simp at h
    obtain ⟨rfl, rfl⟩ := h
    rw [List.replicate_succ, List.flatten_cons, List.append_assoc, ← hk]
    rfl
  | case2 c d rest h => exact ⟨0, by simp⟩
  | case3 bs h => exact ⟨0, by simp⟩

theorem skipEmpty_cons (c : UInt8) (bs : List UInt8) (hc : c ≠ 0x0D) :
    skipEmpty (c :: bs) = c :: bs := by
  cases bs with
  | nil => simp [skipEmpty]
  | cons d rest => rw [skipEmpty.eq_1]; simp [hc]

/-- What `skipEmpty` leaves does not start with CRLF. -/
theorem skipEmpty_head (bs rest : List UInt8) (h : skipEmpty bs = 0x0D :: 0x0A :: rest) : False := by
  fun_induction skipEmpty with
  | case1 c d rest' hcd ih => exact ih h
  | case2 c d rest' hcd =>
    simp at h
    obtain ⟨rfl, rfl, rfl⟩ := h
    simp at hcd
  | case3 bs hbs => exact hbs _ _ _ h

theorem splitOn_three (m t v : List UInt8) (hm : 0x20 ∉ m) (ht : 0x20 ∉ t) (hv : 0x20 ∉ v) :
    (m ++ [0x20] ++ t ++ [0x20] ++ v).splitOn 0x20 = [m, t, v] := by
  have e : m ++ [0x20] ++ t ++ [0x20] ++ v = [(0x20 : UInt8)].intercalate [m, t, v] := by
    simp [List.intercalate]
  rw [e]
  apply List.splitOn_intercalate
  · intro l hl
    simp at hl
    rcases hl with rfl | rfl | rfl <;> assumption
  · simp

private theorem splitOnPPrepend_parts (p : UInt8 → Bool) (xs : List UInt8) :
    ∀ acc : List UInt8, (∀ x ∈ acc, p x = false) →
      ∀ l ∈ List.splitOnPPrepend p xs acc, ∀ x ∈ l, p x = false := by
  induction xs with
  | nil =>
    intro acc hacc l hl x hx
    simp at hl
    subst hl
    exact hacc x (List.mem_reverse.mp hx)
  | cons a t ih =>
    intro acc hacc l hl x hx
    rw [List.splitOnPPrepend_cons_eq_ite] at hl
    split at hl
    · rcases List.mem_cons.mp hl with rfl | hl
      · exact hacc x (List.mem_reverse.mp hx)
      · exact ih [] (by simp) l hl x hx
    · refine ih (a :: acc) ?_ l hl x hx
      intro y hy
      simp at hy
      rcases hy with rfl | hy
      · simpa using ‹¬p y = true›
      · exact hacc y hy

private theorem splitOn_parts (xs l : List UInt8) (hl : l ∈ xs.splitOn 0x20) : (0x20 : UInt8) ∉ l := by
  intro h
  have := splitOnPPrepend_parts (fun x => x == 0x20) xs [] (by simp) l hl _ h
  simp at this

theorem splitOn_three_inv (line m t v : List UInt8) (h : line.splitOn 0x20 = [m, t, v]) :
    line = m ++ [0x20] ++ t ++ [0x20] ++ v ∧ 0x20 ∉ m ∧ 0x20 ∉ t ∧ 0x20 ∉ v := by
  refine ⟨?_, splitOn_parts line m (by simp [h]), splitOn_parts line t (by simp [h]),
    splitOn_parts line v (by simp [h])⟩
  have := List.intercalate_splitOn (xs := line) (0x20 : UInt8)
  rw [h] at this
  rw [← this]
  simp [List.intercalate]

private theorem digit_toNat (n : Nat) (hn : n ≤ 9) : (Spec.digit n).toNat = 0x30 + n := by
  simp [Spec.digit]
  omega

theorem parseVersion_iff (v : List UInt8) (a b : Nat) :
    parseVersion v = some (a, b) ↔
      a ≤ 9 ∧ b ≤ 9 ∧ v = Spec.ascii "HTTP/" ++ [Spec.digit a, 0x2E, Spec.digit b] := by
  have hs : Spec.ascii "HTTP/" = [0x48, 0x54, 0x54, 0x50, 0x2F] := by decide
  rw [hs]
  unfold parseVersion
  split
  · rename_i h t1 t2 p s x dot y
    constructor
    · intro hp
      split at hp
      · rename_i hc
        simp [isDigit, UInt8.le_iff_toNat_le] at hc hp
        obtain ⟨⟨⟨⟨⟨⟨⟨rfl, rfl⟩, rfl⟩, rfl⟩, rfl⟩, rfl⟩, ⟨hx1, hx2⟩⟩, ⟨hy1, hy2⟩⟩ := hc
        obtain ⟨rfl, rfl⟩ := hp
        refine ⟨by omega, by omega, ?_⟩
        simp only [List.cons_append, List.nil_append, List.cons.injEq, and_true, true_and]
        constructor
        · apply UInt8.toNat_inj.mp; rw [digit_toNat _ (by omega)]; omega
        · apply UInt8.toNat_inj.mp; rw [digit_toNat _ (by omega)]; omega
      · simp at hp
    · rintro ⟨ha, hb, he⟩
      simp only [List.cons_append, List.nil_append, List.cons.injEq, and_true] at he
      obtain ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩ := he
      have da := digit_toNat a ha
      have db := digit_toNat b hb
      simp [isDigit, UInt8.le_iff_toNat_le, da, db]
      omega
  · rename_i hne
    simp only [reduceCtorEq, false_iff]
    rintro ⟨-, -, he⟩
    simp only [List.cons_append, List.nil_append] at he
    exact hne _ _ _ _ _ _ _ _ he

end Http.Proofs.Lines
