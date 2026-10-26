/-
  Tokens, field values, optional whitespace, and the field lines.
-/

import Http.Head
import Spec.Defs

namespace Http.Proofs.Fields

open Http Http.Re

private theorem m_eps {s : List UInt8} : Spec.Matches .eps s ↔ s = [] := by
  constructor
  · intro h; cases h; rfl
  · rintro rfl; exact .eps

private theorem m_range {lo hi : UInt8} {s : List UInt8} :
    Spec.Matches (.range lo hi) s ↔ ∃ c, s = [c] ∧ lo ≤ c ∧ c ≤ hi := by
  constructor
  · intro h; cases h with
    | range h1 h2 => exact ⟨_, rfl, h1, h2⟩
  · rintro ⟨c, rfl, h1, h2⟩; exact .range h1 h2

private theorem m_cat {a b : Re} {s : List UInt8} :
    Spec.Matches (.cat a b) s ↔ ∃ s1 s2, s = s1 ++ s2 ∧ Spec.Matches a s1 ∧ Spec.Matches b s2 := by
  constructor
  · intro h; cases h with
    | cat h1 h2 => exact ⟨_, _, rfl, h1, h2⟩
  · rintro ⟨s1, s2, rfl, h1, h2⟩; exact .cat h1 h2

private theorem m_alt {a b : Re} {s : List UInt8} :
    Spec.Matches (.alt a b) s ↔ Spec.Matches a s ∨ Spec.Matches b s := by
  constructor
  · intro h; cases h with
    | altL h => exact .inl h
    | altR h => exact .inr h
  · rintro (h | h)
    · exact .altL h
    · exact .altR h

/-- Induction principle for star. -/
private theorem star_ind {a : Re} (P : List UInt8 → Prop) (h0 : P [])
    (h1 : ∀ s t, Spec.Matches a s → Spec.Matches (.star a) t → P t → P (s ++ t))
    {s : List UInt8} (h : Spec.Matches (.star a) s) : P s := by
  generalize e : Re.star a = R at h
  induction h with
  | eps => cases e
  | range => cases e
  | cat => cases e
  | altL => cases e
  | altR => cases e
  | starNil => exact h0
  | starCons hs ht _ iht =>
    cases e
    exact h1 _ _ hs ht (iht rfl)

/-- `r` matches exactly the one-octet strings `[x]` with `p x`. -/
private def Single (r : Re) (p : UInt8 → Bool) : Prop :=
  ∀ s, Spec.Matches r s ↔ ∃ x, s = [x] ∧ p x = true

private theorem single_range (lo hi : UInt8) : Single (.range lo hi) (fun x => decide (lo ≤ x) && decide (x ≤ hi)) := by
  intro s; rw [m_range]; simp

private theorem single_alt {a b : Re} {p q : UInt8 → Bool} (ha : Single a p) (hb : Single b q) :
    Single (.alt a b) (fun x => p x || q x) := by
  intro s; rw [m_alt, ha, hb]
  constructor
  · rintro (⟨x, rfl, hx⟩ | ⟨x, rfl, hx⟩) <;> exact ⟨x, rfl, by simp [hx]⟩
  · rintro ⟨x, rfl, hx⟩
    simp only [Bool.or_eq_true] at hx
    rcases hx with hx | hx
    · exact .inl ⟨x, rfl, hx⟩
    · exact .inr ⟨x, rfl, hx⟩

private theorem single_congr {r : Re} {p q : UInt8 → Bool} (h : Single r p) (hpq : ∀ x, p x = q x) :
    Single r q := by
  intro s; rw [h]; simp [hpq]

private theorem single_star {r : Re} {p : UInt8 → Bool} (h : Single r p) (s : List UInt8) :
    Spec.Matches (.star r) s ↔ ∀ x ∈ s, p x = true := by
  constructor
  · intro hs
    refine star_ind (fun s => ∀ x ∈ s, p x = true) (by simp) ?_ hs
    intro s t hs _ ht
    obtain ⟨y, rfl, hy⟩ := (h s).1 hs
    intro x hx
    simp at hx
    rcases hx with rfl | hx
    · exact hy
    · exact ht x hx
  · intro hs
    induction s with
    | nil => exact .starNil
    | cons y s ih =>
      have : y :: s = [y] ++ s := rfl
      rw [this]
      exact .starCons ((h _).2 ⟨y, rfl, hs y (by simp)⟩) (ih (fun x hx => hs x (by simp [hx])))

