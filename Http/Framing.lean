/-
  Whether a server accepts a request head, and how the body after it is
  framed (RFC 9112, sections 3.2, 6.1 and 6.3).
-/

import Http.Head

namespace Http

/-- ASCII lower case. -/
def lower (c : UInt8) : UInt8 := if 0x41 ≤ c && c ≤ 0x5A then c + 0x20 else c

/-- Whether the field's name, without regard to ASCII case, is `n`,
    given in lower case. -/
def Field.isNamed (f : Field) (n : List UInt8) : Bool := f.name.map lower == n

/-- The number a string of decimal digits writes. -/
def decimal (ds : List UInt8) : Nat := ds.foldl (fun n d => 10 * n + (d.toNat - 0x30)) 0

/-- `host`, `content-length`, `transfer-encoding` and `chunked`. -/
def hostName : List UInt8 := [0x68, 0x6F, 0x73, 0x74]
def contentLengthName : List UInt8 :=
  [0x63, 0x6F, 0x6E, 0x74, 0x65, 0x6E, 0x74, 0x2D, 0x6C, 0x65, 0x6E, 0x67, 0x74, 0x68]
def transferEncodingName : List UInt8 :=
  [0x74, 0x72, 0x61, 0x6E, 0x73, 0x66, 0x65, 0x72, 0x2D, 0x65, 0x6E, 0x63, 0x6F, 0x64, 0x69, 0x6E,
    0x67]
def chunkedName : List UInt8 := [0x63, 0x68, 0x75, 0x6E, 0x6B, 0x65, 0x64]

/-- The framing of the body after the head, or `none` when the server
    must reject the request: a major version other than 1, a missing,
    repeated or invalid Host, Transfer-Encoding together with
    Content-Length, Transfer-Encoding in HTTP/1.0 or with a value other
    than `chunked`, or Content-Length other than one string of digits. -/
def Head.framing (h : Head) : Option Framing :=
  let hosts := h.fields.filter (·.isNamed hostName)
  if h.major != 1 || hosts.length > 1 || (1 ≤ h.minor && hosts.length != 1) ||
      !hosts.all (fun f => Grammar.hostValue.isMatch f.value) then none
  else
    match h.fields.filter (·.isNamed transferEncodingName),
        h.fields.filter (·.isNamed contentLengthName) with
    | [], [] => some (.length 0)
    | [], [f] => if !f.value.isEmpty && f.value.all isDigit then some (.length (decimal f.value)) else none
    | [f], [] => if 1 ≤ h.minor && f.value.map lower == chunkedName then some .chunked else none
    | _, _ => none

end Http
