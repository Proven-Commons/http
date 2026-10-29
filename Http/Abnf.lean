/-
  The grammar notation: a small language of regular expressions over
  octets, enough to write the ABNF rules of RFC 3986, RFC 9110 and
  RFC 9112 that this library reads. Part of the approved specification,
  with `Spec.lean`, since the grammar in `Spec/Rules.lean` is written in
  it and `Spec/Abnf.lean` gives its meaning.

  Each ABNF form (RFC 5234) has a counterpart here:
  - a terminal value, `%x41`, is `byte`, and a range, `%x41-5A`, is
    `range`;
  - concatenation is `cat`, or `seq` for several;
  - alternation, `/`, is `alt`, or `any` for several;
  - repetition: `*rule` is `star`, `1*rule` is `plus`, `nrule` is
    `rep n`, `*n rule` is `upTo n`, `n*m rule` is `between n m`;
  - an optional sequence, `[ rule ]`, is `opt`;
  - a quoted string is case-insensitive (section 2.3), and is `litCI`;
    a case-sensitive one, `%s"..."` (RFC 7405), is `lit`.
-/

namespace Http

/-- A regular expression over octets. -/
inductive Re where
  /-- Matches nothing. -/
  | empty
  /-- Matches the empty string. -/
  | eps
  /-- Matches one octet from `lo` to `hi`. -/
  | range (lo hi : UInt8)
  /-- Matches a string of `a` followed by a string of `b`. -/
  | cat (a b : Re)
  /-- Matches what `a` or `b` matches. -/
  | alt (a b : Re)
  /-- Matches zero or more strings of `a`, one after another. -/
  | star (a : Re)
  deriving DecidableEq, Repr

namespace Re

/-- One octet. -/
def byte (c : UInt8) : Re := range c c

/-- Each of the rules in turn. -/
def seq : List Re → Re
  | [] => eps
  | [r] => r
  | r :: rs => cat r (seq rs)

/-- Any one of the rules. -/
def any : List Re → Re
  | [] => empty
  | [r] => r
  | r :: rs => alt r (any rs)

/-- `[ r ]`. -/
def opt (r : Re) : Re := alt eps r

/-- `1*r`. -/
def plus (r : Re) : Re := cat r (star r)

/-- `n r`: exactly `n` times. -/
def rep (n : Nat) (r : Re) : Re := seq (List.replicate n r)

/-- `*n r`: at most `n` times. -/
def upTo (n : Nat) (r : Re) : Re := seq (List.replicate n (opt r))

/-- `n*m r`: from `n` to `m` times. -/
def between (n m : Nat) (r : Re) : Re := cat (rep n r) (upTo (m - n) r)

/-- A string of ASCII characters, matched exactly. -/
def lit (s : String) : Re := seq (s.toList.map fun c => byte c.toNat.toUInt8)

/-- An ASCII letter in either case, or any other character as itself. -/
def charCI (c : Char) : Re :=
  if 'a' ≤ c ∧ c ≤ 'z' then alt (byte c.toNat.toUInt8) (byte (c.toNat - 32).toUInt8)
  else if 'A' ≤ c ∧ c ≤ 'Z' then alt (byte c.toNat.toUInt8) (byte (c.toNat + 32).toUInt8)
  else byte c.toNat.toUInt8

/-- A quoted ABNF string: ASCII letters match in either case. -/
def litCI (s : String) : Re := seq (s.toList.map charCI)

/-- Any one of the characters of the string. -/
def oneOf (s : String) : Re := any (s.toList.map fun c => byte c.toNat.toUInt8)

end Re

end Http
