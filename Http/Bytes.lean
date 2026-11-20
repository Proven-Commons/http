import Http.Types

namespace Http

/-- The largest integer that fits in 64 bits. A chunk size above this is rejected. -/
def maxUInt64 : Nat := 2 ^ 64 - 1

def lowerByte (b : UInt8) : UInt8 :=
  if 65 ≤ b && b ≤ 90 then b + 32 else b

def mapBytes (f : UInt8 → UInt8) : List UInt8 → List UInt8
  | [] => []
  | b :: bs => f b :: mapBytes f bs

def lowerBytes (bs : List UInt8) : List UInt8 :=
  mapBytes lowerByte bs

def isOWS (b : UInt8) : Bool :=
  b == 32 || b == 9

def dropWhileBytes (p : UInt8 → Bool) : List UInt8 → List UInt8
  | [] => []
  | b :: bs => if p b then dropWhileBytes p bs else b :: bs

def revBytes : List UInt8 → List UInt8 → List UInt8
  | [], acc => acc
  | b :: bs, acc => revBytes bs (b :: acc)

def trimOWS (bs : List UInt8) : List UInt8 :=
  revBytes (dropWhileBytes isOWS (revBytes (dropWhileBytes isOWS bs) [])) []

def allBytes (p : UInt8 → Bool) : List UInt8 → Bool
  | [] => true
  | b :: bs => p b && allBytes p bs

def anyBytes (p : UInt8 → Bool) : List UInt8 → Bool
  | [] => false
  | b :: bs => p b || anyBytes p bs

def takeBytes : Nat → List UInt8 → List UInt8
  | 0, _ => []
  | _, [] => []
  | n + 1, b :: bs => b :: takeBytes n bs

def dropBytes : Nat → List UInt8 → List UInt8
  | 0, bs => bs
  | _, [] => []
  | n + 1, _ :: bs => dropBytes n bs

def takeWhileBytes (p : UInt8 → Bool) : List UInt8 → List UInt8
  | [] => []
  | b :: bs => if p b then b :: takeWhileBytes p bs else []

def splitByte (sep : UInt8) : List UInt8 → List (List UInt8)
  | [] => [[]]
  | b :: bs =>
    let parts := splitByte sep bs
    if b == sep then
      [] :: parts
    else
      match parts with
      | [] => [[b]]
      | p :: ps => (b :: p) :: ps

/-- Split at the first CRLF. A bare CR or a bare LF makes the split fail,
and neither byte is kept in the line. -/
def splitCRLF : List UInt8 → Option (List UInt8 × List UInt8)
  | [] => none
  | c :: bs =>
    if c = 0x0D then
      match bs with
      | [] => none
      | d :: rest => if d = 0x0A then some ([], rest) else none
    else if c = 0x0A then
      none
    else
      match splitCRLF bs with
      | none => none
      | some (line, rest) => some (c :: line, rest)

def noBareLineBreak (line : List UInt8) : Prop :=
  ∀ b, b ∈ line → b ≠ 0x0D ∧ b ≠ 0x0A

theorem splitCRLF_of_line (line rest : List UInt8) (h : noBareLineBreak line) :
    splitCRLF (line ++ [0x0D, 0x0A] ++ rest) = some (line, rest) := by
  induction line with
  | nil =>
    simp [splitCRLF]
  | cons c line ih =>
    have hc : c ≠ 0x0D ∧ c ≠ 0x0A := h c (by simp)
    have hline : noBareLineBreak line := fun b hb => h b (by simp [hb])
    have ih' := ih hline
    rcases hc with ⟨hcr, hlf⟩
    have ih'' : splitCRLF (line ++ 0x0D :: 0x0A :: rest) = some (line, rest) := by
      simpa [List.append_assoc] using ih'
    simp [splitCRLF, hcr, hlf, ih'']

