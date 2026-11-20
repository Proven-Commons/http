import Http.Parse
import Http.Spec.Defs

namespace Http

theorem beq_eq_false {a b : List UInt8} (h : (a == b) = false) : a ≠ b := by
  intro heq
  simp [heq] at h

theorem beq_eq_true {a b : List UInt8} (h : (a == b) = true) : a = b := by
  simpa using h

theorem clHeaders_absent (hdrs : List Header) :
    clHeaders hdrs = [] ↔ ∀ hdr, hdr ∈ hdrs → lowerBytes hdr.name ≠ clNameLower := by
  induction hdrs with
  | nil => simp [clHeaders]
  | cons h hs ih =>
    constructor
    · intro hempty hdr hmem
      cases hcmp : lowerBytes h.name == clNameLower
      · simp [clHeaders, hcmp] at hempty
        simp at hmem
        cases hmem with
        | inl he =>
          subst he
          exact beq_eq_false hcmp
        | inr hmem =>
          exact (ih.mp hempty) hdr hmem
      · simp [clHeaders, hcmp] at hempty
    · intro hall
      cases hcmp : lowerBytes h.name == clNameLower
      · simp [clHeaders, hcmp]
        exact ih.mpr (fun hdr hmem => hall hdr (by simp [List.mem_cons, hmem]))
      · exact absurd (beq_eq_true hcmp) (hall h (by simp))

theorem mem_clHeaders (hdrs : List Header) (h : Header) :
    h ∈ clHeaders hdrs → h ∈ hdrs ∧ lowerBytes h.name = clNameLower := by
  induction hdrs with
  | nil => simp [clHeaders]
  | cons a as ih =>
    cases hcmp : lowerBytes a.name == clNameLower
    · simp [clHeaders, hcmp]
      intro hm
      rcases ih hm with ⟨hm, heq⟩
      exact ⟨by simp [List.mem_cons, hm], heq⟩
    · simp [clHeaders, hcmp]
      intro hm
      rcases hm with rfl | hm
      · exact ⟨by simp, beq_eq_true hcmp⟩
      · rcases ih hm with ⟨hm, heq⟩
        exact ⟨by simp [List.mem_cons, hm], heq⟩

theorem teValues_absent (hdrs : List Header) :
    teValues hdrs = [] ↔ ∀ hdr, hdr ∈ hdrs → lowerBytes hdr.name ≠ teNameLower := by
  induction hdrs with
  | nil => simp [teValues]
  | cons h hs ih =>
    constructor
    · intro hempty hdr hmem
      cases hcmp : lowerBytes h.name == teNameLower
      · simp [teValues, hcmp] at hempty
        simp [List.mem_cons] at hmem
        cases hmem with
        | inl he =>
          subst he
          exact beq_eq_false hcmp
        | inr hmem =>
          exact (ih.mp hempty) hdr hmem
      · simp [teValues, hcmp] at hempty
    · intro hall
      cases hcmp : lowerBytes h.name == teNameLower
      · simp [teValues, hcmp]
        exact ih.mpr (fun hdr hmem => hall hdr (by simp [List.mem_cons, hmem]))
      · exact absurd (beq_eq_true hcmp) (hall h (by simp))

theorem clState_absent (hdrs : List Header) :
    clState hdrs = .absent ↔ ∀ hdr, hdr ∈ hdrs → lowerBytes hdr.name ≠ clNameLower := by
  unfold clState
  cases hcs : clHeaders hdrs with
  | nil =>
    simp
    exact (clHeaders_absent hdrs).mp hcs
  | cons h hs =>
    constructor
    · intro habs
      cases hs with
      | nil =>
        cases hdig : digits h.value
        · simp [hdig] at habs
        · cases hdec : parseDec h.value <;> simp [hdig, hdec] at habs
      | cons => simp [hcs] at habs
    · intro hall
      have hm : h ∈ clHeaders hdrs := by simp [hcs]
      rcases mem_clHeaders hdrs h hm with ⟨hmem, heq⟩
      exact absurd heq (hall h hmem)

theorem no_te (hdrs : List Header) (hte : ∃ hdr, hdr ∈ hdrs ∧ lowerBytes hdr.name = teNameLower) :
    teValues hdrs ≠ [] := by
  intro hempty
  rcases hte with ⟨hdr, hm, heq⟩
  exact (teValues_absent hdrs).mp hempty hdr hm heq

theorem no_cl (hdrs : List Header) (hcl : ∃ hdr, hdr ∈ hdrs ∧ lowerBytes hdr.name = clNameLower) :
    clState hdrs ≠ .absent := by
  intro habs
  rcases hcl with ⟨hdr, hm, heq⟩
  exact (clState_absent hdrs).mp habs hdr hm heq

theorem determineFraming_rejects_nonfinal_chunked (v : Version) (hdrs : List Header)
    (h : determineFraming v hdrs = some .chunked) :
    v = .http11 ∧ (∀ hdr, hdr ∈ hdrs → lowerBytes hdr.name ≠ clNameLower) ∧
      normalizedCodings hdrs = some [chunkedToken] := by
  unfold determineFraming at h
  cases hcodes : normalizedCodings hdrs with
  | none => simp [hcodes] at h
  | some cs =>
    cases hcl : clState hdrs with
    | bad => simp [hcodes, hcl] at h
    | ok n => simp [hcodes, hcl] at h
    | absent =>
      cases cs with
      | nil => simp [hcodes, hcl] at h
      | cons c rest =>
        cases rest with
        | nil =>
          cases hv : decide (v = .http11) <;> cases hc : decide (c = chunkedToken) <;>
            simp [hcodes, hcl, hv, hc] at h
          refine ⟨?_, (clState_absent hdrs).mp hcl, ?_⟩
          · simpa using hv
          · simp [hcodes]
            simpa using hc
        | cons => simp [hcodes, hcl] at h

theorem chunked_requires_http11_without_cl (v : Version) (hdrs : List Header)
    (h : determineFraming v hdrs = some .chunked) :
    v = .http11 ∧ ∀ hdr, hdr ∈ hdrs → lowerBytes hdr.name ≠ clNameLower := by
  rcases determineFraming_rejects_nonfinal_chunked v hdrs h with ⟨hv, hcl, _⟩
  exact ⟨hv, hcl⟩

theorem determineFraming_disjoint (v : Version) (hdrs : List Header) (f1 f2 : Framing)
    (h1 : determineFraming v hdrs = some f1) (h2 : determineFraming v hdrs = some f2) :
    f1 = f2 := by
  exact Option.some.inj (h1.symm.trans h2)