private theorem single_plus {r : Re} {p : UInt8 → Bool} (h : Single r p) (s : List UInt8) :
    Spec.Matches (plus r) s ↔ s ≠ [] ∧ ∀ x ∈ s, p x = true := by
  simp only [plus]
  rw [m_cat]
  constructor
  · rintro ⟨s1, s2, rfl, h1, h2⟩
    obtain ⟨y, rfl, hy⟩ := (h _).1 h1
    rw [single_star h] at h2
    refine ⟨by simp, ?_⟩
    intro x hx
    simp at hx
    rcases hx with rfl | hx
    · exact hy
    · exact h2 x hx
  · rintro ⟨hne, hs⟩
    match s, hne with
    | y :: s', _ =>
      refine ⟨[y], s', rfl, (h _).2 ⟨y, rfl, hs y (by simp)⟩, ?_⟩
      rw [single_star h]
      intro x hx; exact hs x (by simp [hx])


private theorem uint8_forall {p : UInt8 → Prop} (h : ∀ n, n < 256 → p (UInt8.ofNat n)) : ∀ x, p x := by
  intro x
  have := h x.toNat (UInt8.toNat_lt x)
  rwa [UInt8.ofNat_toNat] at this

/-- Whether a rule is a class of single octets. -/
private def IsCls : Re → Bool
  | .range _ _ => true
  | .alt a b => IsCls a && IsCls b
  | _ => false

/-- The octets of a class. -/
private def clsP : Re → UInt8 → Bool
  | .range lo hi => fun x => decide (lo ≤ x) && decide (x ≤ hi)
  | .alt a b => fun x => clsP a x || clsP b x
  | _ => fun _ => false

private theorem cls_single : ∀ (r : Re), IsCls r = true → Single r (clsP r)
  | .range lo hi, _ => single_range lo hi
  | .alt a b, h => by
    simp only [IsCls, Bool.and_eq_true] at h
    exact single_alt (cls_single a h.1) (cls_single b h.2)
  | .empty, h => by simp [IsCls] at h
  | .eps, h => by simp [IsCls] at h
  | .cat _ _, h => by simp [IsCls] at h
  | .star _, h => by simp [IsCls] at h

private theorem tchar_eq : Spec.tchar = any [byte 0x21, byte 0x23, byte 0x24, byte 0x25, byte 0x26, byte 0x27,
    byte 0x2A, byte 0x2B, byte 0x2D, byte 0x2E, byte 0x5E, byte 0x5F,
    byte 0x60, byte 0x7C, byte 0x7E, Spec.DIGIT, Spec.ALPHA] := by decide

private theorem single_tchar : Single Spec.tchar isTchar := by
  rw [tchar_eq]
  refine single_congr (cls_single _ rfl) ?_
  exact uint8_forall (by decide +kernel)

private theorem single_ws : Single (.alt Spec.SP Spec.HTAB) isWs :=
  single_congr (cls_single _ rfl) (uint8_forall (by decide +kernel))

private theorem single_digit : Single Spec.DIGIT isDigit :=
  single_congr (cls_single _ rfl) (uint8_forall (by decide +kernel))

private theorem single_fieldVchar : Single Spec.fieldVchar isVchar :=
  single_congr (cls_single _ rfl) (uint8_forall (by decide +kernel))

private theorem single_wsv : Single (any [Spec.SP, Spec.HTAB, Spec.fieldVchar]) (fun x => isWs x || isVchar x) :=
  single_congr (cls_single _ rfl) (uint8_forall (by decide +kernel))


theorem isToken_iff (s : List UInt8) : isToken s = true ↔ Spec.Matches Spec.token s := by
  rw [Spec.token, single_plus single_tchar]
  simp [isToken, List.all_eq_true]

theorem OWS_iff (w : List UInt8) : Spec.Matches Spec.OWS w ↔ ∀ c ∈ w, isWs c = true := by
  rw [Spec.OWS, single_star single_ws]