theorem splitCRLF_sound_left (bs line rest : List UInt8)
    (h : splitCRLF bs = some (line, rest)) :
    noBareLineBreak line ∧ bs = line ++ [0x0D, 0x0A] ++ rest := by
  induction bs generalizing line rest with
  | nil =>
    simp [splitCRLF] at h
  | cons c bs ih =>
    by_cases hcr : c = 0x0D
    · subst hcr
      cases bs with
      | nil =>
        simp [splitCRLF] at h
      | cons d ds =>
        by_cases hlf : d = 0x0A
        · subst hlf
          simp [splitCRLF] at h
          rcases h with ⟨rfl, rfl⟩
          simp [noBareLineBreak]
        · simp [splitCRLF, hlf] at h
    · by_cases hlf : c = 0x0A
      · simp [splitCRLF, hlf] at h
      · simp only [splitCRLF, hcr, hlf] at h
        cases hsp : splitCRLF bs with
        | none =>
          simp [hsp] at h
        | some pair =>
          obtain ⟨line', rest'⟩ := pair
          simp [hsp] at h
          rcases h with ⟨rfl, rfl⟩
          obtain ⟨hn, heq⟩ := ih line' rest' hsp
          refine ⟨?_, ?_⟩
          · intro b hb
            simp at hb
            cases hb with
            | inl hb =>
              subst hb
              exact ⟨hcr, hlf⟩
            | inr hb =>
              exact hn b hb
          · simp [heq]

theorem splitCRLF_sound (bs line rest : List UInt8) :
    splitCRLF bs = some (line, rest) ↔
      noBareLineBreak line ∧ bs = line ++ [0x0D, 0x0A] ++ rest := by
  constructor
  · exact splitCRLF_sound_left bs line rest
  · intro h
    rcases h with ⟨hn, heq⟩
    subst heq
    exact splitCRLF_of_line line rest hn

theorem splitCRLF_prefix_free (bs line rest extra : List UInt8)
    (h : splitCRLF bs = some (line, rest)) :
    splitCRLF (bs ++ extra) = some (line, rest ++ extra) := by
  obtain ⟨hn, heq⟩ := splitCRLF_sound_left bs line rest h
  have h' := splitCRLF_of_line line (rest ++ extra) hn
  simpa [heq, List.append_assoc] using h'

def decVal (b : UInt8) : Option Nat :=
  if 48 ≤ b.toNat ∧ b.toNat ≤ 57 then some (b.toNat - 48) else none

def hexVal (b : UInt8) : Option Nat :=
  if 48 ≤ b.toNat ∧ b.toNat ≤ 57 then some (b.toNat - 48)
  else if 97 ≤ b.toNat ∧ b.toNat ≤ 102 then some (b.toNat - 87)
  else if 65 ≤ b.toNat ∧ b.toNat ≤ 70 then some (b.toNat - 55)
  else none

def parseAcc (base : Nat) (val : UInt8 → Option Nat) (acc : Nat) : List UInt8 → Option Nat
  | [] => if acc ≤ maxUInt64 then some acc else none
  | b :: bs =>
    match val b with
    | none => none
    | some d =>
      let n := acc * base + d
      if n ≤ maxUInt64 then parseAcc base val n bs else none

def parseDec (ds : List UInt8) : Option Nat :=
  match ds with
  | [] => none
  | _ => parseAcc 10 decVal 0 ds

def parseHex (ds : List UInt8) : Option Nat :=
  match ds with
  | [] => none
  | _ => parseAcc 16 hexVal 0 ds

def natToDecChars (n : Nat) : List UInt8 :=
  if n < 10 then [UInt8.ofNat (48 + n)]
  else natToDecChars (n / 10) ++ [UInt8.ofNat (48 + n % 10)]
termination_by n
decreasing_by
  apply Nat.div_lt_self
  · omega
  · decide

def nibble (d : Nat) : UInt8 :=
  if d < 10 then UInt8.ofNat (48 + d) else UInt8.ofNat (87 + d)

def natToHexLower (n : Nat) : List UInt8 :=
  let digit := nibble (n % 16)
  if n < 16 then [digit]
  else natToHexLower (n / 16) ++ [digit]
termination_by n
decreasing_by
  apply Nat.div_lt_self
  · omega
  · decide

