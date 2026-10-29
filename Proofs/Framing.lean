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

private theorem foldl_digits (b : List UInt8) (x : Nat) :
    b.foldl (fun n d => 10 * n + (d.toNat - 0x30)) x =
      x * 10 ^ b.length + b.foldl (fun n d => 10 * n + (d.toNat - 0x30)) 0 := by
  induction b generalizing x with
  | nil => simp
  | cons d b ih =>
    simp only [List.foldl_cons, List.length_cons]
    rw [ih, ih (10 * 0 + _), Nat.pow_succ]
    simp only [Nat.mul_zero, Nat.zero_add, Nat.add_mul, Nat.mul_assoc, Nat.add_assoc]
    have e : 10 * (x * 10 ^ b.length) = x * (10 ^ b.length * 10) := by
      rw [Nat.mul_left_comm, Nat.mul_comm 10]
    rw [e]

/-- The number that `a ++ b` writes. -/
private theorem decimal_append (a b : List UInt8) :
    decimal (a ++ b) = decimal a * 10 ^ b.length + decimal b := by
  unfold decimal
  rw [List.foldl_append, foldl_digits]

private theorem decimalBy_eq (fuel n : Nat) (ds : List UInt8) (hn : ds.length = n) :
    decimalBy fuel n ds = decimal ds := by
  induction fuel generalizing n ds with
  | zero => rfl
  | succ fuel ih =>
    simp only [decimalBy, List.splitAt_eq]
    split
    · rfl
    · rw [ih (n / 2) _ (by simp [hn]; omega), ih (n - n / 2) _ (by simp [hn])]
      conv => rhs; rw [← List.take_append_drop (n / 2) ds]
      rw [decimal_append, List.length_drop, hn]

private theorem decimalFast_eq : decimalFast = Spec.decimal := by
  funext ds
  exact decimalBy_eq _ _ _ rfl

private theorem decimal_zero_cons (cs : List UInt8) : decimal (0x30 :: cs) = decimal cs := by
  simp [decimal]

/-- What is left of a string of digits after its leading zeros writes the
    same number, and is empty or starts with a digit other than 0. -/
private theorem dropZeros (ds : List UInt8) (hd : ∀ c ∈ ds, isDigit c = true) :
    decimal (ds.dropWhile (· == 0x30)) = decimal ds ∧ (∀ c ∈ ds.dropWhile (· == 0x30), isDigit c = true) ∧
      ∀ d rest, ds.dropWhile (· == 0x30) = d :: rest → d ≠ 0x30 := by
  induction ds with
  | nil => simp
  | cons c cs ih =>
    have hcs : ∀ x ∈ cs, isDigit x = true := fun x hx => hd x (by simp [hx])
    by_cases hc : c = 0x30
    · subst hc
      have e : (0x30 :: cs).dropWhile (· == (0x30 : UInt8)) = cs.dropWhile (· == 0x30) := by
        simp
      rw [e, decimal_zero_cons]
      exact ih hcs
    · have e : (c :: cs).dropWhile (· == (0x30 : UInt8)) = c :: cs := by
        simp [hc]
      rw [e]
      refine ⟨rfl, hd, ?_⟩
      intro d rest h
      simp only [List.cons.injEq] at h
      rw [← h.1]
      exact hc

/-- A string of digits that starts with a digit other than 0 writes at
    least 10 to the number of digits after the first. -/
private theorem decimal_ge (d : UInt8) (rest : List UInt8) (hd : isDigit d = true) (h0 : d ≠ 0x30) :
    10 ^ rest.length ≤ decimal (d :: rest) := by
  have e : decimal (d :: rest) = decimal [d] * 10 ^ rest.length + decimal rest := decimal_append [d] rest
  have h1 : 1 ≤ decimal [d] := by
    simp only [decimal, List.foldl_cons, List.foldl_nil]
    simp only [isDigit, Bool.and_eq_true, decide_eq_true_eq] at hd
    have : d.toNat ≠ 0x30 := fun h => h0 (UInt8.toNat_inj.mp h)
    have := UInt8.le_iff_toNat_le.mp hd.1
    simp at this ⊢
    omega
  rw [e]
  calc 10 ^ rest.length = 1 * 10 ^ rest.length := (Nat.one_mul _).symm
    _ ≤ decimal [d] * 10 ^ rest.length := Nat.mul_le_mul_right _ h1
    _ ≤ _ := Nat.le_add_right _ _

private theorem portInRange_iff (ds : List UInt8) (hd : ∀ c ∈ ds, isDigit c = true) :
    portInRange ds = true ↔ 1 ≤ Spec.decimal ds ∧ Spec.decimal ds ≤ 65535 := by
  obtain ⟨hdec, hdig, hlead⟩ := dropZeros ds hd
  rw [← decimal_eq, ← hdec]
  unfold portInRange
  generalize ds.dropWhile (· == 0x30) = z at hdig hlead
  simp only
  split
  · simp only [Bool.and_eq_true, decide_eq_true_eq]
  · rename_i hlen
    simp only [Bool.false_eq_true, false_iff]
    rintro ⟨-, h2⟩
    cases z with
    | nil => simp at hlen
    | cons d rest =>
      have hge := decimal_ge d rest (hdig d (by simp)) (hlead d rest rfl)
      have : 10 ^ 5 ≤ 10 ^ rest.length := Nat.pow_le_pow_right (by decide) (by simp at hlen; omega)
      omega