theorem contentLength_iff (v : List UInt8) :
    Spec.Matches Spec.contentLength v ↔ v ≠ [] ∧ ∀ c ∈ v, isDigit c = true := by
  rw [Spec.contentLength, single_plus single_digit]

theorem port_iff (v : List UInt8) : Spec.Matches Spec.port v ↔ ∀ c ∈ v, isDigit c = true := by
  rw [Spec.port, single_star single_digit]

/-- The shape of a field value. -/
private def FV (v : List UInt8) : Prop :=
  (∀ x ∈ v, (isVchar x || isWs x) = true) ∧ (∀ a, v.head? = some a → isVchar a = true) ∧
    (∀ b, v.getLast? = some b → isVchar b = true)

private theorem FV_append {s t : List UInt8} (hs : FV s) (ht : FV t) : FV (s ++ t) := by
  obtain ⟨hs1, hs2, hs3⟩ := hs
  obtain ⟨ht1, ht2, ht3⟩ := ht
  refine ⟨?_, ?_, ?_⟩
  · intro x hx
    rw [List.mem_append] at hx
    rcases hx with hx | hx
    · exact hs1 x hx
    · exact ht1 x hx
  · intro a ha
    rw [List.head?_append] at ha
    cases h : s.head? with
    | some a' => rw [h] at ha; simp at ha; subst ha; exact hs2 _ h
    | none => rw [h] at ha; simp at ha; exact ht2 _ ha
  · intro b hb
    rw [List.getLast?_append] at hb
    cases h : t.getLast? with
    | some b' => rw [h] at hb; simp at hb; subst hb; exact ht3 _ h
    | none => rw [h] at hb; simp at hb; exact hs3 _ hb

private theorem fc_iff (s : List UInt8) : Spec.Matches Spec.fieldContent s ↔
    ∃ a rest, s = a :: rest ∧ isVchar a = true ∧
      (rest = [] ∨ ∃ m b, rest = m ++ [b] ∧ m ≠ [] ∧ (∀ x ∈ m, (isWs x || isVchar x) = true) ∧
        isVchar b = true) := by
  have hv : ∀ s, Spec.Matches Spec.fieldVchar s ↔ ∃ x, s = [x] ∧ isVchar x = true :=
    single_fieldVchar
  rw [Spec.fieldContent, m_cat]
  simp only [opt, m_alt, m_eps, m_cat, single_plus single_wsv, hv]
  constructor
  · rintro ⟨s1, s2, rfl, ⟨a, rfl, ha⟩, h2⟩
    refine ⟨a, s2, rfl, ha, ?_⟩
    rcases h2 with h2 | ⟨m, s3, rfl, ⟨hm1, hm2⟩, ⟨b, rfl, hb⟩⟩
    · exact .inl h2
    · exact .inr ⟨m, b, rfl, hm1, hm2, hb⟩
  · rintro ⟨a, rest, rfl, ha, h⟩
    refine ⟨[a], rest, rfl, ⟨a, rfl, ha⟩, ?_⟩
    rcases h with h | ⟨m, b, rfl, hm1, hm2, hb⟩
    · exact .inl h
    · exact .inr ⟨m, [b], rfl, ⟨hm1, hm2⟩, ⟨b, rfl, hb⟩⟩

private theorem fc_FV {s : List UInt8} (h : Spec.Matches Spec.fieldContent s) : FV s := by
  rw [fc_iff] at h
  obtain ⟨a, rest, rfl, ha, h⟩ := h
  rcases h with rfl | ⟨m, b, rfl, _, hm2, hb⟩
  · refine ⟨?_, ?_, ?_⟩
    · intro x hx; simp at hx; subst hx; simp [ha]
    · intro a' h'; simp at h'; subst h'; exact ha
    · intro a' h'; simp at h'; subst h'; exact ha
  · refine ⟨?_, ?_, ?_⟩
    · intro x hx
      simp only [List.mem_cons, List.mem_append, List.not_mem_nil, or_false] at hx
      rcases hx with rfl | hx | rfl
      · simp [ha]
      · have := hm2 x hx; simp only [Bool.or_eq_true] at this ⊢; exact this.symm
      · simp [hb]
    · intro a' h'; simp at h'; subst h'; exact ha
    · intro b' h'
      have : (a :: (m ++ [b])).getLast? = some b := by
        rw [← List.cons_append, List.getLast?_append]; simp
      rw [this] at h'; simp at h'; subst h'; exact hb

