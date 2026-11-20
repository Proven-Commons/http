/-
  What a request head is, and how its body is framed. Part of the
  approved specification, with `Spec.lean`, since the statements are
  about these types.
-/

namespace Http

/-- A field line: its name and its value, as octets, the value without
    the optional whitespace around it. -/
structure Field where
  name : List UInt8
  value : List UInt8
  deriving DecidableEq, Repr

/-- A request head: the request line, `method SP request-target SP
    HTTP-version`, with the version's two digits as numbers, and the
    field lines in order. -/
structure Head where
  method : List UInt8
  target : List UInt8
  major : Nat
  minor : Nat
  fields : List Field
  deriving DecidableEq, Repr

/-- How the body after a head is delimited: by a length in octets, which
    is 0 when there is no body, or by the chunked transfer coding. -/
inductive Framing where
  | length (n : Nat)
  | chunked
  deriving DecidableEq, Repr

end Http
