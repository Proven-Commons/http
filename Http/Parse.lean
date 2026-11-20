/-
  The body after a head `parseHead` has read. A length framing takes that
  many octets. A chunked framing is decoded here, including chunk
  extensions and the trailer section, which is parsed and then dropped.
-/

import Http.Head
import Http.Framing
import Http.Bytes

namespace Http

def crlf : List UInt8 := [13, 10]

def isHex (b : UInt8) : Bool :=
  isDigit b || (97 ≤ b && b ≤ 102) || (65 ≤ b && b ≤ 70)

/-- Chunk extensions: a token name and an optional token or quoted-string
    (RFC 9112, section 7.1.1), not a whitelist of field characters. -/

def skipOWS : List UInt8 → List UInt8
  | 32 :: bs => skipOWS bs
  | 9 :: bs => skipOWS bs
  | bs => bs

def takeToken (bs : List UInt8) : Option (List UInt8 × List UInt8) :=
  let tok := takeWhileBytes isTchar bs
  if tok.isEmpty then none else some (tok, dropBytes tok.length bs)

def isQdtext (b : UInt8) : Bool :=
  b == 9 || b == 32 || b == 33 || (35 ≤ b && b ≤ 91) || (93 ≤ b && b ≤ 126) || b ≥ 128

def isQuotedChar (b : UInt8) : Bool :=
  b == 9 || b == 32 || isVchar b

def parseQuoted : List UInt8 → Option (List UInt8)
  | [] => none
  | 34 :: rest => some rest
  | 92 :: c :: rest => if isQuotedChar c then parseQuoted rest else none
  | b :: rest => if isQdtext b then parseQuoted rest else none

/-- One extension, including the leading semicolon. Returns the unread suffix. -/
def parseOneExt (bs : List UInt8) : Option (List UInt8) :=
  match skipOWS bs with
  | 59 :: rest =>
    match takeToken (skipOWS rest) with
    | none => none
    | some (_, after) =>
      match skipOWS after with
      | 61 :: restEq =>
        match skipOWS restEq with
        | 34 :: quoted => parseQuoted quoted
        | other =>
          match takeToken other with
          | some (_, r) => some r
          | none => none
      | other => some other
  | _ => none

def parseExt (fuel : Nat) : List UInt8 → Bool
  | [] => true
  | bs =>
    match fuel with
    | 0 => false
    | fuel + 1 =>
      match parseOneExt bs with
      | none => false
      | some rest =>
        if rest.length < bs.length then parseExt fuel rest else false

def parseChunkSize (line : List UInt8) : Option Nat :=
  let digits := takeWhileBytes isHex line
  if digits.isEmpty then
    none
  else
    match parseHex digits with
    | none => none
    | some n =>
      if parseExt line.length (dropBytes digits.length line) then some n else none

def parseTrailers (fuel : Nat) (bs : List UInt8) : Option (List Field × List UInt8) :=
  match fuel with
  | 0 => none
  | fuel + 1 =>
    match splitCRLF bs with
    | none => none
    | some ([], rest) => some ([], rest)
    | some (line, rest) =>
      match parseField line with
      | none => none
      | some h =>
        match parseTrailers fuel rest with
        | none => none
        | some (hs, rest') => some (h :: hs, rest')

def decodeLoop (fuel : Nat) (acc : List UInt8) (buf : List UInt8) :
    Option (List UInt8 × List Field × List UInt8) :=
  match fuel with
  | 0 => none
  | fuel + 1 =>
    match splitCRLF buf with
    | none => none
    | some (line, rest) =>
      match parseChunkSize line with
      | none => none
      | some 0 =>
        match parseTrailers rest.length rest with
        | none => none
        | some (ts, rest') => some (acc, ts, rest')
      | some n =>
        if rest.length < n + 2 then
          none
        else
          let data := takeBytes n rest
          match dropBytes n rest with
          | 13 :: 10 :: rest' => decodeLoop fuel (acc ++ data) rest'
          | _ => none

def decodeChunked (buf : List UInt8) : Option (List UInt8 × List Field × List UInt8) :=
  decodeLoop (buf.length + 1) [] buf

def encodeChunked (body : List UInt8) : List UInt8 :=
  if body.isEmpty then
    [48] ++ crlf ++ crlf
  else
    natToHexLower body.length ++ crlf ++ body ++ crlf ++ [48] ++ crlf ++ crlf

/-- A request `parseHead` accepted, together with its body and the octets
    that follow the body. -/
structure FramedRequest where
  head : Head
  body : List UInt8
  rest : List UInt8
  deriving Repr

/-- Read one request. The head is `parseHead`, and the body is framed by
    `Head.framing`: a length takes that many octets, and chunked decoding
    reads the chunk stream. -/
def parseRequest (bs : List UInt8) : Option FramedRequest :=
  match parseHead bs with
  | none => none
  | some (hd, rest) =>
    match hd.framing with
    | none => none
    | some (.length n) =>
      if rest.length < n then none
      else some { head := hd, body := takeBytes n rest, rest := dropBytes n rest }
    | some .chunked =>
      match decodeChunked rest with
      | none => none
      | some (body, _, rest') => some { head := hd, body, rest := rest' }

/-- Two readings of one byte string into the same number of requests. -/
inductive StreamFrames : List (Head × List UInt8) → List UInt8 → List UInt8 → Prop where
  | nil (tail : List UInt8) : StreamFrames [] tail tail
  | cons {stream : List UInt8} {r : FramedRequest} {msgs : List (Head × List UInt8)}
      {tail : List UInt8} :
      parseRequest stream = some r →
      StreamFrames msgs tail r.rest →
      StreamFrames ((r.head, r.body) :: msgs) tail stream

end Http
