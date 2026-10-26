/-
  Command line front end.

    httphead check

  reads a request from standard input and prints its head, one line for
  the request line and one for each field, then how its body is framed:
  `length N`, `chunked`, or `reject` when this library refuses it. It
  prints `invalid` when the input does not start with a request head of
  the grammar. It exits with 0 for a framed request and 1 otherwise.

    httphead serve

  answers requests on standard input, one per line, for the
  differential tests. Octets are sent as lower-case hex digits.

    head HEX          prints  OK, then tab-separated: the head as
                      `Head.print` writes it, in hex, the octets after
                      the head, in hex, and the framing (`length N`,
                      `chunked` or `reject`); or REJECT

  A malformed request prints `error`: an unknown operation, or hex
  digits that are not lower case or not in pairs. A request line may end
  in LF or CR LF.

  Every answer comes from the proved functions in `Http/`: `parseHead`,
  `Head.print` and `Head.framing`. The hex coding and the request
  handling here are covered by the tests, not by a proof.
-/

import Http

open Http

def hexValue (c : Char) : Option Nat :=
  if '0' ≤ c ∧ c ≤ '9' then some (c.toNat - '0'.toNat)
  else if 'a' ≤ c ∧ c ≤ 'f' then some (c.toNat - 'a'.toNat + 10)
  else none

/-- The octets that pairs of hex digits write, with the octets so far in
    `acc`, last first. It calls itself last, so it runs in constant
    stack. -/
def hexBytesFrom (acc : List UInt8) : List Char → Option (List UInt8)
  | [] => some acc.reverse
  | a :: b :: rest =>
    match hexValue a, hexValue b with
    | some hi, some lo => hexBytesFrom ((hi * 16 + lo).toUInt8 :: acc) rest
    | _, _ => none
  | [_] => none

def hexBytes (cs : List Char) : Option (List UInt8) := hexBytesFrom [] cs

def hexDigit (n : Nat) : Char := "0123456789abcdef".toList.getD n '0'

def toHex (bs : List UInt8) : String :=
  String.ofList (bs.flatMap fun b => [hexDigit (b.toNat / 16), hexDigit (b.toNat % 16)])

def framingText : Option Framing → String
  | some (.length n) => s!"length {n}"
  | some .chunked => "chunked"
  | none => "reject"

/-- The answer to one request line, or `none` when it is malformed. -/
def request (line : String) : Option String :=
  match line.splitOn " " with
  | ["head", h] => do
    let bs ← hexBytes h.toList
    pure <| match parseHead bs with
      | some (hd, rest) => s!"OK\t{toHex hd.print}\t{toHex rest}\t{framingText hd.framing}"
      | none => "REJECT"
  | _ => none

/-- The line without its line ending: LF, or CR LF. -/
def chomp (line : String) : String :=
  let cs := line.toList
  if cs.getLast? = some '\n' then
    let cs := cs.dropLast
    String.ofList (if cs.getLast? = some '\r' then cs.dropLast else cs)
  else line

def serve : IO Unit := do
  let stdin ← IO.getStdin
  let stdout ← IO.getStdout
  repeat
    let line ← stdin.getLine
    if line.isEmpty then break
    stdout.putStrLn ((request (chomp line)).getD "error")

/-- Octets as text, with each octet outside printable ASCII as `\xHH`. -/
def escape (bs : List UInt8) : String :=
  String.join (bs.map fun b =>
    if 0x20 ≤ b ∧ b < 0x7F ∧ b ≠ 0x5C then (Char.ofNat b.toNat).toString
    else "\\x" ++ String.ofList [hexDigit (b.toNat / 16), hexDigit (b.toNat % 16)])

def check : IO UInt32 := do
  let stdin ← IO.getStdin
  let input ← stdin.readBinToEnd
  match parseHead input.toList with
  | some (h, _) =>
    IO.println s!"{escape h.method} {escape h.target} HTTP/{h.major}.{h.minor}"
    for f in h.fields do
      IO.println s!"{escape f.name}: {escape f.value}"
    IO.println (framingText h.framing)
    return if h.framing.isSome then 0 else 1
  | none =>
    IO.println "invalid"
    return 1

def usage : String := "usage: httphead check < request\n       httphead serve"

def main (args : List String) : IO UInt32 := do
  match args with
  | ["check"] => check
  | ["serve"] => serve; return 0
  | _ => IO.eprintln usage; return 2
