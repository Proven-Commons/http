import Http.Types
import Http.Bytes

namespace Http

def isDigit (b : UInt8) : Bool :=
  48 ≤ b && b ≤ 57

def isHex (b : UInt8) : Bool :=
  isDigit b || (97 ≤ b && b ≤ 102) || (65 ≤ b && b ≤ 70)

def isAlpha (b : UInt8) : Bool :=
  (65 ≤ b && b ≤ 90) || (97 ≤ b && b ≤ 122)

def isTchar (b : UInt8) : Bool :=
  isAlpha b || isDigit b || b == 33 || b == 35 || b == 36 || b == 37 || b == 38 ||
    b == 39 || b == 42 || b == 43 || b == 45 || b == 46 || b == 94 || b == 95 ||
    b == 96 || b == 124 || b == 126

def isVChar (b : UInt8) : Bool :=
  33 ≤ b && b ≤ 126

/-- A transfer-coding token: no parameters, no whitespace. -/
def bareToken : List UInt8 → Bool
  | [] => false
  | bs => allBytes isTchar bs

def joinComma : List (List UInt8) → List UInt8
  | [] => []
  | [v] => v
  | v :: vs => v ++ [44] ++ joinComma vs

def teValues : List Header → List (List UInt8)
  | [] => []
  | h :: hs =>
    if lowerBytes h.name == teNameLower then h.value :: teValues hs else teValues hs

def mapTrim : List (List UInt8) → List (List UInt8)
  | [] => []
  | b :: bs => trimOWS b :: mapTrim bs

def commaElements (bs : List UInt8) : List (List UInt8) :=
  mapTrim (splitByte 44 bs)

def dropEmpty : List (List UInt8) → List (List UInt8)
  | [] => []
  | b :: bs => if b.isEmpty then dropEmpty bs else b :: dropEmpty bs

def allBare : List (List UInt8) → Bool
  | [] => true
  | b :: bs => bareToken b && allBare bs

def mapLower : List (List UInt8) → List (List UInt8)
  | [] => []
  | b :: bs => lowerBytes b :: mapLower bs

/-- Transfer-coding list after combining field lines, dropping empty
elements, and rejecting a parameter or any other non-token. No
Transfer-Encoding field gives `some []`. -/
def normalizedCodings (hdrs : List Header) : Option (List (List UInt8)) :=
  let vals := teValues hdrs
  if vals.isEmpty then
    some []
  else
    let nonempty := dropEmpty (commaElements (joinComma vals))
    if allBare nonempty then
      some (mapLower nonempty)
    else
      none

def clHeaders : List Header → List Header
  | [] => []
  | h :: hs =>
    if lowerBytes h.name == clNameLower then h :: clHeaders hs else clHeaders hs

def digits : List UInt8 → Bool
  | [] => false
  | bs => allBytes isDigit bs

inductive ClState where
  | absent
  | ok (n : Nat)
  | bad
  deriving DecidableEq, Repr

def clState (hdrs : List Header) : ClState :=
  match clHeaders hdrs with
  | [] => .absent
  | [h] =>
    if digits h.value then
      match parseDec h.value with
      | some n => .ok n
      | none => .bad
    else
      .bad
  | _ => .bad

/-- Body framing from the version and the header list. Chunked framing is
returned only for HTTP/1.1 whose normalized Transfer-Encoding list is exactly
`[chunked]` and which has no Content-Length. -/
def determineFraming (v : Version) (hdrs : List Header) : Option Framing :=
  match normalizedCodings hdrs with
  | none => none
  | some cs =>
    match clState hdrs with
    | .bad => none
    | .ok n =>
      if cs.isEmpty && (teValues hdrs).isEmpty then some (.fixed n) else none
    | .absent =>
      match cs with
      | [] =>
        if (teValues hdrs).isEmpty then some (.fixed 0) else none
      | [c] =>
        if v = .http11 && c = chunkedToken then some .chunked else none
      | _ => none

end Http
