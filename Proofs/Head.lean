/-
  The head: `parseHead` reads exactly `Spec.Reads`, and printing.
-/

import Http.Head
import Spec.Defs
import Proofs.Match
import Proofs.Lines
import Proofs.Fields

namespace Http.Proofs.Head

open Http

theorem requestTarget_eq : Grammar.requestTarget = Spec.requestTarget := rfl

private theorem ascii_HTTP : Spec.ascii "HTTP/" = [0x48, 0x54, 0x54, 0x50, 0x2F] := by decide

private theorem tchar_ne {c : UInt8} (h : isTchar c = true) : c ≠ 0x0D ∧ c ≠ 0x0A ∧ c ≠ 0x20 := by
  refine ⟨?_, ?_, ?_⟩ <;> (rintro rfl; revert h; decide)

private theorem vis_ne {c : UInt8} (h : (0x21 ≤ c && c ≤ 0x7E) = true) :
    c ≠ 0x0D ∧ c ≠ 0x0A ∧ c ≠ 0x20 := by
  refine ⟨?_, ?_, ?_⟩ <;> (rintro rfl; revert h; decide)

private theorem digit_ne_aux : ∀ a, a < 10 →
    Spec.digit a ≠ 0x0D ∧ Spec.digit a ≠ 0x0A ∧ Spec.digit a ≠ 0x20 := by decide

private theorem digit_ne {a : Nat} (h : a ≤ 9) :
    Spec.digit a ≠ 0x0D ∧ Spec.digit a ≠ 0x0A ∧ Spec.digit a ≠ 0x20 :=
  digit_ne_aux a (by omega)

private theorem target_bytes {t : List UInt8} (ht : Spec.Matches Spec.requestTarget t) :
    ∀ c ∈ t, (0x21 ≤ c && c ≤ 0x7E) = true :=
  Http.Proofs.Match.matches_bytes (fun c => 0x21 ≤ c && c ≤ 0x7E) Spec.requestTarget
    (by decide +kernel) ht

private theorem token_bytes {m : List UInt8} (hm : Spec.Matches Spec.method m) :
    m ≠ [] ∧ ∀ c ∈ m, isTchar c = true := by
  have h := (Http.Proofs.Fields.isToken_iff m).2 hm
  simp only [isToken, Bool.and_eq_true, Bool.not_eq_true', List.isEmpty_eq_false_iff,
    List.all_eq_true] at h
  exact h