private theorem isFieldValue_FV (v : List UInt8) : isFieldValue v = true ↔ FV v := by
  unfold isFieldValue FV
  cases v with
  | nil => simp
  | cons a rest =>
    have hl : (a :: rest).getLast? = some ((a :: rest).getLast (by simp)) := List.getLast?_eq_some_getLast _
    rw [hl]
    simp only [List.head?_cons, Bool.and_eq_true, List.all_eq_true]
    constructor
    · rintro ⟨h1, h2, h3⟩
      refine ⟨h1, ?_, ?_⟩
      · intro a' h; simp at h; subst h; exact h2
      · intro b' h; simp at h; subst h; exact h3
    · rintro ⟨h1, h2, h3⟩
      exact ⟨h1, h2 _ rfl, h3 _ rfl⟩

theorem isFieldValue_iff (v : List UInt8) :
    isFieldValue v = true ↔ Spec.Matches Spec.fieldValue v := by
  rw [isFieldValue_FV, Spec.fieldValue]
  constructor
  · rintro ⟨h1, h2, h3⟩
    have fc1 : ∀ a, isVchar a = true → Spec.Matches Spec.fieldContent [a] := by
      intro a ha; rw [fc_iff]; exact ⟨a, [], rfl, ha, .inl rfl⟩
    match v, h1, h2, h3 with
    | [], _, _, _ => exact .starNil
    | a :: rest, h1, h2, h3 =>
      have ha : isVchar a = true := h2 a rfl
      rcases List.eq_nil_or_concat rest with rfl | ⟨m, b, rfl⟩
      all_goals try simp only [List.concat_eq_append] at *
      · have : [a] = [a] ++ [] := rfl
        rw [this]; exact .starCons (fc1 a ha) .starNil
      · have hb : isVchar b = true := by
          apply h3; rw [← List.cons_append, List.getLast?_append]; simp
        cases m with
        | nil =>
          have : a :: ([] ++ [b]) = [a] ++ ([b] ++ []) := rfl
          rw [this]; exact .starCons (fc1 a ha) (.starCons (fc1 b hb) .starNil)
        | cons c m' =>
          have : a :: ((c :: m') ++ [b]) = (a :: ((c :: m') ++ [b])) ++ [] := by simp
          rw [this]
          refine .starCons ?_ .starNil
          rw [fc_iff]
          refine ⟨a, _, rfl, ha, .inr ⟨c :: m', b, rfl, by simp, ?_, hb⟩⟩
          intro x hx
          have := h1 x (List.mem_cons_of_mem _ (List.mem_append_left _ hx))
          simp only [Bool.or_eq_true] at this ⊢; exact this.symm
  · intro h
    refine star_ind FV ⟨by simp, by simp, by simp⟩ ?_ h
    intro s t hs _ ht
    exact FV_append (fc_FV hs) ht


private theorem mem_takeWhile {p : UInt8 → Bool} : ∀ {l : List UInt8} {x : UInt8}, x ∈ l.takeWhile p → p x = true
  | [], _, h => by simp at h
  | a :: l, x, h => by
    rw [List.takeWhile_cons] at h
    split at h
    · simp only [List.mem_cons] at h
      rcases h with rfl | h
      · assumption
      · exact mem_takeWhile h
    · simp at h

private theorem drop_takeWhile (p : UInt8 → Bool) : ∀ l : List UInt8, l.drop (l.takeWhile p).length = l.dropWhile p
  | [] => rfl
  | a :: l => by
    rw [List.takeWhile_cons, List.dropWhile_cons]
    split
    · simp only [List.length_cons, List.drop_succ_cons]; exact drop_takeWhile p l
    · rfl