private theorem digits_iff (v : List UInt8) :
    (!v.isEmpty && v.all isDigit) = true ↔ Spec.Matches Spec.contentLength v := by
  rw [Fields.contentLength_iff]
  cases v <;> simp

theorem hostField_eq : Grammar.hostField = Spec.hostField := rfl

theorem chunkedList_eq : Grammar.chunkedList = Spec.listOne (Re.litCI "chunked") := rfl

theorem connectTarget_eq :
    Grammar.connectTarget = Re.seq [Spec.hostNonEmpty, Re.litCI ":", Spec.port] := rfl

private theorem colon_eq : Re.litCI ":" = .range 0x3A 0x3A := rfl

/-- A CONNECT target is a host that is not empty, a colon and a port. -/
private theorem connectTarget_iff (t : List UInt8) :
    Spec.Matches (Re.seq [Spec.hostNonEmpty, Re.litCI ":", Spec.port]) t ↔
      ∃ host port, t = host ++ [0x3A] ++ port ∧ Spec.Matches Spec.hostNonEmpty host ∧
        Spec.Matches Spec.port port := by
  simp only [Re.seq, colon_eq, Match.matches_cat_iff, Match.matches_range_iff]
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
  simp only [Bool.or_eq_true, bne_iff_ne, ne_eq, Bool.and_eq_true,
    Match.isMatch_iff, connectTarget_eq, connectTarget_iff]
  constructor
  · rintro (hm | ⟨⟨host, port, rfl, hh, hp⟩, hr⟩) hc
    · exact absurd hc hm
    · rw [portOf_eq ((Fields.port_iff port).1 hp), portInRange_iff _ ((Fields.port_iff port).1 hp)] at hr
      exact ⟨host, port, rfl, hh, hp, hr.1, hr.2⟩
  · intro hc
    by_cases hm : m = connectName
    · obtain ⟨host, port, rfl, hh, hp, h1, h2⟩ := hc hm
      rw [portOf_eq ((Fields.port_iff port).1 hp)]
      exact .inr ⟨⟨host, port, rfl, hh, hp⟩, (portInRange_iff _ ((Fields.port_iff port).1 hp)).2 ⟨h1, h2⟩⟩
    · exact .inl hm

theorem httpTarget_eq : Grammar.httpTarget = Spec.httpTarget := rfl

/-- `Grammar.httpTarget` with its two schemes as lists of characters,
    not string literals. -/
def httpTargetChars : Re :=
  .seq [.alt (.seq (['h', 't', 't', 'p'].map .charCI)) (.seq (['h', 't', 't', 'p', 's'].map .charCI)),
    .litCI "://", Grammar.hostNonEmpty, .opt (.cat (.litCI ":") Grammar.port), Grammar.pathAbempty,
    .opt (.cat (.litCI "?") Grammar.query)]

/-- `Head.httpTargetOK` with `httpTargetChars` in place of
    `Grammar.httpTarget`. -/
def httpTargetOKChars (h : Head) : Bool :=
  h.method == connectName ||
    !(httpColon.isPrefixOf (h.target.map lower) || httpsColon.isPrefixOf (h.target.map lower)) ||
    httpTargetChars.isMatch h.target

/-- `head_vectors` rewrites with this before `decide`. Matching an http
    target compares `litCI "http"` with `litCI "https"`, and the nanoda
    checker runs out of stack when it reads the two from string
    literals. -/
theorem httpTargetOK_chars : Head.httpTargetOK = httpTargetOKChars := rfl

theorem httpTargetOK_iff (h : Head) : h.httpTargetOK = true ↔ Spec.HttpTargetOK h := by
  have ec : Spec.ascii "CONNECT" = connectName := rfl
  have e1 : Spec.ascii "http:" = httpColon := rfl
  have e2 : Spec.ascii "https:" = httpsColon := rfl
  unfold Head.httpTargetOK Spec.HttpTargetOK
  rw [ec, e1, e2, ← lower_eq]
  generalize h.method = m
  generalize h.target.map lower = l
  simp only [Bool.or_eq_true, beq_iff_eq, Bool.not_eq_true', Bool.eq_false_iff,
    ne_eq, List.isPrefixOf_iff_prefix, Match.isMatch_iff, httpTarget_eq]
  constructor
  · rintro ((hm | hp) | ht) hm' hp'
    · exact absurd hm hm'
    · exact absurd hp' hp
    · exact ht
  · intro H
    by_cases hm : m = connectName
    · exact .inl (.inl hm)
    by_cases hp : httpColon <+: l ∨ httpsColon <+: l
    · exact .inr (H hm hp)
    · exact .inl (.inr hp)

private theorem ite_none_iff {α : Type} {c : Bool} {x : Option α} {y : α} :
    (if c = true then none else x) = some y ↔ c = false ∧ x = some y := by
  cases c <;> simp