theorem determineFraming_rejects_cl_and_te (v : Version) (hdrs : List Header)
    (hte : ∃ h, h ∈ hdrs ∧ lowerBytes h.name = teNameLower)
    (hcl : ∃ h, h ∈ hdrs ∧ lowerBytes h.name = clNameLower) :
    determineFraming v hdrs = none := by
  have hte' := no_te hdrs hte
  have hcl' := no_cl hdrs hcl
  unfold determineFraming
  cases hcodes : normalizedCodings hdrs with
  | none => rfl
  | some cs =>
    cases hst : clState hdrs with
    | bad => rfl
    | ok n => simp [hst, hte']
    | absent => exact absurd hst hcl'

theorem determineFraming_rejects_http10_te (hdrs : List Header)
    (hte : ∃ h, h ∈ hdrs ∧ lowerBytes h.name = teNameLower) :
    determineFraming .http10 hdrs = none := by
  have hte' := no_te hdrs hte
  unfold determineFraming
  cases hcodes : normalizedCodings hdrs with
  | none => rfl
  | some cs =>
    cases hst : clState hdrs with
    | bad => rfl
    | ok n => simp [hst, hte']
    | absent =>
      cases cs with
      | nil => simp [hst, hte']
      | cons c rest =>
        cases rest <;> simp

theorem determineFraming_rejects_bad_te (v : Version) (hdrs : List Header)
    (hte : ∃ h, h ∈ hdrs ∧ lowerBytes h.name = teNameLower)
    (hbad : normalizedCodings hdrs ≠ some [chunkedToken]) :
    determineFraming v hdrs = none := by
  have hte' := no_te hdrs hte
  unfold determineFraming
  cases hcodes : normalizedCodings hdrs with
  | none => rfl
  | some cs =>
    have hcs : cs ≠ [chunkedToken] := by
      intro heq
      exact hbad (by simp [hcodes, heq])
    cases hst : clState hdrs with
    | bad => rfl
    | ok n => simp [hst, hte']
    | absent =>
      cases cs with
      | nil => simp [hst, hte']
      | cons c rest =>
        cases rest with
        | cons => simp
        | nil =>
          have hc : c ≠ chunkedToken := by
            intro hc
            exact hcs (by simp [hc])
          simp [hc]

theorem takeBytes_append (bs rest : List UInt8) :
    takeBytes bs.length (bs ++ rest) = bs := by
  induction bs with
  | nil => simp [takeBytes]
  | cons b bs ih => simp [takeBytes, List.length_cons, ih]

theorem dropBytes_append (bs rest : List UInt8) :
    dropBytes bs.length (bs ++ rest) = rest := by
  induction bs with
  | nil => simp [dropBytes]
  | cons b bs ih => simp [dropBytes, List.length_cons, ih]

theorem allBytes_append (p : UInt8 → Bool) (xs ys : List UInt8) :
    allBytes p (xs ++ ys) = (allBytes p xs && allBytes p ys) := by
  induction xs with
  | nil => simp [allBytes]
  | cons x xs ih => simp [allBytes, ih, Bool.and_assoc]

theorem hexDigit_ok (d : Nat) (hd : d < 16) :
    isHex (hexDigit d) = true ∧ hexDigit d ≠ 13 ∧ hexDigit d ≠ 10 := by
  revert hd
  match d with
  | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 =>
    intro _
    decide
  | n + 16 =>
    intro h
    omega

theorem allBytes_hex (n : Nat) : allBytes isHex (natToHexLower n) = true := by
  induction n using Nat.strongRecOn with
  | ind n ih =>
    by_cases h16 : n < 16
    · have hmod : n % 16 = n := Nat.mod_eq_of_lt h16
      simp [natToHexLower, h16, hmod, allBytes, (hexDigit_ok n h16).1]
    · have hdiv : n / 16 < n := Nat.div_lt_self (by omega) (by decide)
      have hdigit : n % 16 < 16 := Nat.mod_lt _ (by decide)
      rw [natToHexLower]
      simp only [h16, ite_false]
      rw [allBytes_append]
      simp [allBytes, ih (n / 16) hdiv, (hexDigit_ok _ hdigit).1]

theorem natToHex_no_break (n : Nat) : noBareLineBreak (natToHexLower n) := by
  induction n using Nat.strongRecOn with
  | ind n ih =>
    by_cases h16 : n < 16
    · have hmod : n % 16 = n := Nat.mod_eq_of_lt h16
      simp [natToHexLower, h16, hmod, noBareLineBreak]
      exact ⟨(hexDigit_ok n h16).2.1, (hexDigit_ok n h16).2.2⟩
    · have hdiv : n / 16 < n := Nat.div_lt_self (by omega) (by decide)
      have hdigit : n % 16 < 16 := Nat.mod_lt _ (by decide)
      intro b hb
      rw [natToHexLower] at hb
      simp only [h16, ite_false, List.mem_append] at hb
      cases hb with
      | inl hb => exact ih _ hdiv b hb
      | inr hb =>
        simp at hb
        subst hb
        exact ⟨(hexDigit_ok _ hdigit).2.1, (hexDigit_ok _ hdigit).2.2⟩

theorem takeWhile_of_all (p : UInt8 → Bool) (bs : List UInt8) (h : allBytes p bs = true) :
    takeWhileBytes p bs = bs := by
  induction bs with
  | nil => simp [takeWhileBytes]
  | cons b bs ih =>
    simp [allBytes] at h
    rcases h with ⟨hb, hbs⟩
    simp [takeWhileBytes, hb, ih hbs]

theorem parseChunkSize_hex (n : Nat) (h : n ≤ maxUInt64) :
    parseChunkSize (natToHexLower n) = some n := by
  have htake := takeWhile_of_all isHex (natToHexLower n) (allBytes_hex n)
  have hdrop : dropBytes (natToHexLower n).length (natToHexLower n) = [] := by
    simpa using dropBytes_append (natToHexLower n) []
  have hne := natToHexLower_ne_nil n
  simp [parseChunkSize, htake, hdrop, parseHex_printHex n h, parseExt, hne]

theorem decode_last (fuel : Nat) (acc : List UInt8) (h : 0 < fuel) :
    decodeLoop fuel acc ([48] ++ crlf ++ crlf) = some (acc, [], []) := by
  cases fuel with
  | zero => omega
  | succ fuel =>
    simp [decodeLoop, crlf, splitCRLF, parseChunkSize, parseHex, parseAcc, hexVal, parseExt, parseTrailers,
      takeWhileBytes, dropBytes, isHex, isDigit]

theorem decodeChunked_encodeChunked (body : List UInt8) (h : body.length ≤ maxUInt64) :
    decodeChunked (encodeChunked body) = some (body, [], []) := by
  cases body with
  | nil =>
    simp [encodeChunked, decodeChunked, decodeLoop, crlf, splitCRLF, parseChunkSize, parseHex, parseAcc, hexVal,
      parseExt, parseTrailers, takeWhileBytes, dropBytes, isHex, isDigit]
  | cons b bs =>
    have hline := natToHex_no_break (b :: bs).length
    have hhex := parseChunkSize_hex (b :: bs).length h
    have hsplit := splitCRLF_of_line (natToHexLower (b :: bs).length)
      ((b :: bs) ++ crlf ++ [48] ++ crlf ++ crlf) hline
    have htake := takeBytes_append (b :: bs) (crlf ++ [48] ++ crlf ++ crlf)
    have hdrop := dropBytes_append (b :: bs) (crlf ++ [48] ++ crlf ++ crlf)
    simp [crlf, List.append_assoc, List.cons_append, List.length_cons] at hsplit htake hdrop hhex
    simp [encodeChunked, decodeChunked, List.isEmpty, crlf, decodeLoop, hsplit]
    rw [hhex]
    simp [List.length_cons, List.length_append]
    rw [hdrop, htake]
    simp [crlf, splitCRLF, parseChunkSize, parseHex, parseAcc, hexVal, parseExt, parseTrailers,
      takeWhileBytes, dropBytes, isHex, isDigit, decode_last]

theorem tchar_ne (b : UInt8) (h : isTchar b = true) : b ≠ 13 ∧ b ≠ 10 ∧ b ≠ 32 ∧ b ≠ 58 := by
  refine ⟨?_, ?_, ?_, ?_⟩ <;> intro hb <;> subst hb <;> simp [isTchar, isAlpha, isDigit] at h

theorem vchar_ne (b : UInt8) (h : isVChar b = true) : b ≠ 13 ∧ b ≠ 10 ∧ b ≠ 32 := by
  refine ⟨?_, ?_, ?_⟩ <;> intro hb <;> subst hb <;> simp [isVChar] at h

theorem ne_beq_u8 {a b : UInt8} (h : a ≠ b) : (a == b) = false := by
  cases hcmp : a == b
  · rfl
  · simp [beq_iff_eq] at hcmp
    exact absurd hcmp h

theorem noBare_all (p : UInt8 → Bool) (bs : List UInt8)
    (hp : ∀ b, p b = true → b ≠ 13 ∧ b ≠ 10) (h : allBytes p bs = true) :
    noBareLineBreak bs := by
  induction bs with
  | nil => simp [noBareLineBreak]
  | cons b bs ih =>
    simp [allBytes] at h
    rcases h with ⟨hb, hbs⟩
    intro x hx
    simp at hx
    rcases hx with rfl | hx
    · exact hp x hb
    · exact ih hbs x hx

theorem splitByte_no (sep : UInt8) (bs : List UInt8) (h : ∀ b ∈ bs, (b == sep) = false) :
    splitByte sep bs = [bs] := by
  induction bs with
  | nil => simp [splitByte]
  | cons b bs ih =>
    have hb := h b (by simp)
    have hbs : ∀ x ∈ bs, (x == sep) = false := fun x hx => h x (by simp [hx])
    simp [splitByte, ih hbs, hb]

theorem splitByte_sep (sep : UInt8) (l r : List UInt8) (h : ∀ b ∈ l, (b == sep) = false) :
    splitByte sep (l ++ sep :: r) = l :: splitByte sep r := by
  induction l with
  | nil => simp [splitByte]
  | cons b l ih =>
    have hb := h b (by simp)
    have hl : ∀ x ∈ l, (x == sep) = false := fun x hx => h x (by simp [hx])
    simp [splitByte, hb, ih hl]

theorem version_no_sp (v : Version) : ∀ b ∈ versionBytes v, (b == 32) = false ∧ (b == 13) = false ∧
    (b == 10) = false := by
  cases v <;> intro b hb <;> simp [versionBytes] at hb <;>
    rcases hb with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> decide

theorem parseVersion_bytes (v : Version) : parseVersion (versionBytes v) = some v := by
  cases v <;> simp [parseVersion, versionBytes, takeBytes, List.length, List.getLast?]

theorem all_mem (p : UInt8 → Bool) (bs : List UInt8) (b : UInt8)
    (h : allBytes p bs = true) (hb : b ∈ bs) : p b = true := by
  induction bs with
  | nil => simp at hb
  | cons c cs ih =>
    simp [allBytes] at h
    simp at hb
    cases hb with
    | inl hb =>
      subst hb
      exact h.1
    | inr hb =>
      exact ih h.2 hb

theorem bare_all (bs : List UInt8) (h : bareToken bs = true) :
    allBytes isTchar bs = true ∧ bs ≠ [] := by
  cases bs with
  | nil => simp [bareToken] at h
  | cons b bs =>
    simp [bareToken] at h
    exact ⟨h, by simp⟩

theorem parseRequestLine_render (method target : List UInt8) (v : Version)
    (hm : bareToken method = true) (ht : allBytes isVChar target = true) (hne : target ≠ []) :
    parseRequestLine (method ++ [32] ++ target ++ [32] ++ versionBytes v) =
      some (method, target, v) := by
  have hmsp : ∀ b ∈ method, (b == 32) = false := fun b hb =>
    ne_beq_u8 (tchar_ne b (all_mem isTchar method b (bare_all method hm).1 hb)).2.2.1
  have htsp : ∀ b ∈ target, (b == 32) = false := fun b hb =>
    ne_beq_u8 (vchar_ne b (all_mem isVChar target b ht hb)).2.2
  have hvsp : ∀ b ∈ versionBytes v, (b == 32) = false := fun b hb => (version_no_sp v b hb).1
  have hmethod := splitByte_sep 32 method (target ++ 32 :: versionBytes v) hmsp
  have htarget := splitByte_sep 32 target (versionBytes v) htsp
  have hversion := splitByte_no 32 (versionBytes v) hvsp
  unfold parseRequestLine
  rw [show method ++ [32] ++ target ++ [32] ++ versionBytes v =
      method ++ 32 :: (target ++ 32 :: versionBytes v) by simp [List.append_assoc, List.singleton_append]]
  rw [hmethod, htarget, hversion]
  simp [parseVersion_bytes, hm, hne, ht, vchars]

theorem splitFirst_sep (sep : UInt8) (l r : List UInt8) (h : ∀ b ∈ l, (b == sep) = false) :
    splitFirst sep (l ++ sep :: r) = some (l, r) := by
  induction l with
  | nil => simp [splitFirst]
  | cons b l ih =>
    have hb := h b (by simp)
    have hl : ∀ x ∈ l, (x == sep) = false := fun x hx => h x (by simp [hx])
    simp [splitFirst, hb, ih hl]

theorem dropWhile_stop (b : UInt8) (bs : List UInt8) (h : isOWS b = false) :
    dropWhileBytes isOWS (b :: bs) = b :: bs := by
  simp [dropWhileBytes, h]

theorem rev_cons (b : UInt8) (bs acc : List UInt8) :
    revBytes (b :: bs) acc = revBytes bs (b :: acc) := by
  simp [revBytes]

theorem rev_append (bs acc : List UInt8) :
    revBytes bs acc = revBytes bs [] ++ acc := by
  induction bs generalizing acc with
  | nil => simp [revBytes]
  | cons b bs ih =>
    simp [revBytes, ih (b :: acc), ih [b], List.append_assoc]

theorem rev_snoc (xs : List UInt8) (b : UInt8) :
    revBytes (xs ++ [b]) [] = b :: revBytes xs [] := by
  induction xs with
  | nil => simp [revBytes]
  | cons c xs ih =>
    rw [List.cons_append, revBytes, rev_append, ih, revBytes, rev_append, List.cons_append,
      List.append_nil, ← rev_append]

theorem rev_rev (bs : List UInt8) : revBytes (revBytes bs []) [] = bs := by
  induction bs with
  | nil => simp [revBytes]
  | cons b bs ih =>
    rw [revBytes, rev_append bs [b], rev_snoc, ih]

theorem not_ows (b : UInt8) (h : !isOWS b = true) : isOWS b = false := by
  simpa using h

theorem dropWhile_len (bs : List UInt8) :
    (dropWhileBytes isOWS bs).length ≤ bs.length := by
  induction bs with
  | nil => simp [dropWhileBytes]
  | cons b bs ih =>
    simp [dropWhileBytes]
    split
    · exact Nat.le_trans ih (Nat.le_succ _)
    · simp

theorem dropWhile_head (b : UInt8) (bs : List UInt8)
    (h : dropWhileBytes isOWS (b :: bs) = b :: bs) : isOWS b = false := by
  cases hO : isOWS b with
  | false => rfl
  | true =>
    simp [dropWhileBytes, hO] at h
    have hlen := dropWhile_len bs
    rw [h] at hlen
    simp at hlen
    omega

theorem dropWhile_append_stop (xs ys : List UInt8)
    (h : dropWhileBytes isOWS xs = xs) (hne : xs ≠ []) :
    dropWhileBytes isOWS (xs ++ ys) = xs ++ ys := by
  cases xs with
  | nil => simp at hne
  | cons b bs =>
    have hb := dropWhile_head b bs h
    simp [dropWhileBytes, hb]

theorem dropWhile_rev_noTrail (bs : List UInt8) (h : noTrail bs = true) :
    dropWhileBytes isOWS (revBytes bs []) = revBytes bs [] := by
  induction bs with
  | nil => simp [revBytes, dropWhileBytes]
  | cons b bs ih =>
    cases bs with
    | nil =>
      simp [noTrail, revBytes, dropWhileBytes, not_ows b h]
    | cons c cs =>
      simp [noTrail] at h
      have ih' := ih h
      have hne : revBytes (c :: cs) [] ≠ [] := by
        rw [revBytes, rev_append]
        intro hempty
        simp [List.append_eq_nil_iff] at hempty
      rw [revBytes, rev_append]
      exact dropWhile_append_stop _ _ ih' hne

theorem trim_canonical (v : List UInt8) (h : canonicalValue v = true) : trimOWS v = v := by
  cases v with
  | nil => simp [trimOWS, dropWhileBytes, revBytes, canonicalValue]
  | cons b bs =>
    simp [canonicalValue] at h
    have hb : isOWS b = false := h.1.1
    have htrail : noTrail (b :: bs) = true := h.1.2
    simp [trimOWS, dropWhile_stop b bs hb, dropWhile_rev_noTrail (b :: bs) htrail, rev_rev]

theorem trim_space (v : List UInt8) (h : canonicalValue v = true) : trimOWS (32 :: v) = v := by
  have h32 : isOWS 32 = true := by decide
  cases v with
  | nil => simp [trimOWS, dropWhileBytes, revBytes, h32]
  | cons b bs =>
    simp [canonicalValue] at h
    have hb : isOWS b = false := h.1.1
    have hfront : dropWhileBytes isOWS (32 :: b :: bs) = b :: bs := by
      simp only [dropWhileBytes, h32, ite_true]
      exact dropWhile_stop b bs hb
    simp [trimOWS, hfront, dropWhile_rev_noTrail (b :: bs) h.1.2, rev_rev]

theorem field_ne (b : UInt8) (h : isFieldByte b = true) : b ≠ 13 ∧ b ≠ 10 := by
  refine ⟨?_, ?_⟩ <;> intro hb <;> subst hb <;> simp [isFieldByte, isVChar] at h

theorem tchar_ne_htab (b : UInt8) (h : isTchar b = true) : b ≠ 9 := by
  intro hb
  subst hb
  simp [isTchar, isAlpha, isDigit] at h

theorem canonical_bytes (v : List UInt8) (h : canonicalValue v = true) :
    allBytes isFieldByte v = true := by
  cases v with
  | nil => simp [allBytes]
  | cons b bs =>
    simp [canonicalValue] at h
    exact h.2

theorem noBare_append (xs ys : List UInt8) (hx : noBareLineBreak xs) (hy : noBareLineBreak ys) :
    noBareLineBreak (xs ++ ys) := by
  intro b hb
  simp [List.mem_append] at hb
  cases hb with
  | inl hb => exact hx b hb
  | inr hb => exact hy b hb

theorem noBare_pair (x y : UInt8) (hx : x ≠ 13 ∧ x ≠ 10) (hy : y ≠ 13 ∧ y ≠ 10) :
    noBareLineBreak [x, y] := by
  intro b hb
  simp at hb
  rcases hb with rfl | rfl
  · exact hx
  · exact hy

theorem field_line_noBare (name value : List UInt8) (hn : allBytes isTchar name = true)
    (hv : allBytes isFieldByte value = true) :
    noBareLineBreak (name ++ [58, 32] ++ value) := by
  apply noBare_append
  · apply noBare_append
    · exact noBare_all isTchar name (fun b hb =>
        let h := tchar_ne b hb
        ⟨h.1, h.2.1⟩) hn
    · exact noBare_pair 58 32 (by decide) (by decide)
  · exact noBare_all isFieldByte value field_ne hv

theorem skip_cons (b : UInt8) (bs : List UInt8) (h : b ≠ 13) : skipEmpty (b :: bs) = b :: bs := by
  unfold skipEmpty
  split
  · rename_i heq
    simp at heq
    exact absurd heq.1 h
  · rfl

theorem parseField_render (h : Header) (hc : canonicalHeader h = true) :
    parseField (h.name ++ [58, 32] ++ h.value) = some h := by
  have hn : bareToken h.name = true := by
    simp [canonicalHeader] at hc
    exact hc.1
  have hv : canonicalValue h.value = true := by
    simp [canonicalHeader] at hc
    exact hc.2
  have hall := (bare_all h.name hn).1
  have hne := (bare_all h.name hn).2
  have hsplit := splitFirst_sep 58 h.name (32 :: h.value)
    (fun b hb => ne_beq_u8 (tchar_ne b (all_mem isTchar h.name b hall hb)).2.2.2)
  have hbuf : h.name ++ [58, 32] ++ h.value = h.name ++ 58 :: (32 :: h.value) := by
    simp [List.append_assoc, List.singleton_append]
  cases hname : h.name with
  | nil => simp [hname] at hne
  | cons b bs =>
    have hb := all_mem isTchar h.name b hall (by simp [hname])
    have hsp : ((h.name).head? == some 32) = false := by
      simp [hname, List.head?, ne_beq_u8 (tchar_ne b hb).2.2.1]
    have htab : ((h.name).head? == some 9) = false := by
      simp [hname, List.head?, ne_beq_u8 (tchar_ne_htab b hb)]
    have hgoal : b :: bs ++ [58, 32] ++ h.value = h.name ++ 58 :: 32 :: h.value := by
      simp [hname, List.append_assoc, List.cons_append, List.singleton_append]
    simp [hname] at hsplit
    simp [parseField, hname, List.cons_append, List.head?,
      ne_beq_u8 (tchar_ne b hb).2.2.1, ne_beq_u8 (tchar_ne_htab b hb),
      hsplit, trim_space h.value hv, hn, canonical_bytes h.value hv]
    refine And.intro ?_ ?_
    · simpa [hname] using hn
    · rw [← hname]

theorem parseFields_render (hs : List Header) (rest : List UInt8) (fuel : Nat)
    (hc : headersCanonical hs = true) (hf : hs.length + 1 ≤ fuel) :
    parseFields fuel (renderHeaders hs ++ crlf ++ rest) = some (hs, rest) := by
  induction hs generalizing fuel rest with
  | nil =>
    cases fuel with
    | zero => omega
    | succ n =>
      simp [parseFields, renderHeaders, crlf, splitCRLF]
  | cons h hs ih =>
    cases fuel with
    | zero => simp at hf
    | succ n =>
      have hc1 : canonicalHeader h = true := by
        simp [headersCanonical] at hc
        exact hc.1
      have hcs : headersCanonical hs = true := by
        simp [headersCanonical] at hc
        exact hc.2
      have hlen : hs.length + 1 ≤ n := by
        simp at hf
        omega
      have hline := field_line_noBare h.name h.value (bare_all h.name
        (by simp [canonicalHeader] at hc1; exact hc1.1)).1 (canonical_bytes h.value
        (by simp [canonicalHeader] at hc1; exact hc1.2))
      have hsplit := splitCRLF_of_line (h.name ++ [58, 32] ++ h.value)
        (renderHeaders hs ++ crlf ++ rest) hline
      have hfield := parseField_render h hc1
      have hsplit' :
          splitCRLF (h.name ++ 58 :: 32 :: (h.value ++ 13 :: 10 :: (renderHeaders hs ++ 13 :: 10 :: rest))) =
            some (h.name ++ [58, 32] ++ h.value, renderHeaders hs ++ crlf ++ rest) := by
        simpa [crlf, List.append_assoc, List.singleton_append, List.cons_append] using hsplit
      simp only [crlf, List.append_assoc] at hsplit
      have hfield' : parseField (h.name ++ ([58, 32] ++ h.value)) = some h := by
        simpa [List.append_assoc] using hfield
      simp only [parseFields, renderHeaders, renderHeader, crlf, List.append_assoc, hsplit]
      split
      · rename_i heq
        injection heq
      · rename_i rest' heq
        injection heq with hnil
        simp [List.append_eq_nil_iff] at hnil
      · rename_i line rest' _ heq
        injection heq with hpair
        injection hpair with hline hrest
        subst hline
        subst hrest
        rw [hfield']
        split
        · rename_i heq
          injection heq
        · rename_i h' heq
          injection heq with hh
          subst hh
          have hbuf : renderHeaders hs ++ ([13, 10] ++ rest) = renderHeaders hs ++ crlf ++ rest := by
            simp [crlf, List.append_assoc]
          rw [hbuf, ih rest n hcs hlen]

theorem render_len (hs : List Header) : hs.length ≤ (renderHeaders hs).length := by
  induction hs with
  | nil => simp [renderHeaders]
  | cons h hs ih =>
    simp [renderHeaders, renderHeader, List.length_append]
    omega

theorem parseHead_render (hd : RequestHead) (rest : List UInt8) (ha : acceptHead hd = true) :
    parseHead (renderHead hd ++ rest) = some (hd, rest) := by
  simp [acceptHead, Bool.and_eq_true, List.isEmpty] at ha
  have hm : bareToken hd.method = true := ha.1.1.1.1
  have htne : hd.target ≠ [] := by
    intro hnil
    have ha' := ha
    simp [hnil] at ha'
  have ht : allBytes isVChar hd.target = true := by
    have hvchars : vchars hd.target = true := ha.1.1.2
    simpa [vchars] using hvchars
  have hhc : headersCanonical hd.headers = true := ha.1.2
  have hok : requestOK hd.method hd.target hd.version hd.headers = true := ha.2
  have hline := parseRequestLine_render hd.method hd.target hd.version hm ht htne
  have hbare : noBareLineBreak (hd.method ++ [32] ++ hd.target ++ [32] ++ versionBytes hd.version) := by
    intro b hb
    simp [List.mem_append] at hb
    rcases hb with hb | rfl | hb | rfl | hb
    · exact ⟨(tchar_ne b (all_mem isTchar hd.method b (bare_all hd.method hm).1 hb)).1,
        (tchar_ne b (all_mem isTchar hd.method b (bare_all hd.method hm).1 hb)).2.1⟩
    · decide
    · exact ⟨(vchar_ne b (all_mem isVChar hd.target b ht hb)).1,
        (vchar_ne b (all_mem isVChar hd.target b ht hb)).2.1⟩
    · decide
    · have hv := version_no_sp hd.version b hb
      refine ⟨?_, ?_⟩ <;> intro heq <;> subst heq <;> simp at hv
  have hsplit := splitCRLF_of_line
    (hd.method ++ [32] ++ hd.target ++ [32] ++ versionBytes hd.version)
    (renderHeaders hd.headers ++ crlf ++ rest) hbare
  have hfuel : hd.headers.length + 1 ≤ (renderHeaders hd.headers ++ crlf ++ rest).length := by
    have hlen := render_len hd.headers
    simp [List.length_append, crlf]
    omega
  have hfields := parseFields_render hd.headers rest _ hhc hfuel
  have hskip : skipEmpty (renderHead hd ++ rest) = renderHead hd ++ rest := by
    cases hmethod : hd.method with
    | nil => simp [hmethod, bareToken] at hm
    | cons b bs =>
      have hb : b ≠ 13 :=
        (tchar_ne b (all_mem isTchar hd.method b (bare_all hd.method hm).1 (by simp [hmethod]))).1
      simp [renderHead, hmethod, List.cons_append]
      exact skip_cons b _ hb
  have hskip2 :
      skipEmpty (hd.method ++ 32 :: (hd.target ++ 32 :: (versionBytes hd.version ++ 13 :: 10 ::
        (renderHeaders hd.headers ++ 13 :: 10 :: rest)))) =
        hd.method ++ 32 :: (hd.target ++ 32 :: (versionBytes hd.version ++ 13 :: 10 ::
          (renderHeaders hd.headers ++ 13 :: 10 :: rest))) := by
    cases hmethod : hd.method with
    | nil => simp [hmethod, bareToken] at hm
    | cons b bs =>
      have hb : b ≠ 13 :=
        (tchar_ne b (all_mem isTchar hd.method b (bare_all hd.method hm).1 (by simp [hmethod]))).1
      simp [hmethod, List.cons_append]
      exact skip_cons b _ hb
  have hsplit2 :
      splitCRLF (hd.method ++ 32 :: (hd.target ++ 32 :: (versionBytes hd.version ++ 13 :: 10 ::
        (renderHeaders hd.headers ++ 13 :: 10 :: rest)))) =
        some (hd.method ++ [32] ++ hd.target ++ [32] ++ versionBytes hd.version,
          renderHeaders hd.headers ++ crlf ++ rest) := by
    simpa [crlf, List.append_assoc, List.singleton_append, List.cons_append] using hsplit
  simp only [renderHead, crlf, List.append_assoc] at hskip hsplit
  simp only [parseHead, renderHead, crlf, List.append_assoc]
  rw [hskip, hsplit]
  split
  · rename_i heq
    injection heq
  · rename_i _ l rest' heq
    simp only [List.append_assoc] at hline
    injection heq with hpair
    injection hpair with hline' hrest
    subst hline'
    subst hrest
    rw [hline]
    split
    · rename_i heq
      injection heq
    · rename_i parsed heq
      injection heq with hparsed
      cases hparsed
      simp only [List.append_assoc, crlf] at hfields
      rw [hfields]
      split
      · rename_i heq
        injection heq
      · rename_i headers rest' heq
        injection heq with hpair
        injection hpair with hh hr
        subst hh
        subst hr
        simp [hok]

theorem takeBytes_length (bs : List UInt8) : takeBytes bs.length bs = bs := by
  induction bs with
  | nil => simp [takeBytes]
  | cons b bs ih => simp [takeBytes, List.length, ih]

theorem dropBytes_length (bs : List UInt8) : dropBytes bs.length bs = [] := by
  induction bs with
  | nil => simp [dropBytes]
  | cons _ bs ih => simp [dropBytes, List.length, ih]

theorem parseRequest_serializeFixed (hd : RequestHead) (body wire : List UInt8)
    (hs : serializeFixed hd body = some wire) :
    ∃ r, parseRequest wire = some r ∧ r.head.method = hd.method ∧
      r.head.target = hd.target ∧ r.head.version = hd.version ∧
      r.body = body ∧ r.rest = [] := by
  simp [serializeFixed] at hs
  split at hs
  · next n hf =>
    split at hs
    · next hif =>
      cases hs
      rcases hif with ⟨hlen, ha⟩
      have hhead := parseHead_render hd body ha
      refine ⟨{ head := hd, body := body, rest := [] }, ?_, rfl, rfl, rfl, rfl, rfl⟩
      simp [parseRequest, hhead, hf, hlen, takeBytes_length, dropBytes_length]
    · cases hs
  · cases hs

theorem parseRequest_serializeChunked (hd : RequestHead) (body wire : List UInt8)
    (hs : serializeChunked hd body = some wire) :
    ∃ r, parseRequest wire = some r ∧ r.head.method = hd.method ∧
      r.head.target = hd.target ∧ r.head.version = .http11 ∧
      r.body = body ∧ r.rest = [] := by
  simp [serializeChunked, Bool.and_eq_true] at hs
  rcases hs with ⟨⟨⟨⟨hv, hf⟩, ha⟩, hlen⟩, hwire⟩
  subst hwire
  have hhead := parseHead_render hd (encodeChunked body) ha
  have hdec := decodeChunked_encodeChunked body hlen
  refine ⟨{ head := hd, body := body, rest := [] }, ?_, rfl, rfl, ?_, rfl, rfl⟩
  · simp [parseRequest, hhead, hf, hdec]
  · simpa using hv

theorem takeBytes_le (n : Nat) (bs extra : List UInt8) (h : n ≤ bs.length) :
    takeBytes n (bs ++ extra) = takeBytes n bs := by
  induction n generalizing bs with
  | zero => simp [takeBytes]
  | succ n ih =>
    cases bs with
    | nil => simp at h
    | cons b bs =>
      simp [List.length] at h
      simp [takeBytes, List.cons_append]
      exact ih bs h

theorem dropBytes_le (n : Nat) (bs extra : List UInt8) (h : n ≤ bs.length) :
    dropBytes n (bs ++ extra) = dropBytes n bs ++ extra := by
  induction n generalizing bs with
  | zero => simp [dropBytes]
  | succ n ih =>
    cases bs with
    | nil => simp at h
    | cons _ bs =>
      simp [dropBytes, List.length] at h ⊢
      exact ih bs h

theorem parseFields_prefix (fuel fuel' : Nat) (bs : List UInt8) (hs : List Header)
    (rest extra : List UInt8)
    (h : parseFields fuel bs = some (hs, rest)) (hf : fuel ≤ fuel') :
    parseFields fuel' (bs ++ extra) = some (hs, rest ++ extra) := by
  induction fuel generalizing bs hs rest fuel' with
  | zero => simp [parseFields] at h
  | succ fuel ih =>
    cases fuel' with
    | zero => omega
    | succ fuel' =>
      simp [parseFields] at h
      cases hsp : splitCRLF bs with
      | none => simp [hsp] at h
      | some pair =>
        simp [hsp] at h
        rcases pair with ⟨line, rest0⟩
        have hpre := splitCRLF_prefix_free bs line rest0 extra hsp
        cases line with
        | nil =>
          simp at h
          rcases h with ⟨rfl, rfl⟩
          simp [parseFields, hpre]
        | cons b line =>
          simp at h
          cases hfield : parseField (b :: line) with
          | none => simp [hfield] at h
          | some hdr =>
            simp [hfield] at h
            cases hrest : parseFields fuel rest0 with
            | none => simp [hrest] at h
            | some parsed =>
              simp [hrest] at h
              rcases parsed with ⟨hs0, rest'⟩
              rcases h with ⟨rfl, rfl, rfl⟩
              have ih' := ih fuel' rest0 hs0 rest' hrest (by omega)
              simp [parseFields, hpre, hfield, ih']

theorem skip_crlf (bs : List UInt8) : skipEmpty (13 :: 10 :: bs) = skipEmpty bs := by
  simp [skipEmpty]

theorem skip_not (b c : UInt8) (bs : List UInt8) (h : b ≠ 13 ∨ c ≠ 10) :
    skipEmpty (b :: c :: bs) = b :: c :: bs := by
  unfold skipEmpty
  split
  · rename_i heq
    simp at heq
    rcases h with h | h
    · exact absurd heq.1 h
    · exact absurd heq.2.1 h
  · rfl

theorem skip_one (b : UInt8) : skipEmpty [b] = [b] := by
  unfold skipEmpty
  split
  · rename_i heq
    simp at heq
  · rfl

theorem skipEmpty_append (bs extra : List UInt8) (b : UInt8) (rest : List UInt8)
    (h : skipEmpty bs = b :: rest) (hb : b ≠ 13) :
    skipEmpty (bs ++ extra) = (b :: rest) ++ extra := by
  match bs with
  | [] => simp [skipEmpty] at h
  | [x] =>
    simp [skip_one] at h
    rcases h with ⟨rfl, rfl⟩
    simp [List.singleton_append, skip_cons x extra hb]
  | 13 :: 10 :: ys =>
    simp [skip_crlf] at h
    exact skipEmpty_append ys extra b rest h hb
  | x :: y :: ys =>
    by_cases hx : x = 13
    · subst hx
      by_cases hy : y = 10
      · subst hy
        simp [skip_crlf] at h
        exact skipEmpty_append ys extra b rest h hb
      · have hid := skip_not 13 y (ys ++ extra) (Or.inr hy)
        simp [skip_not 13 y ys (Or.inr hy), List.cons_append] at h
        rcases h with ⟨rfl, rfl⟩
        simp [hid, List.cons_append]
    · have hid := skip_not x y (ys ++ extra) (Or.inl hx)
      simp [skip_not x y ys (Or.inl hx), List.cons_append] at h
      rcases h with ⟨rfl, rfl⟩
      simp [hid, List.cons_append]
termination_by bs.length

theorem method_head (line : List UInt8) (method target : List UInt8) (v : Version)
    (h : parseRequestLine line = some (method, target, v)) :
    ∃ b rest, line = b :: rest ∧ b ≠ 13 := by
  cases line with
  | nil => simp [parseRequestLine, splitByte] at h
  | cons c cs =>
    refine ⟨c, cs, rfl, ?_⟩
    intro hc
    subst hc
    cases hcs : splitByte 32 cs with
    | nil => simp [parseRequestLine, splitByte, hcs, bareToken, allBytes, isTchar, isAlpha, isDigit] at h
    | cons p ps =>
      cases ps with
      | nil => simp [parseRequestLine, splitByte, hcs] at h
      | cons q qs =>
        cases qs with
        | nil => simp [parseRequestLine, splitByte, hcs] at h
        | cons r rs =>
          cases rs with
          | nil =>
            simp [parseRequestLine, splitByte, hcs, bareToken, allBytes, isTchar, isAlpha, isDigit] at h
            split at h <;> simp at h
          | cons => simp [parseRequestLine, splitByte, hcs] at h

theorem parseHead_prefix (bs extra : List UInt8) (hd : RequestHead) (rest : List UInt8)
    (h : parseHead bs = some (hd, rest)) :
    parseHead (bs ++ extra) = some (hd, rest ++ extra) := by
  unfold parseHead at h
  cases hsk : skipEmpty bs with
  | nil => simp [hsk, splitCRLF] at h
  | cons b skipped =>
    cases hsp : splitCRLF (b :: skipped) with
    | none => simp [hsk, hsp] at h
    | some got =>
      obtain ⟨line, after⟩ := got
      cases hreq : parseRequestLine line with
      | none => simp [hsk, hsp, hreq] at h
      | some parsed =>
        obtain ⟨method, target, v⟩ := parsed
        obtain ⟨c, _, hline, hc⟩ := method_head line method target v hreq
        cases hf : parseFields after.length after with
        | none => simp [hsk, hsp, hreq, hf] at h
        | some fields =>
          obtain ⟨headers, rest'⟩ := fields
          simp [hsk, hsp, hreq, hf] at h
          rcases h with ⟨hok, rfl, rfl⟩
          have hbuf := (splitCRLF_sound (b :: skipped) line after).mp hsp
          have hb : b ≠ 13 := by
            rcases hbuf with ⟨_, hbuf⟩
            simp [hline, List.cons_append] at hbuf
            rcases hbuf with ⟨hb', _⟩
            exact hb' ▸ hc
          have happ := skipEmpty_append bs extra b skipped hsk hb
          have hpre := splitCRLF_prefix_free (b :: skipped) line after extra hsp
          have hmore : after.length ≤ (after ++ extra).length := by simp [List.length_append]
          have hfields := parseFields_prefix after.length (after ++ extra).length after headers rest'
            extra hf hmore
          simp [List.cons_append] at hpre happ
          simp [parseHead, happ, hpre, hreq]
          have hfields' : parseFields (after.length + extra.length) (after ++ extra) =
              some (headers, rest' ++ extra) := by
            simpa [List.length_append] using hfields
          rw [hfields']
          simp [hok]

theorem parseTrailers_prefix (fuel fuel' : Nat) (bs : List UInt8) (hs : List Header)
    (rest extra : List UInt8)
    (h : parseTrailers fuel bs = some (hs, rest)) (hf : fuel ≤ fuel') :
    parseTrailers fuel' (bs ++ extra) = some (hs, rest ++ extra) := by
  induction fuel generalizing bs hs rest fuel' with
  | zero => simp [parseTrailers] at h
  | succ fuel ih =>
    cases fuel' with
    | zero => omega
    | succ fuel' =>
      simp [parseTrailers] at h
      cases hsp : splitCRLF bs with
      | none => simp [hsp] at h
      | some pair =>
        simp [hsp] at h
        rcases pair with ⟨line, rest0⟩
        have hpre := splitCRLF_prefix_free bs line rest0 extra hsp
        cases line with
        | nil =>
          simp at h
          rcases h with ⟨rfl, rfl⟩
          simp [parseTrailers, hpre]
        | cons b line =>
          simp at h
          cases hfield : parseField (b :: line) with
          | none => simp [hfield] at h
          | some hdr =>
            simp [hfield] at h
            cases hrest : parseTrailers fuel rest0 with
            | none => simp [hrest] at h
            | some parsed =>
              simp [hrest] at h
              rcases parsed with ⟨hs0, rest'⟩
              rcases h with ⟨rfl, rfl, rfl⟩
              have ih' := ih fuel' rest0 hs0 rest' hrest (by omega)
              simp [parseTrailers, hpre, hfield, ih']

theorem decodeLoop_prefix (fuel fuel' : Nat) (acc buf body : List UInt8) (ts : List Header)
    (rest extra : List UInt8)
    (h : decodeLoop fuel acc buf = some (body, ts, rest)) (hf : fuel ≤ fuel') :
    decodeLoop fuel' acc (buf ++ extra) = some (body, ts, rest ++ extra) := by
  induction fuel generalizing acc buf body ts rest fuel' with
  | zero => simp [decodeLoop] at h
  | succ fuel ih =>
    cases fuel' with
    | zero => omega
    | succ fuel' =>
      simp [decodeLoop] at h
      cases hsp : splitCRLF buf with
      | none => simp [hsp] at h
      | some got =>
        obtain ⟨line, after⟩ := got
        have hpre := splitCRLF_prefix_free buf line after extra hsp
        simp [hsp] at h
        cases hsz : parseChunkSize line with
        | none => simp [hsz] at h
        | some n =>
          by_cases hz : n = 0
          · subst hz
            simp [hsz] at h
            cases htr : parseTrailers after.length after with
            | none => simp [htr] at h
            | some parsed =>
              simp [htr] at h
              rcases parsed with ⟨ts0, rest0⟩
              rcases h with ⟨rfl, rfl, rfl⟩
              have hmore : after.length ≤ (after ++ extra).length := by simp [List.length_append]
              have htr' := parseTrailers_prefix after.length (after ++ extra).length after ts0 rest0
                extra htr hmore
              have htr'' : parseTrailers (after.length + extra.length) (after ++ extra) =
                  some (ts0, rest0 ++ extra) := by
                simpa [List.length_append] using htr'
              simp [decodeLoop, hpre, hsz, htr'']
          · simp [hsz, hz] at h
            split at h
            · rename_i _ rest0 heq
              rcases h with ⟨hlen, hrec⟩
              have htake := takeBytes_le n after extra (by omega)
              have hdrop := dropBytes_le n after extra (by omega)
              simp [decodeLoop, hpre, hsz, htake, hdrop, heq]
              refine And.intro ?_ (ih fuel' (acc ++ takeBytes n after) rest0 body ts rest hrec (by omega))
              · omega
            · simp at h

theorem decodeChunked_prefix_free (buf body rest extra : List UInt8) (trailers : List Header)
    (h : decodeChunked buf = some (body, trailers, rest)) :
    decodeChunked (buf ++ extra) = some (body, trailers, rest ++ extra) := by
  simp [decodeChunked] at h ⊢
  exact decodeLoop_prefix (buf.length + 1) (buf.length + extra.length + 1) [] buf body trailers
    rest extra h (by omega)

theorem parseRequest_prefix_free (stream extra : List UInt8) (r : FramedRequest)
    (h : parseRequest stream = some r) :
    parseRequest (stream ++ extra) = some { r with rest := r.rest ++ extra } := by
  simp [parseRequest] at h
  cases hh : parseHead stream with
  | none => simp [hh] at h
  | some got =>
    obtain ⟨hd, rest⟩ := got
    have hp := parseHead_prefix stream extra hd rest hh
    cases hf : determineFraming hd.version hd.headers with
    | none => simp [hh, hf] at h
    | some fr =>
      cases fr with
      | fixed n =>
        simp [hh, hf] at h
        rcases h with ⟨hlen, rfl⟩
        have htake := takeBytes_le n rest extra hlen
        have hdrop := dropBytes_le n rest extra hlen
        have hlong : ¬ (rest ++ extra).length < n := by
          simp [List.length_append]
          omega
        simp [parseRequest, hp, hf, htake, hdrop]
        omega
      | chunked =>
        simp [hh, hf] at h
        cases hdec : decodeChunked rest with
        | none => simp [hdec] at h
        | some parsed =>
          simp [hdec] at h
          obtain ⟨body, ts, rest'⟩ := parsed
          cases h
          have hdec' := decodeChunked_prefix_free rest body rest' extra ts hdec
          simp [parseRequest, hp, hf, hdec']

theorem parseRequest_stream_unique (stream tail1 tail2 : List UInt8)
    (msgs1 msgs2 : List (RequestHead × List UInt8))
    (hlen : msgs1.length = msgs2.length)
    (h1 : Spec.StreamFrames msgs1 tail1 stream)
    (h2 : Spec.StreamFrames msgs2 tail2 stream) :
    msgs1 = msgs2 ∧ tail1 = tail2 := by
  induction h1 generalizing msgs2 tail2 with
  | nil =>
    cases h2 with
    | nil => exact ⟨rfl, rfl⟩
    | cons _ _ => simp at hlen
  | cons hp hrest ih =>
    cases h2 with
    | nil => simp at hlen
    | cons hp2 hrest2 =>
      have hr : _ = _ := hp.symm.trans hp2
      cases hr
      simp at hlen
      have ih' := ih _ _ hlen hrest2
      rcases ih' with ⟨rfl, rfl⟩
      exact ⟨rfl, rfl⟩

theorem reject_smuggling_vectors :
    ∀ v, v ∈ Spec.smugglingVectors → parseRequest v = none := by
  intro v hv
  simp [Spec.smugglingVectors] at hv
  rcases hv with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl
  all_goals decide

end Http
