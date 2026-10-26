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

/-- `host`, `content-length` and `transfer-encoding`. -/
def hostName : List UInt8 := [0x68, 0x6F, 0x73, 0x74]
def contentLengthName : List UInt8 :=
  [0x63, 0x6F, 0x6E, 0x74, 0x65, 0x6E, 0x74, 0x2D, 0x6C, 0x65, 0x6E, 0x67, 0x74, 0x68]
def transferEncodingName : List UInt8 :=
  [0x74, 0x72, 0x61, 0x6E, 0x73, 0x66, 0x65, 0x72, 0x2D, 0x65, 0x6E, 0x63, 0x6F, 0x64, 0x69, 0x6E,
    0x67]

/-- `CONNECT`. -/
def connectName : List UInt8 := [0x43, 0x4F, 0x4E, 0x4E, 0x45, 0x43, 0x54]

/-- The digits at the end of `t`: in an authority-form target, its port. -/
def portOf (t : List UInt8) : List UInt8 := (t.reverse.takeWhile isDigit).reverse

/-- Whether the head keeps the rule of RFC 9110 section 9.3.6 for
    CONNECT: its target is `uri-host ":" port`, with a port from 1 to
    65535. Any other method keeps it. -/
def Head.connectOK (h : Head) : Bool :=
  h.method != connectName ||
    (Grammar.authorityForm.isMatch h.target && 1 ≤ decimal (portOf h.target) &&
      decimal (portOf h.target) ≤ 65535)

/-- `http:` and `https:`. -/
def httpColon : List UInt8 := [0x68, 0x74, 0x74, 0x70, 0x3A]
def httpsColon : List UInt8 := [0x68, 0x74, 0x74, 0x70, 0x73, 0x3A]

/-- Whether the head keeps the rule of RFC 9110 sections 4.2.1, 4.2.2 and
    4.2.4: a target whose scheme is http or https, in any case, is such a
    URI with a host that is not empty and no userinfo. A CONNECT target
    is a host and a port, so a CONNECT keeps it. -/
def Head.httpTargetOK (h : Head) : Bool :=
  h.method == connectName ||
    !(httpColon.isPrefixOf (h.target.map lower) || httpsColon.isPrefixOf (h.target.map lower)) ||
    Grammar.httpTarget.isMatch h.target

/-- The framing of the body after the head, or `none` when this library
    refuses the request: a major version other than 1, a missing,
    repeated or invalid Host, a CONNECT without a valid port, an http or
    https target with an empty host or with userinfo,
    Transfer-Encoding together with Content-Length, Transfer-Encoding in
    HTTP/1.0 or with a value other than a list of the one coding
    `chunked`, or Content-Length other than one string of digits. -/
def Head.framing (h : Head) : Option Framing :=
  let hosts := h.fields.filter (·.isNamed hostName)
  if h.major != 1 || hosts.length > 1 || (1 ≤ h.minor && hosts.length != 1) ||
      !hosts.all (fun f => Grammar.hostValue.isMatch f.value) then none
  else if !h.connectOK || !h.httpTargetOK then none
  else
    match h.fields.filter (·.isNamed transferEncodingName),
        h.fields.filter (·.isNamed contentLengthName) with
    | [], [] => some (.length 0)
    | [], [f] => if !f.value.isEmpty && f.value.all isDigit then some (.length (decimal f.value)) else none
    | t :: ts, [] =>
      if 1 ≤ h.minor && Grammar.chunkedList.isMatch (List.intercalate [0x2C] ((t :: ts).map (·.value)))
      then some .chunked else none
    | _, _ => none

end Http
