import Http.Parse

namespace Http

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

theorem nibble_ok (d : Nat) (hd : d < 16) :
    isHex (nibble d) = true ∧ nibble d ≠ 13 ∧ nibble d ≠ 10 := by
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
      simp [natToHexLower, h16, hmod, allBytes, (nibble_ok n h16).1]
    · have hdiv : n / 16 < n := Nat.div_lt_self (by omega) (by decide)
      have hdigit : n % 16 < 16 := Nat.mod_lt _ (by decide)
      rw [natToHexLower]
      simp only [h16, ite_false]
      rw [allBytes_append]
      simp [allBytes, ih (n / 16) hdiv, (nibble_ok _ hdigit).1]

theorem natToHex_no_break (n : Nat) : noBareLineBreak (natToHexLower n) := by
  induction n using Nat.strongRecOn with
  | ind n ih =>
    by_cases h16 : n < 16
    · have hmod : n % 16 = n := Nat.mod_eq_of_lt h16
      simp [natToHexLower, h16, hmod, noBareLineBreak]
      exact ⟨(nibble_ok n h16).2.1, (nibble_ok n h16).2.2⟩
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
        exact ⟨(nibble_ok _ hdigit).2.1, (nibble_ok _ hdigit).2.2⟩

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
    simp [decodeLoop, crlf, splitCRLF, parseChunkSize, parseHex, parseAcc, hexVal, parseExt,
      parseTrailers, takeWhileBytes, dropBytes, isHex, isDigit]

theorem decodeChunked_encodeChunked (body : List UInt8) (h : body.length ≤ maxUInt64) :
    decodeChunked (encodeChunked body) = some (body, [], []) := by
  cases body with
  | nil =>
    simp [encodeChunked, decodeChunked, decodeLoop, crlf, splitCRLF, parseChunkSize, parseHex,
      parseAcc, hexVal, parseExt, parseTrailers, takeWhileBytes, dropBytes, isHex, isDigit]
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

/-- Chunked framing is HTTP/1.1 or a later 1.x, with no Content-Length, and
    the combined Transfer-Encoding value is a list of the one coding
    `chunked` (empty elements allowed). The method is not `CONNECT`, and
    the target does not begin with `:`. -/
theorem determineFraming_rejects_nonfinal_chunked (h : Head)
    (hf : determineFraming h = some .chunked) :
    h.major = 1 ∧ 1 ≤ h.minor ∧
      (∀ f, f ∈ h.fields → f.isNamed contentLengthName = false) ∧
      Grammar.chunkedList.isMatch
        (List.intercalate [0x2C]
          ((h.fields.filter (·.isNamed transferEncodingName)).map (·.value))) = true ∧
      h.method ≠ connectName ∧ h.target.head? ≠ some 0x3A := by
  simp only [determineFraming] at hf
  revert hf
  simp only [Head.framing]
  intro hf
  split at hf
  · simp at hf
  · rename_i fr hcore
    split at hf
    · simp at hf
    · rename_i hnot
      cases hf
      simp only [Head.framingCore] at hcore
      -- Host and version guards refuse before the field match.
      split at hcore
      · simp at hcore
      · split at hcore
        · simp at hcore
        · rename_i hhosts hconnect
          -- `hhosts` / `hconnect` are the false guards. The match is on the two filters.
          split at hcore
          · simp at hcore
          · simp at hcore
          · next _ _ ts heq =>
            split at hcore
            · next hok =>
              injection hcore with hfr
              cases hfr
              simp only [Bool.and_eq_true] at hok
              rcases hok with ⟨hminor, hmatch⟩
              have hminor' : 1 ≤ h.minor := by
                simpa using hminor
              refine ⟨?major, hminor', ?nocl, ?te, ?method, ?colon⟩
              case major =>
                have hhosts' := hhosts
                simp only [Bool.not_eq_true, Bool.or_eq_false_iff, bne, beq_iff_eq] at hhosts'
                rcases hhosts' with ⟨hmaj, _⟩
                cases hbeq : h.major == 1 with
                | false => simp [hbeq] at hmaj
                | true => exact beq_iff_eq.mp hbeq
              case nocl =>
                intro f hf'
                by_cases hnamed : f.isNamed contentLengthName = true
                · have hmem : f ∈ h.fields.filter (·.isNamed contentLengthName) :=
                    List.mem_filter.mpr ⟨hf', hnamed⟩
                  simp [heq] at hmem
                · simpa [Bool.not_eq_true] using hnamed
              case te =>
                simpa [ts] using hmatch
              case method =>
                have hnot' := hnot
                simp only [Bool.not_eq_true, Bool.or_eq_false_iff] at hnot'
                rcases hnot' with ⟨_, hconn⟩
                simp only [Bool.and_eq_false_iff] at hconn
                cases hconn with
                | inl hne =>
                  simpa [beq_eq_false_iff_ne] using hne
                | inr hlen =>
                  simp at hlen
              case colon =>
                have hnot' := hnot
                simp only [Bool.not_eq_true, Bool.or_eq_false_iff] at hnot'
                rcases hnot' with ⟨hcol, _⟩
                simpa [beq_eq_false_iff_ne] using hcol
            · injection hcore
          · injection hcore