def decDigits (n : Nat) : Nat :=
  if n < 10 then 1 else decDigits (n / 10) + 1
termination_by n
decreasing_by
  apply Nat.div_lt_self
  · omega
  · decide

def hexDigits (n : Nat) : Nat :=
  if n < 16 then 1 else hexDigits (n / 16) + 1
termination_by n
decreasing_by
  apply Nat.div_lt_self
  · omega
  · decide

theorem toNat_ofNat_small (n : Nat) (h : n < 256) : (UInt8.ofNat n).toNat = n := by
  simp [UInt8.ofNat, UInt8.toNat, Nat.mod_eq_of_lt h]

theorem decVal_digit (d : Nat) (h : d < 10) :
    decVal (UInt8.ofNat (48 + d)) = some d := by
  have hlt : 48 + d < 256 := by omega
  unfold decVal
  rw [toNat_ofNat_small _ hlt]
  have hlo : 48 ≤ 48 + d := Nat.le_add_right _ _
  have hhi : 48 + d ≤ 57 := by omega
  simp only [hlo, hhi, and_self, ite_true]
  exact congrArg some (Nat.add_sub_cancel_left 48 d)

theorem hexVal_digit (d : Nat) (h : d < 16) :
    hexVal (nibble d) = some d := by
  unfold nibble hexVal
  by_cases h10 : d < 10
  · have hlt : 48 + d < 256 := by omega
    simp only [h10, ite_true]
    rw [toNat_ofNat_small _ hlt]
    have hlo : 48 ≤ 48 + d := Nat.le_add_right _ _
    have hhi : 48 + d ≤ 57 := by omega
    simp only [hlo, hhi, and_self, ite_true]
    exact congrArg some (Nat.add_sub_cancel_left 48 d)
  · have hlt : 87 + d < 256 := by omega
    simp only [h10, ite_false]
    rw [toNat_ofNat_small _ hlt]
    have hnot : ¬(48 ≤ 87 + d ∧ 87 + d ≤ 57) := by omega
    have hlo : 97 ≤ 87 + d := by omega
    have hhi : 87 + d ≤ 102 := by omega
    simp only [hnot, ite_false, hlo, hhi, and_self, ite_true]
    exact congrArg some (Nat.add_sub_cancel_left 87 d)

theorem parseAcc_append (base : Nat) (val : UInt8 → Option Nat) (acc : Nat)
    (xs ys : List UInt8) (hacc : acc ≤ maxUInt64) :
    parseAcc base val acc (xs ++ ys) =
      match parseAcc base val acc xs with
      | none => none
      | some n => parseAcc base val n ys := by
  induction xs generalizing acc with
  | nil =>
    simp [parseAcc, hacc]
  | cons b xs ih =>
    simp only [List.cons_append, parseAcc]
    cases hval : val b with
    | none =>
      simp [hval]
    | some d =>
      simp only [hval]
      by_cases hn : acc * base + d ≤ maxUInt64
      · simp only [hn, ite_true]
        have hacc' : acc * base + d ≤ maxUInt64 := hn
        simpa using ih (acc * base + d) hacc'
      · simp [hn]