private theorem ite_some_iff {α : Type} {c : Bool} {x y : α} :
    (if c = true then some x else none) = some y ↔ c = true ∧ x = y := by
  cases c <;> simp

private theorem cond_iff (h : Head) (H : List Field) :
    (h.major != 1 || decide (H.length > 1) || (decide (1 ≤ h.minor) && H.length != 1) ||
      !H.all (fun f => Grammar.hostField.isMatch f.value)) = false ↔
    h.major = 1 ∧ H.length ≤ 1 ∧ (1 ≤ h.minor → H.length = 1) ∧
      ∀ f ∈ H, Spec.Matches Spec.hostField f.value := by
  simp only [Bool.or_eq_false_iff, bne_eq_false_iff_eq, decide_eq_false_iff_not, Bool.and_eq_false_imp,
    decide_eq_true_eq, Bool.not_eq_false', List.all_eq_true, Match.isMatch_iff, hostField_eq]
  constructor
  · rintro ⟨⟨⟨h1, h2⟩, h3⟩, h4⟩
    exact ⟨h1, by omega, h3, h4⟩
  · rintro ⟨h1, h2, h3, h4⟩
    exact ⟨⟨⟨h1, by omega⟩, h3⟩, h4⟩

private theorem target_cond_iff (h : Head) :
    (!h.connectOK || !h.httpTargetOK) = false ↔ Spec.ConnectOK h ∧ Spec.HttpTargetOK h := by
  rw [Bool.or_eq_false_iff, Bool.not_eq_false', Bool.not_eq_false', connectOK_iff, httpTargetOK_iff]

theorem framingCore_iff (h : Head) (fr : Framing) :
    h.framingCore = some fr ↔
      h.major = 1 ∧ Spec.HostOK h ∧ Spec.ConnectOK h ∧ Spec.HttpTargetOK h ∧ Spec.FramedAs h fr := by
  have eh : Spec.named h "host" = h.fields.filter (·.isNamed hostName) := named_eq h "host"
  have et : Spec.named h "transfer-encoding" = h.fields.filter (·.isNamed transferEncodingName) :=
    named_eq h "transfer-encoding"
  have ec : Spec.named h "content-length" = h.fields.filter (·.isNamed contentLengthName) :=
    named_eq h "content-length"
  unfold Head.framingCore Spec.HostOK
  rw [ite_none_iff, cond_iff, ite_none_iff, target_cond_iff, and_assoc, eh]
  apply and_congr_right
  intro _
  apply and_congr_right
  intro _
  rw [and_assoc]
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
      simp [← digits_iff, decimalFast_eq]
    all_goals (intros; exact eq_comm)

theorem framing_iff (h : Head) (fr : Framing) : h.framing = some fr ↔ Spec.Accepts h fr := by
  have ec : Spec.ascii "CONNECT" = connectName := rfl
  unfold Head.framing Spec.Accepts Spec.AuthorityHostOK Spec.ConnectNoContent
  rw [ec]
  constructor
  · intro hf
    cases hc : h.framingCore with
    | none => rw [hc] at hf; cases hf
    | some fr' =>
      rw [hc] at hf
      simp only at hf
      split at hf
      · cases hf
      · rename_i hcond
        cases hf
        obtain ⟨a, b, c, d, e⟩ := (framingCore_iff h _).1 hc
        simp only [Bool.or_eq_true, beq_iff_eq, Bool.and_eq_true, bne_iff_ne, ne_eq, not_or,
          not_and, Decidable.not_not] at hcond
        exact ⟨a, b, c, d, hcond.1, hcond.2, e⟩
  · rintro ⟨a, b, c, d, e, g, f⟩
    rw [(framingCore_iff h fr).2 ⟨a, b, c, d, f⟩]
    simp only
    split
    · rename_i hcond
      simp only [Bool.or_eq_true, beq_iff_eq, Bool.and_eq_true, bne_iff_ne, ne_eq] at hcond
      rcases hcond with h1 | ⟨h2, h3⟩
      · exact absurd h1 e
      · exact absurd (g h2) h3
    · rfl

theorem framing_te_cl (h : Head) (hte : Spec.named h "transfer-encoding" ≠ [])
    (hcl : Spec.named h "content-length" ≠ []) : h.framing = none := by
  cases hf : h.framing with
  | none => rfl
  | some fr =>
    have ⟨_, _, _, _, _, _, hfr⟩ := (framing_iff h fr).1 hf
    cases fr with
    | chunked => exact absurd hfr.2.1 hcl
    | length n => exact absurd hfr.1 hte

theorem framing_two_cl (h : Head) (h2 : 2 ≤ (Spec.named h "content-length").length) :
    h.framing = none := by
  cases hf : h.framing with
  | none => rfl
  | some fr =>
    have ⟨_, _, _, _, _, _, hfr⟩ := (framing_iff h fr).1 hf
    cases fr with
    | chunked => rw [hfr.2.1] at h2; simp at h2
    | length n =>
      rcases hfr.2 with ⟨hc, _⟩ | ⟨f, hc, _⟩ <;> rw [hc] at h2 <;> simp at h2

end Http.Proofs.Framing