private theorem dropWhile_head {p : UInt8 → Bool} : ∀ {l v : List UInt8} {c : UInt8},
    l.dropWhile p = c :: v → p c = false
  | [], _, _, h => by simp at h
  | a :: l, v, c, h => by
    rw [List.dropWhile_cons] at h
    split at h
    · exact dropWhile_head h
    · rename_i hn; simp at h; obtain ⟨rfl, rfl⟩ := h; simpa using hn

private theorem takeWhile_prefix {p : UInt8 → Bool} : ∀ {xs : List UInt8} (y : UInt8) (ys : List UInt8),
    (∀ x ∈ xs, p x = true) → p y = false → (xs ++ y :: ys).takeWhile p = xs
  | [], y, ys, _, hy => by simp [hy]
  | a :: xs, y, ys, h, hy => by
    rw [List.cons_append, List.takeWhile_cons, ite_eq_left (h a (by simp)),
      takeWhile_prefix y ys (fun x hx => h x (by simp [hx])) hy]

private theorem dropWhile_ws {p : UInt8 → Bool} {xs ys : List UInt8} (h1 : ∀ x ∈ xs, p x = true)
    (h2 : ∀ y, ys.head? = some y → p y = false) : (xs ++ ys).dropWhile p = ys := by
  rw [List.dropWhile_append_of_pos h1]
  cases ys with
  | nil => rfl
  | cons y ys => rw [List.dropWhile_cons_of_neg (by simp [h2 y rfl])]

private theorem trim_split (v : List UInt8) : ∃ w1 w2, (∀ c ∈ w1, isWs c = true) ∧ (∀ c ∈ w2, isWs c = true) ∧
    v = w1 ++ trim v ++ w2 := by
  refine ⟨v.takeWhile isWs, ((v.dropWhile isWs).reverse.takeWhile isWs).reverse,
    fun c hc => mem_takeWhile hc, fun c hc => mem_takeWhile (List.mem_reverse.1 hc), ?_⟩
  unfold trim
  rw [List.append_assoc, ← List.reverse_append, List.takeWhile_append_dropWhile, List.reverse_reverse,
    List.takeWhile_append_dropWhile]

private theorem vchar_not_ws : ∀ x, isVchar x = true → isWs x = false :=
  uint8_forall (by decide +kernel)

private theorem trim_eq {w1 w2 val : List UInt8} (h1 : ∀ c ∈ w1, isWs c = true) (h2 : ∀ c ∈ w2, isWs c = true)
    (hv : FV val) : trim (w1 ++ val ++ w2) = val := by
  unfold trim
  cases val with
  | nil =>
    have e : w1 ++ [] ++ w2 = (w1 ++ w2) ++ [] := by simp
    rw [e, List.dropWhile_append_of_pos (fun x hx => by
      rw [List.mem_append] at hx; rcases hx with hx | hx; exact h1 x hx; exact h2 x hx)]
    rfl
  | cons a rest =>
    obtain ⟨_, hv2, hv3⟩ := hv
    rw [List.append_assoc, dropWhile_ws h1, List.reverse_append, dropWhile_ws, List.reverse_reverse]
    · intro c hc; exact h2 c (List.mem_reverse.1 hc)
    · intro y hy; rw [List.head?_reverse] at hy; exact vchar_not_ws y (hv3 y hy)
    · intro y hy; simp at hy; subst hy; exact vchar_not_ws _ (hv2 _ rfl)

private theorem tchar_not_colon : ∀ x, isTchar x = true → (x != 0x3A) = true :=
  uint8_forall (by decide +kernel)

private theorem token_tchar {s : List UInt8} (h : Spec.Matches Spec.token s) : ∀ x ∈ s, isTchar x = true :=
  ((single_plus single_tchar s).1 h).2