theorem parseAcc_dec (acc n : Nat) (hacc : acc ≤ maxUInt64)
    (h : acc * 10 ^ decDigits n + n ≤ maxUInt64) :
    parseAcc 10 decVal acc (natToDecChars n) = some (acc * 10 ^ decDigits n + n) := by
  induction n using Nat.strongRecOn generalizing acc with
  | ind n ih =>
    by_cases h10 : n < 10
    · have hchars : natToDecChars n = [UInt8.ofNat (48 + n)] := by
        rw [natToDecChars]
        split
        · rfl
        · contradiction
      have hdig : decDigits n = 1 := by
        rw [decDigits]
        split
        · rfl
        · contradiction
      rw [hdig, Nat.pow_one] at h
      rw [hchars, hdig, Nat.pow_one]
      unfold parseAcc
      rw [decVal_digit n h10]
      simp only [h, ite_true]
      unfold parseAcc
      simp only [h, ite_true]
    · have hdiv : n / 10 < n := Nat.div_lt_self (by omega) (by decide)
      have hdigits : decDigits n = decDigits (n / 10) + 1 := by
        rw [decDigits]
        split
        · contradiction
        · rfl
      have hpow : 10 ^ decDigits n = 10 ^ decDigits (n / 10) * 10 := by
        rw [hdigits, Nat.pow_succ, Nat.mul_comm]
      have hassoc : acc * (10 ^ decDigits (n / 10) * 10) = acc * 10 ^ decDigits (n / 10) * 10 := by
        simp [Nat.mul_assoc]
      have hbound : acc * 10 ^ decDigits (n / 10) + n / 10 ≤ maxUInt64 := by
        have hle : acc * 10 ^ decDigits (n / 10) + n / 10 ≤ acc * 10 ^ decDigits n + n := by
          rw [hpow, hassoc]
          have hmul : acc * 10 ^ decDigits (n / 10) ≤ acc * 10 ^ decDigits (n / 10) * 10 :=
            Nat.le_mul_of_pos_right _ (by decide)
          have hdivle : n / 10 ≤ n := Nat.div_le_self _ _
          omega
        exact Nat.le_trans hle h
      have ih' := ih (n / 10) hdiv acc hacc hbound
      have hdigit : n % 10 < 10 := Nat.mod_lt _ (by decide)
      have hd := decVal_digit (n % 10) hdigit
      have hstep : (acc * 10 ^ decDigits (n / 10) + n / 10) * 10 + n % 10 =
          acc * 10 ^ decDigits n + n := by
        have hdivmod : n / 10 * 10 + n % 10 = n := by
          simpa [Nat.mul_comm] using Nat.div_add_mod n 10
        have hmul : (acc * 10 ^ decDigits (n / 10) + n / 10) * 10 =
            acc * 10 ^ decDigits (n / 10) * 10 + n / 10 * 10 := by
          rw [Nat.add_mul]
        rw [hmul, Nat.add_assoc, hdivmod, hpow, hassoc]
      have hsum : (acc * 10 ^ decDigits (n / 10) + n / 10) * 10 + n % 10 ≤ maxUInt64 := by
        rw [hstep]; exact h
      have hchars : natToDecChars n =
          natToDecChars (n / 10) ++ [UInt8.ofNat (48 + n % 10)] := by
        rw [natToDecChars]
        split
        · contradiction
        · rfl
      have happ := parseAcc_append 10 decVal acc (natToDecChars (n / 10))
        [UInt8.ofNat (48 + n % 10)] hacc
      rw [hchars, happ, ih']
      unfold parseAcc
      rw [hd]
      simp only [hsum, ite_true, hstep]
      unfold parseAcc
      simp only [h, ite_true]

theorem natToDecChars_ne_nil (n : Nat) : natToDecChars n ≠ [] := by
  rw [natToDecChars]
  split
  · simp
  · simp [List.append_eq_nil_iff]

theorem parseDec_printDec (n : Nat) (h : n ≤ maxUInt64) :
    parseDec (natToDecChars n) = some n := by
  have hparse := parseAcc_dec 0 n (by decide) (by simpa using h)
  have hne := natToDecChars_ne_nil n
  have hzero : 0 * 10 ^ decDigits n + n = n := by simp
  rw [hzero] at hparse
  cases hchars : natToDecChars n with
  | nil => exact absurd hchars hne
  | cons b bs =>
    rw [hchars] at hparse
    unfold parseDec
    simp only [hchars]
    exact hparse

theorem parseAcc_hex (acc n : Nat) (hacc : acc ≤ maxUInt64)
    (h : acc * 16 ^ hexDigits n + n ≤ maxUInt64) :
    parseAcc 16 hexVal acc (natToHexLower n) = some (acc * 16 ^ hexDigits n + n) := by
  induction n using Nat.strongRecOn generalizing acc with
  | ind n ih =>
    by_cases h16 : n < 16
    · have hmod : n % 16 = n := Nat.mod_eq_of_lt h16
      have hchars : natToHexLower n = [nibble n] := by
        rw [natToHexLower]
        simp [h16, hmod]
      have hdig : hexDigits n = 1 := by
        rw [hexDigits]
        simp [h16]
      rw [hdig, Nat.pow_one] at h
      rw [hchars, hdig, Nat.pow_one]
      unfold parseAcc
      rw [hexVal_digit n h16]
      simp only [h, ite_true]
      unfold parseAcc
      simp only [h, ite_true]
    · have hdiv : n / 16 < n := Nat.div_lt_self (by omega) (by decide)
      have hdigits : hexDigits n = hexDigits (n / 16) + 1 := by
        rw [hexDigits]
        simp [h16]
      have hpow : 16 ^ hexDigits n = 16 ^ hexDigits (n / 16) * 16 := by
        rw [hdigits, Nat.pow_succ, Nat.mul_comm]
      have hassoc : acc * (16 ^ hexDigits (n / 16) * 16) = acc * 16 ^ hexDigits (n / 16) * 16 := by
        simp [Nat.mul_assoc]
      have hbound : acc * 16 ^ hexDigits (n / 16) + n / 16 ≤ maxUInt64 := by
        have hle : acc * 16 ^ hexDigits (n / 16) + n / 16 ≤ acc * 16 ^ hexDigits n + n := by
          rw [hpow, hassoc]
          have hmul : acc * 16 ^ hexDigits (n / 16) ≤ acc * 16 ^ hexDigits (n / 16) * 16 :=
            Nat.le_mul_of_pos_right _ (by decide)
          have hdivle : n / 16 ≤ n := Nat.div_le_self _ _
          omega
        exact Nat.le_trans hle h
      have ih' := ih (n / 16) hdiv acc hacc hbound
      have hdigit : n % 16 < 16 := Nat.mod_lt _ (by decide)
      have hd := hexVal_digit (n % 16) hdigit
      have hstep : (acc * 16 ^ hexDigits (n / 16) + n / 16) * 16 + n % 16 =
          acc * 16 ^ hexDigits n + n := by
        have hdivmod : n / 16 * 16 + n % 16 = n := by
          simpa [Nat.mul_comm] using Nat.div_add_mod n 16
        have hmul : (acc * 16 ^ hexDigits (n / 16) + n / 16) * 16 =
            acc * 16 ^ hexDigits (n / 16) * 16 + n / 16 * 16 := by
          rw [Nat.add_mul]
        rw [hmul, Nat.add_assoc, hdivmod, hpow, hassoc]
      have hsum : (acc * 16 ^ hexDigits (n / 16) + n / 16) * 16 + n % 16 ≤ maxUInt64 := by
        rw [hstep]; exact h
      have hchars : natToHexLower n = natToHexLower (n / 16) ++ [nibble (n % 16)] := by
        rw [natToHexLower]
        simp [h16]
      have happ := parseAcc_append 16 hexVal acc (natToHexLower (n / 16)) [nibble (n % 16)] hacc
      rw [hchars, happ, ih']
      unfold parseAcc
      rw [hd]
      simp only [hsum, ite_true, hstep]
      unfold parseAcc
      simp only [h, ite_true]

theorem natToHexLower_ne_nil (n : Nat) : natToHexLower n ≠ [] := by
  rw [natToHexLower]
  by_cases h16 : n < 16
  · simp [h16]
  · simp [h16, List.append_eq_nil_iff]

theorem parseHex_printHex (n : Nat) (h : n ≤ maxUInt64) :
    parseHex (natToHexLower n) = some n := by
  have hparse := parseAcc_hex 0 n (by decide) (by simpa using h)
  have hne := natToHexLower_ne_nil n
  have hzero : 0 * 16 ^ hexDigits n + n = n := by simp
  rw [hzero] at hparse
  cases hchars : natToHexLower n with
  | nil => exact absurd hchars hne
  | cons b bs =>
    rw [hchars] at hparse
    unfold parseHex
    simp only [hchars]
    exact hparse

end Http
