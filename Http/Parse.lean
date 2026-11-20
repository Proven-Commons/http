import Http.Types
import Http.Bytes
import Http.Framing

namespace Http

def crlf : List UInt8 := [13, 10]

def isFieldByte (b : UInt8) : Bool :=
  b == 9 || b == 32 || isVChar b || b ≥ 128

def skipEmpty : List UInt8 → List UInt8
  | 13 :: 10 :: rest => skipEmpty rest
  | bs => bs

/-- Split on the first `sep`. -/
def splitFirst (sep : UInt8) : List UInt8 → Option (List UInt8 × List UInt8)
  | [] => none
  | b :: bs =>
    if b == sep then some ([], bs)
    else
      match splitFirst sep bs with
      | none => none
      | some (l, r) => some (b :: l, r)

def parseVersion (bs : List UInt8) : Option Version :=
  if bs.length = 8 && takeBytes 7 bs == [72, 84, 84, 80, 47, 49, 46] then
    match bs.getLast? with
    | some d =>
      if d == 48 then some .http10
      else if 49 ≤ d && d ≤ 57 then some .http11
      else none
    | none => none
  else
    none

def versionBytes : Version → List UInt8
  | .http10 => [72, 84, 84, 80, 47, 49, 46, 48]
  | .http11 => [72, 84, 84, 80, 47, 49, 46, 49]

def startsWith (bs pre : List UInt8) : Bool :=
  takeBytes pre.length bs == pre

def startsWithLower (bs pre : List UInt8) : Bool :=
  lowerBytes (takeBytes pre.length bs) == lowerBytes pre && pre.length ≤ bs.length

def httpPrefix : List UInt8 := [104, 116, 116, 112, 58]
def httpsPrefix : List UInt8 := [104, 116, 116, 112, 115, 58]

def vchars (bs : List UInt8) : Bool :=
  allBytes isVChar bs

/-- host [ ":" port ], host nonempty, port absent or digits (empty port allowed). -/
def hostPort (bs : List UInt8) : Bool :=
  if bs.isEmpty || !vchars bs then
    false
  else if bs.head? == some 91 then
    match splitFirst 93 bs with
    | none => false
    | some (lit, rest) =>
      if lit.length ≤ 1 then false
      else
        match rest with
        | [] => true
        | 58 :: port => port.isEmpty || digits port
        | _ => false
  else
    match splitFirst 58 bs with
    | none => true
    | some (host, port) => !host.isEmpty && (port.isEmpty || digits port)

def noUserinfo (bs : List UInt8) : Bool :=
  !(anyBytes (· == 64) bs)

/-- `( "http" / "https" ) "://" host [ ":" port ] path-abempty [ "?" query ]` with a nonempty host and no userinfo. -/
def httpTarget (bs : List UInt8) : Bool :=
  let pre := if startsWithLower bs httpsPrefix then httpsPrefix else httpPrefix
  if !startsWithLower bs pre then
    false
  else
    let rest := dropBytes pre.length bs
    if !startsWith rest ([47, 47]) then
      false
    else
      let authAnd := dropBytes 2 rest
      let auth := takeWhileBytes (fun b => b != 47 && b != 63) authAnd
      let path := dropWhileBytes (fun b => b != 47 && b != 63) authAnd
      vchars bs && noUserinfo auth && hostPort auth && vchars path && !(anyBytes (· == 35) path)

def originTarget (bs : List UInt8) : Bool :=
  bs.head? == some 47 && vchars bs && !(anyBytes (· == 35) bs)

def authorityTarget (bs : List UInt8) : Bool :=
  hostPort bs && !(anyBytes (· == 47) bs) && !(anyBytes (· == 63) bs) && !(anyBytes (· == 35) bs)

def schemeRest (bs : List UInt8) : Bool :=
  match splitFirst 58 bs with
  | none => false
  | some (scheme, rest) =>
    match scheme with
    | [] => false
    | s :: ss =>
      isAlpha s && allBytes (fun b => isAlpha b || isDigit b || b == 43 || b == 45 || b == 46) ss &&
        vchars rest && !(anyBytes (· == 35) rest) &&
        !(lowerBytes scheme == [104, 116, 116, 112]) &&
        !(lowerBytes scheme == [104, 116, 116, 112, 115])

def connectPort (port : List UInt8) : Bool :=
  match parseDec port with
  | some n => digits port && 1 ≤ n && n ≤ 65535
  | none => false

/-- CONNECT target: nonempty host, colon, port 1..65535. Leading zeros allowed. -/
def connectTarget (bs : List UInt8) : Bool :=
  if bs.head? == some 91 then
    match splitFirst 93 bs with
    | none => false
    | some (_, rest) =>
      match rest with
      | 58 :: port => connectPort port && vchars bs && !(anyBytes (· == 64) bs)
      | _ => false
  else
    match splitFirst 58 bs with
    | some (host, port) => !host.isEmpty && connectPort port && vchars bs && !(anyBytes (· == 64) bs) &&
        !(anyBytes (· == 58) host)
    | none => false

def targetOK (method target : List UInt8) : Bool :=
  if method == connectName then
    connectTarget target
  else if startsWithLower target httpPrefix || startsWithLower target httpsPrefix then
    httpTarget target
  else if target == [42] then
    true
  else if target.head? == some 47 then
    originTarget target
  else if schemeRest target then
    true
  else
    authorityTarget target