theorem parseField_iff (line : List UInt8) (f : Field) :
    parseField line = some f ↔ Spec.FieldValid f ∧ Spec.FieldLineText f line := by
  constructor
  · intro hp
    unfold parseField at hp
    dsimp only at hp
    rw [drop_takeWhile] at hp
    split at hp
    · rename_i c v heq
      split at hp
      · rename_i hc
        cases hp
        simp only [Bool.and_eq_true] at hc
        refine ⟨⟨(isToken_iff _).1 hc.1, (isFieldValue_iff _).1 hc.2⟩, ?_⟩
        obtain ⟨w1, w2, hw1, hw2, hvw⟩ := trim_split v
        refine ⟨w1, w2, (OWS_iff _).2 hw1, (OWS_iff _).2 hw2, ?_⟩
        have hc3 : c = 0x3A := by
          have := dropWhile_head heq; simpa using this
        subst hc3
        conv => lhs; rw [← List.takeWhile_append_dropWhile (p := (· != 0x3A)) (l := line)]
        rw [heq]
        conv => lhs; rw [hvw]
        simp
      · cases hp
    · cases hp
  · rintro ⟨⟨hn, hv⟩, w1, w2, h1, h2, rfl⟩
    rw [OWS_iff] at h1 h2
    have hfv : FV f.value := (isFieldValue_FV _).1 ((isFieldValue_iff _).2 hv)
    have e : f.name ++ [0x3A] ++ w1 ++ f.value ++ w2 = f.name ++ 0x3A :: (w1 ++ f.value ++ w2) := by
      simp
    rw [e]
    have ht : (f.name ++ 0x3A :: (w1 ++ f.value ++ w2)).takeWhile (· != 0x3A) = f.name :=
      takeWhile_prefix _ _ (fun x hx => tchar_not_colon x (token_tchar hn x hx)) (by decide)
    unfold parseField
    simp only [ht, List.drop_left, trim_eq h1 h2 hfv]
    rw [(isToken_iff _).2 hn, (isFieldValue_iff _).2 hv]
    rfl


private theorem takeLine_eq : ∀ {bs l r : List UInt8}, takeLine bs = some (l, r) → bs = l ++ Spec.crlf ++ r
  | [], _, _, h => by simp [takeLine] at h
  | c :: rest, l, r, h => by
    unfold takeLine at h
    split at h
    · rename_i hc
      split at h
      · rename_i d rest'
        split at h
        · rename_i hd
          simp only [Option.some.injEq, Prod.mk.injEq] at h
          obtain ⟨rfl, rfl⟩ := h
          simp only [beq_iff_eq] at hc hd
          subst hc; subst hd; rfl
        · cases h
      · cases h
    · split at h
      · cases h
      · cases e : takeLine rest with
        | none => rw [e] at h; cases h
        | some p =>
          rw [e] at h
          simp only [Option.map_some, Option.some.injEq, Prod.mk.injEq] at h
          obtain ⟨rfl, rfl⟩ := h
          rw [takeLine_eq e]
          rfl

private theorem takeLine_app : ∀ {l : List UInt8} (r : List UInt8), (∀ x ∈ l, x ≠ 0x0D ∧ x ≠ 0x0A) →
    takeLine (l ++ Spec.crlf ++ r) = some (l, r)
  | [], r, _ => rfl
  | c :: l, r, h => by
    have hc := h c (by simp)
    have hc1 : (c == 0x0D) = false := by simpa using hc.1
    have hc2 : (c == 0x0A) = false := by simpa using hc.2
    simp only [List.cons_append]
    unfold takeLine
    rw [hc1, hc2]
    simp only [Bool.false_eq_true, ↓reduceIte]
    rw [takeLine_app r (fun x hx => h x (by simp [hx]))]
    rfl

private theorem parseFields_step (fuel : Nat) (bs : List UInt8) : parseFields (fuel+1) bs =
    (takeLine bs).bind (fun p => if p.1.isEmpty then some ([], p.2) else
      (parseField p.1).bind (fun f => (parseFields fuel p.2).bind (fun q => some (f :: q.1, q.2)))) :=
  rfl

private theorem tchar_line : ∀ x, isTchar x = true → x ≠ 0x0D ∧ x ≠ 0x0A :=
  uint8_forall (by decide +kernel)

private theorem ws_line : ∀ x, isWs x = true → x ≠ 0x0D ∧ x ≠ 0x0A :=
  uint8_forall (by decide +kernel)

private theorem vchar_line : ∀ x, (isVchar x || isWs x) = true → x ≠ 0x0D ∧ x ≠ 0x0A :=
  uint8_forall (by decide +kernel)