/-- The weak form: chunked framing needs HTTP/1.1 or a later 1.x and no
    Content-Length. The combined Transfer-Encoding value is not part of
    this statement. -/
theorem chunked_requires_http11_without_cl (h : Head)
    (hf : determineFraming h = some .chunked) :
    h.major = 1 ∧ 1 ≤ h.minor ∧
      (∀ f, f ∈ h.fields → f.isNamed contentLengthName = false) := by
  rcases determineFraming_rejects_nonfinal_chunked h hf with ⟨hmaj, hmin, hcl, _, _, _⟩
  exact ⟨hmaj, hmin, hcl⟩

/-- A Transfer-Encoding field whose combined value is not a list of the
    one coding `chunked` is not framed as chunked. -/
theorem determineFraming_rejects_bad_te (h : Head)
    (hte : ∃ f, f ∈ h.fields ∧ f.isNamed transferEncodingName = true)
    (hbad : Grammar.chunkedList.isMatch
        (List.intercalate [0x2C]
          ((h.fields.filter (·.isNamed transferEncodingName)).map (·.value))) = false) :
    determineFraming h ≠ some .chunked := by
  have _ := hte
  intro hf
  rcases determineFraming_rejects_nonfinal_chunked h hf with ⟨_, _, _, hmatch, _, _⟩
  exact Bool.noConfusion (hmatch.symm.trans hbad)

/-- HTTP/1.0 with a Transfer-Encoding field is not framed as chunked. -/
theorem determineFraming_rejects_http10_te (h : Head)
    (hminor : h.minor = 0)
    (_hte : ∃ f, f ∈ h.fields ∧ f.isNamed transferEncodingName = true) :
    determineFraming h ≠ some .chunked := by
  intro hf
  rcases determineFraming_rejects_nonfinal_chunked h hf with ⟨_, hmin, _⟩
  omega

theorem determineFraming_disjoint (h : Head) (f1 f2 : Framing)
    (h1 : determineFraming h = some f1) (h2 : determineFraming h = some f2) :
    f1 = f2 :=
  Option.some.inj (h1.symm.trans h2)

theorem takeBytes_length (bs : List UInt8) : takeBytes bs.length bs = bs := by
  simpa using takeBytes_append bs []

theorem dropBytes_length (bs : List UInt8) : dropBytes bs.length bs = [] := by
  simpa using dropBytes_append bs []

theorem parseRequest_serializeFixed (h : Head) (body : List UInt8)
    (hf : h.framing = some (.length body.length))
    (hp : parseHead (h.print ++ body) = some (h, body)) :
    parseRequest (h.print ++ body) = some { head := h, body := body, rest := [] } := by
  simp [parseRequest, hp, hf, takeBytes_length, dropBytes_length]

theorem parseRequest_serializeChunked (h : Head) (body : List UInt8)
    (hlen : body.length ≤ maxUInt64)
    (hf : h.framing = some .chunked)
    (hp : parseHead (h.print ++ encodeChunked body) = some (h, encodeChunked body)) :
    parseRequest (h.print ++ encodeChunked body) =
      some { head := h, body := body, rest := [] } := by
  simp [parseRequest, hp, hf, decodeChunked_encodeChunked body hlen]

theorem parseRequest_stream_unique (stream tail1 tail2 : List UInt8)
    (msgs1 msgs2 : List (Head × List UInt8))
    (h1 : StreamFrames msgs1 tail1 stream) (h2 : StreamFrames msgs2 tail2 stream)
    (hlen : msgs1.length = msgs2.length) :
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
      rcases ih _ _ hrest2 hlen with ⟨rfl, rfl⟩
      exact ⟨rfl, rfl⟩

end Http
