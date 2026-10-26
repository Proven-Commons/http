/-
  Reading and writing a request head (RFC 9112, sections 2 to 5): the
  request line, the field lines, and the empty line that ends them.
-/

import Http.Types
import Http.Match
import Http.Grammar

namespace Http

/-- SP or HTAB. -/
def isWs (c : UInt8) : Bool := c == 0x20 || c == 0x09

/-- An ASCII digit. -/
def isDigit (c : UInt8) : Bool := 0x30 ≤ c && c ≤ 0x39

/-- An ASCII letter. -/
def isAlpha (c : UInt8) : Bool := (0x41 ≤ c && c ≤ 0x5A) || (0x61 ≤ c && c ≤ 0x7A)

/-- A `tchar` (RFC 9110, section 5.6.2): a letter, a digit, or one of
    ``!#$%&'*+-.^_`|~``. -/
def isTchar (c : UInt8) : Bool :=
  isAlpha c || isDigit c || [0x21, 0x23, 0x24, 0x25, 0x26, 0x27, 0x2A, 0x2B, 0x2D, 0x2E, 0x5E, 0x5F,
    0x60, 0x7C, 0x7E].contains c

/-- A `token`: one or more `tchar`. -/
def isToken (s : List UInt8) : Bool := !s.isEmpty && s.all isTchar

/-- A `field-vchar`: a visible ASCII character or an octet from 0x80. -/
def isVchar (c : UInt8) : Bool := (0x21 ≤ c && c ≤ 0x7E) || 0x80 ≤ c

/-- A `field-value`: visible characters, with SP and HTAB only between
    them. -/
def isFieldValue (v : List UInt8) : Bool :=
  v.all (fun c => isVchar c || isWs c) &&
    match v.head?, v.getLast? with
    | some a, some b => isVchar a && isVchar b
    | _, _ => true

/-- The value without the whitespace around it. -/
def trim (v : List UInt8) : List UInt8 :=
  ((v.dropWhile isWs).reverse.dropWhile isWs).reverse

/-- `takeLine`, with the octets of the line read so far in `acc`, last
    first. It calls itself last, so it runs in constant stack. -/
def takeLineFrom (acc : List UInt8) : List UInt8 → Option (List UInt8 × List UInt8)
  | [] => none
  | c :: rest =>
    if c == 0x0D then
      match rest with
      | d :: rest' => if d == 0x0A then some (acc.reverse, rest') else none
      | [] => none
    else if c == 0x0A then none
    else takeLineFrom (c :: acc) rest

/-- The first line: the octets up to the first CR, which must be
    followed by LF, and what comes after the CRLF. `none` when there is
    no CR, when a LF comes first, or when the CR is not followed by LF. -/
def takeLine (bs : List UInt8) : Option (List UInt8 × List UInt8) := takeLineFrom [] bs

/-- The octets after any empty lines at the start. -/
def skipEmpty : List UInt8 → List UInt8
  | c :: d :: rest => if c == 0x0D && d == 0x0A then skipEmpty rest else c :: d :: rest
  | bs => bs

/-- The version `HTTP/d.d`, as its two digits. -/
def parseVersion : List UInt8 → Option (Nat × Nat)
  | [h, t1, t2, p, s, a, dot, b] =>
    if h == 0x48 && t1 == 0x54 && t2 == 0x54 && p == 0x50 && s == 0x2F && dot == 0x2E &&
        isDigit a && isDigit b then
      some (a.toNat - 0x30, b.toNat - 0x30)
    else none
  | _ => none

/-- A field line: a token, a colon, and a value with optional whitespace
    around it. -/
def parseField (line : List UInt8) : Option Field :=
  let name := line.takeWhile (· != 0x3A)
  match line.drop name.length with
  | _ :: v =>
    let value := trim v
    if isToken name && isFieldValue value then some ⟨name, value⟩ else none
  | [] => none

/-- `parseFields`, with the fields read so far in `acc`, last first. It
    calls itself last, so it runs in constant stack. -/
def parseFieldsFrom (acc : List Field) : Nat → List UInt8 → Option (List Field × List UInt8)
  | 0, _ => none
  | fuel + 1, bs =>
    match takeLine bs with
    | none => none
    | some (line, rest) =>
      if line.isEmpty then some (acc.reverse, rest)
      else
        match parseField line with
        | none => none
        | some f => parseFieldsFrom (f :: acc) fuel rest

/-- The field lines up to the empty line, and what follows it. -/
def parseFields (fuel : Nat) (bs : List UInt8) : Option (List Field × List UInt8) :=
  parseFieldsFrom [] fuel bs

/-- Reads a request head from the start of `bs`, after any empty lines,
    and gives it with the octets that follow it. -/
def parseHead (bs : List UInt8) : Option (Head × List UInt8) := do
  let (line, rest) ← takeLine (skipEmpty bs)
  match line.splitOn 0x20 with
  | [m, t, v] =>
    let (major, minor) ← parseVersion v
    if isToken m && Grammar.requestTarget.isMatch t then
      let (fs, rest') ← parseFields (rest.length + 1) rest
      pure (⟨m, t, major, minor, fs⟩, rest')
    else none
  | _ => none

/-- Writes the head: the request line, each field as `name: value`, and
    the empty line, each line ending in CRLF. -/
def Head.print (h : Head) : List UInt8 :=
  h.method ++ [0x20] ++ h.target ++ [0x20, 0x48, 0x54, 0x54, 0x50, 0x2F, (0x30 + h.major).toUInt8,
    0x2E, (0x30 + h.minor).toUInt8, 0x0D, 0x0A] ++
    (h.fields.map fun f => f.name ++ [0x3A, 0x20] ++ f.value ++ [0x0D, 0x0A]).flatten ++ [0x0D, 0x0A]

end Http