private theorem fieldLine_octets {f : Field} {l : List UInt8} (hv : Spec.FieldValid f)
    (hl : Spec.FieldLineText f l) : ∀ x ∈ l, x ≠ 0x0D ∧ x ≠ 0x0A := by
  obtain ⟨hn, hval⟩ := hv
  obtain ⟨w1, w2, h1, h2, rfl⟩ := hl
  rw [OWS_iff] at h1 h2
  have hfv := ((isFieldValue_FV _).1 ((isFieldValue_iff _).2 hval)).1
  intro x hx
  simp only [List.mem_append, List.mem_singleton] at hx
  rcases hx with (((hx | rfl) | hx) | hx) | hx
  · exact tchar_line x (token_tchar hn x hx)
  · decide
  · exact ws_line x (h1 x hx)
  · exact vchar_line x (hfv x hx)
  · exact ws_line x (h2 x hx)

theorem parseFields_iff (fuel : Nat) (bs : List UInt8) (fs : List Field) (r : List UInt8)
    (hfuel : bs.length < fuel) :
    parseFields fuel bs = some (fs, r) ↔
      (∀ f ∈ fs, Spec.FieldValid f) ∧ ∃ t, Spec.FieldsText fs t ∧ bs = t ++ r := by
  induction fuel generalizing bs fs r with
  | zero => omega
  | succ fuel ih =>
    rw [parseFields_step]
    constructor
    · intro h
      rw [Option.bind_eq_some_iff] at h
      obtain ⟨⟨line, rest⟩, hl, h⟩ := h
      have hbs := takeLine_eq hl
      simp only at h
      split at h
      · rename_i he
        simp only [Option.some.injEq, Prod.mk.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        rw [List.isEmpty_iff] at he
        subst he
        exact ⟨by simp, Spec.crlf, rfl, hbs⟩
      · rename_i he
        rw [Option.bind_eq_some_iff] at h
        obtain ⟨f, hf, h⟩ := h
        rw [Option.bind_eq_some_iff] at h
        obtain ⟨⟨fs', rest'⟩, hfs, h⟩ := h
        simp only [Option.some.injEq, Prod.mk.injEq] at h
        obtain ⟨rfl, rfl⟩ := h
        have hlen : rest.length < fuel := by
          rw [hbs] at hfuel; simp [Spec.crlf] at hfuel; omega
        obtain ⟨hv, t', ht', hrest⟩ := (ih rest fs' rest' hlen).1 hfs
        obtain ⟨hfv, hft⟩ := (parseField_iff line f).1 hf
        refine ⟨?_, line ++ Spec.crlf ++ t', ⟨line, t', hft, ht', rfl⟩, ?_⟩
        · intro g hg
          simp only [List.mem_cons] at hg
          rcases hg with rfl | hg
          · exact hfv
          · exact hv g hg
        · rw [hbs, hrest]; simp
    · rintro ⟨hv, t, ht, rfl⟩
      cases fs with
      | nil =>
        simp only [Spec.FieldsText] at ht
        subst ht
        have : takeLine (Spec.crlf ++ r) = some ([], r) := takeLine_app (l := []) r (by simp)
        rw [this]
        rfl
      | cons f fs' =>
        obtain ⟨l, t', hl, ht', rfl⟩ := ht
        have hfv : Spec.FieldValid f := hv f (by simp)
        have hoct := fieldLine_octets hfv hl
        have e : l ++ Spec.crlf ++ t' ++ r = l ++ Spec.crlf ++ (t' ++ r) := by simp
        rw [e, takeLine_app _ hoct]
        have hne : l.isEmpty = false := by
          obtain ⟨w1, w2, _, _, rfl⟩ := hl
          simp
        have hlen : (t' ++ r).length < fuel := by
          rw [e] at hfuel; simp [Spec.crlf] at hfuel ⊢; omega
        have hp : parseField l = some f := (parseField_iff l f).2 ⟨hfv, hl⟩
        have hfs : parseFields fuel (t' ++ r) = some (fs', r) :=
          (ih (t' ++ r) fs' r hlen).2 ⟨fun g hg => hv g (by simp [hg]), t', ht', rfl⟩
        simp only [Option.bind_some, hne, Bool.false_eq_true, ↓reduceIte, hp, hfs]

end Http.Proofs.Fields