theorem parseHead_iff (bs : List UInt8) (h : Head) (rest : List UInt8) :
    parseHead bs = some (h, rest) ↔ Spec.Reads bs h rest := by
  constructor
  · intro hp
    unfold parseHead at hp
    cases h1 : takeLine (skipEmpty bs) with
    | none => simp [h1] at hp
    | some p =>
      obtain ⟨line, rest0⟩ := p
      rw [h1] at hp
      simp only [bind, Option.bind] at hp
      split at hp
      next m t v hs =>
        cases h2 : parseVersion v with
        | none => simp [h2] at hp
        | some ab =>
          obtain ⟨a, b⟩ := ab
          rw [h2] at hp
          simp only at hp
          split at hp
          next hc =>
            cases h3 : parseFields (rest0.length + 1) rest0 with
            | none => simp [h3] at hp
            | some q =>
              obtain ⟨fs, rest'⟩ := q
              rw [h3] at hp
              simp only [pure, Option.some.injEq, Prod.mk.injEq] at hp
              obtain ⟨rfl, rfl⟩ := hp
              obtain ⟨k, hk⟩ := Http.Proofs.Lines.skipEmpty_eq bs
              obtain ⟨-, hl⟩ := (Http.Proofs.Lines.takeLine_iff _ _ _).1 h1
              obtain ⟨hline, -, -, -⟩ := Http.Proofs.Lines.splitOn_three_inv line m t v hs
              obtain ⟨ha, hb, hv⟩ := (Http.Proofs.Lines.parseVersion_iff v a b).1 h2
              rw [Bool.and_eq_true] at hc
              obtain ⟨hm, ht⟩ := hc
              obtain ⟨hfv, tf, hft, hr⟩ :=
                (Http.Proofs.Fields.parseFields_iff _ rest0 fs rest' (by omega)).1 h3
              refine ⟨⟨(Http.Proofs.Fields.isToken_iff m).1 hm,
                (Http.Proofs.Match.isMatch_iff _ t).1 ht, ha, hb, hfv⟩, k, _, ⟨tf, hft, rfl⟩, ?_⟩
              rw [hk, hl, hr, hline, hv]
              simp [Spec.requestLine]
          next => simp at hp
      next => simp at hp
  · rintro ⟨hv, k, tt, ⟨tf, hft, rfl⟩, rfl⟩
    obtain ⟨m, t, a, b, fs⟩ := h
    obtain ⟨hm, ht, ha, hb, hf⟩ := hv
    simp only at hm ht ha hb hf hft
    obtain ⟨hmne, hmc⟩ := token_bytes hm
    have htc := target_bytes ht
    have hmb : ∀ c ∈ m, c ≠ 0x0D ∧ c ≠ 0x0A ∧ c ≠ 0x20 := fun c hc => tchar_ne (hmc c hc)
    have htb : ∀ c ∈ t, c ≠ 0x0D ∧ c ≠ 0x0A ∧ c ≠ 0x20 := fun c hc => vis_ne (htc c hc)
    have hvb : ∀ c ∈ Spec.ascii "HTTP/" ++ [Spec.digit a, 0x2E, Spec.digit b],
        c ≠ 0x0D ∧ c ≠ 0x0A ∧ c ≠ 0x20 := by
      rw [ascii_HTTP]
      intro c hc
      simp only [List.cons_append, List.nil_append, List.mem_cons, List.not_mem_nil, or_false] at hc
      rcases hc with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
      all_goals first | exact digit_ne ha | exact digit_ne hb | decide
    obtain ⟨c, m', rfl⟩ : ∃ c m', m = c :: m' := by
      cases m with
      | nil => exact absurd rfl hmne
      | cons c m' => exact ⟨c, m', rfl⟩
    have hrl : Spec.requestLine ⟨c :: m', t, a, b, fs⟩ =
        (c :: m') ++ [0x20] ++ t ++ [0x20] ++ (Spec.ascii "HTTP/" ++ [Spec.digit a, 0x2E, Spec.digit b]) := by
      simp [Spec.requestLine]
    have hall : ∀ x ∈ Spec.requestLine ⟨c :: m', t, a, b, fs⟩, x ≠ 0x0D ∧ x ≠ 0x0A := by
      intro x hx
      rw [hrl] at hx
      simp only [List.mem_append, List.mem_singleton] at hx
      rcases hx with (((hx | rfl) | hx) | rfl) | hx
      · exact ⟨(hmb x hx).1, (hmb x hx).2.1⟩
      · decide
      · exact ⟨(htb x hx).1, (htb x hx).2.1⟩
      · decide
      · exact ⟨(hvb x (List.mem_append.2 hx)).1, (hvb x (List.mem_append.2 hx)).2.1⟩
    have hskip : skipEmpty ((List.replicate k Spec.crlf).flatten ++
        (Spec.requestLine ⟨c :: m', t, a, b, fs⟩ ++ Spec.crlf ++ tf) ++ rest) =
        Spec.requestLine ⟨c :: m', t, a, b, fs⟩ ++ Spec.crlf ++ (tf ++ rest) := by
      rw [List.append_assoc, Http.Proofs.Lines.skipEmpty_crlf]
      have : Spec.requestLine ⟨c :: m', t, a, b, fs⟩ ++ Spec.crlf ++ tf ++ rest =
          c :: (m' ++ [0x20] ++ t ++ [0x20] ++ (Spec.ascii "HTTP/" ++
            [Spec.digit a, 0x2E, Spec.digit b]) ++ Spec.crlf ++ (tf ++ rest)) := by
        rw [hrl]; simp
      rw [this, Http.Proofs.Lines.skipEmpty_cons _ _ (hmb c (by simp)).1]
      rw [← this]; simp
    have htake : takeLine (Spec.requestLine ⟨c :: m', t, a, b, fs⟩ ++ Spec.crlf ++ (tf ++ rest)) =
        some (Spec.requestLine ⟨c :: m', t, a, b, fs⟩, tf ++ rest) :=
      (Http.Proofs.Lines.takeLine_iff _ _ _).2
        ⟨⟨fun hx => (hall _ hx).1 rfl, fun hx => (hall _ hx).2 rfl⟩, rfl⟩
    have hsplit : (Spec.requestLine ⟨c :: m', t, a, b, fs⟩).splitOn 0x20 =
        [c :: m', t, Spec.ascii "HTTP/" ++ [Spec.digit a, 0x2E, Spec.digit b]] := by
      rw [hrl]
      exact Http.Proofs.Lines.splitOn_three _ _ _
        (fun hx => (hmb _ hx).2.2 rfl) (fun hx => (htb _ hx).2.2 rfl) (fun hx => (hvb _ hx).2.2 rfl)
    have hver : parseVersion (Spec.ascii "HTTP/" ++ [Spec.digit a, 0x2E, Spec.digit b]) = some (a, b) :=
      (Http.Proofs.Lines.parseVersion_iff _ a b).2 ⟨ha, hb, rfl⟩
    have htok : isToken (c :: m') = true := (Http.Proofs.Fields.isToken_iff _).2 hm
    have hmat : Grammar.requestTarget.isMatch t = true := (Http.Proofs.Match.isMatch_iff _ t).2 ht
    have hfld : parseFields ((tf ++ rest).length + 1) (tf ++ rest) = some (fs, rest) :=
      (Http.Proofs.Fields.parseFields_iff _ _ fs rest (by omega)).2 ⟨hf, tf, hft, rfl⟩
    unfold parseHead
    rw [hskip, htake]
    simp only [Option.bind_eq_bind, Option.bind_some]
    rw [hsplit]
    simp only [hver, htok, hmat, Bool.and_self, ite_true, hfld, pure, Option.bind_some]

theorem print_eq (h : Head) : h.print = Spec.render h := by
  simp [Head.print, Spec.render, Spec.requestLine, ascii_HTTP, Spec.digit, Spec.crlf]

private theorem fieldsText_render (fs : List Field) :
    Spec.FieldsText fs
      ((fs.map fun f => f.name ++ [0x3A, 0x20] ++ f.value ++ Spec.crlf).flatten ++ Spec.crlf) := by
  induction fs with
  | nil => simp [Spec.FieldsText]
  | cons f fs ih =>
    refine ⟨f.name ++ [0x3A, 0x20] ++ f.value, _, ⟨[0x20], [], ?_, ?_, by simp⟩, ih, by simp⟩
    · exact (Http.Proofs.Fields.OWS_iff _).2 (by decide)
    · exact (Http.Proofs.Fields.OWS_iff _).2 (by simp)

theorem parseHead_print (h : Head) (rest : List UInt8) (hv : Spec.HeadValid h) :
    parseHead (h.print ++ rest) = some (h, rest) := by
  rw [parseHead_iff]
  refine ⟨hv, 0, Spec.render h, ⟨_, fieldsText_render h.fields, ?_⟩, by simp [print_eq]⟩
  simp [Spec.render]

end Http.Proofs.Head