def hostValueOK (v : List UInt8) : Bool :=
  v.isEmpty || (hostPort v && !(v.head? == some 58))

def countName (n : List UInt8) : List Header → Nat
  | [] => 0
  | h :: hs => (if lowerBytes h.name == n then 1 else 0) + countName n hs

def hostsOK : List Header → Bool
  | [] => true
  | h :: hs =>
    (if lowerBytes h.name == hostNameLower then hostValueOK h.value else true) && hostsOK hs

def requestOK (method target : List UInt8) (v : Version) (hdrs : List Header) : Bool :=
  let hosts := countName hostNameLower hdrs
  let hostVal := hostsOK hdrs
  let hostCount := if v = .http11 then hosts == 1 else hosts ≤ 1
  let connectContent :=
    if method == connectName then
      (teValues hdrs).isEmpty && (match clState hdrs with | .absent => true | .ok 0 => true | _ => false)
    else
      true
  targetOK method target && hostCount && hostVal && connectContent &&
    !(target.head? == some 58)

def parseField (line : List UInt8) : Option Header :=
  if line.head? == some 32 || line.head? == some 9 then
    none
  else
    match splitFirst 58 line with
    | none => none
    | some (name, raw) =>
      let value := trimOWS raw
      if bareToken name && allBytes isFieldByte value then
        some { name, value }
      else
        none

def parseFields (fuel : Nat) (bs : List UInt8) : Option (List Header × List UInt8) :=
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
        match parseFields fuel rest with
        | none => none
        | some (hs, rest') => some (h :: hs, rest')

def parseRequestLine (line : List UInt8) : Option (List UInt8 × List UInt8 × Version) :=
  match splitByte 32 line with
  | [method, target, version] =>
    match parseVersion version with
    | none => none
    | some v =>
      if bareToken method && !target.isEmpty && vchars target then
        some (method, target, v)
      else
        none
  | _ => none

def parseHead (bs : List UInt8) : Option (RequestHead × List UInt8) :=
  match splitCRLF (skipEmpty bs) with
  | none => none
  | some (line, rest) =>
    match parseRequestLine line with
    | none => none
    | some (method, target, v) =>
      match parseFields rest.length rest with
      | none => none
      | some (headers, rest') =>
        if requestOK method target v headers then
          some ({ method, target, version := v, headers }, rest')
        else
          none

-- Chunk extensions: token name and an optional token or quoted-string.

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
  b == 9 || b == 32 || isVChar b || b ≥ 128

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

def parseTrailers (fuel : Nat) (bs : List UInt8) : Option (List Header × List UInt8) :=
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
    Option (List UInt8 × List Header × List UInt8) :=
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

def decodeChunked (buf : List UInt8) : Option (List UInt8 × List Header × List UInt8) :=
  decodeLoop (buf.length + 1) [] buf

def encodeChunked (body : List UInt8) : List UInt8 :=
  if body.isEmpty then
    [48] ++ crlf ++ crlf
  else
    natToHexLower body.length ++ crlf ++ body ++ crlf ++ [48] ++ crlf ++ crlf

def renderHeader (h : Header) : List UInt8 :=
  h.name ++ [58, 32] ++ h.value ++ crlf

def renderHeaders : List Header → List UInt8
  | [] => []
  | h :: hs => renderHeader h ++ renderHeaders hs

def renderHead (hd : RequestHead) : List UInt8 :=
  hd.method ++ [32] ++ hd.target ++ [32] ++ versionBytes hd.version ++ crlf ++
    renderHeaders hd.headers ++ crlf

def noTrail : List UInt8 → Bool
  | [] => true
  | [b] => !isOWS b
  | _ :: bs => noTrail bs

/-- No leading or trailing optional whitespace, and only field bytes. -/
def canonicalValue (v : List UInt8) : Bool :=
  match v with
  | [] => true
  | b :: bs => !isOWS b && noTrail (b :: bs) && allBytes isFieldByte v

def canonicalHeader (h : Header) : Bool :=
  bareToken h.name && canonicalValue h.value

def headersCanonical : List Header → Bool
  | [] => true
  | h :: hs => canonicalHeader h && headersCanonical hs

def acceptHead (hd : RequestHead) : Bool :=
  bareToken hd.method && !hd.target.isEmpty && vchars hd.target &&
    headersCanonical hd.headers &&
    requestOK hd.method hd.target hd.version hd.headers

def serializeFixed (hd : RequestHead) (body : List UInt8) : Option (List UInt8) :=
  match determineFraming hd.version hd.headers with
  | some (.fixed n) =>
    if n = body.length && acceptHead hd then some (renderHead hd ++ body) else none
  | _ => none

def serializeChunked (hd : RequestHead) (body : List UInt8) : Option (List UInt8) :=
  if hd.version = .http11 && determineFraming hd.version hd.headers = some .chunked &&
      acceptHead hd && body.length ≤ maxUInt64 then
    some (renderHead hd ++ encodeChunked body)
  else
    none

def parseRequest (bs : List UInt8) : Option FramedRequest :=
  match parseHead bs with
  | none => none
  | some (hd, rest) =>
    match determineFraming hd.version hd.headers with
    | none => none
    | some (.fixed n) =>
      if rest.length < n then none
      else some { head := hd, body := takeBytes n rest, rest := dropBytes n rest }
    | some .chunked =>
      match decodeChunked rest with
      | none => none
      | some (body, _, rest') => some { head := hd, body, rest := rest' }

end Http
