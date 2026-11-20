namespace Http

inductive Version where
  | http10
  | http11
  deriving DecidableEq, Repr

structure Header where
  name : List UInt8
  value : List UInt8
  deriving DecidableEq, Repr

structure RequestHead where
  method : List UInt8
  target : List UInt8
  version : Version
  headers : List Header
  deriving DecidableEq, Repr

inductive Framing where
  | fixed (len : Nat)
  | chunked
  deriving DecidableEq, Repr

structure FramedRequest where
  head : RequestHead
  body : List UInt8
  rest : List UInt8
  deriving DecidableEq, Repr

def maxUInt64 : Nat := 2 ^ 64 - 1

def teNameLower : List UInt8 := [116, 114, 97, 110, 115, 102, 101, 114, 45, 101, 110, 99, 111, 100, 105, 110, 103]

def clNameLower : List UInt8 := [99, 111, 110, 116, 101, 110, 116, 45, 108, 101, 110, 103, 116, 104]

def hostNameLower : List UInt8 := [104, 111, 115, 116]

def chunkedToken : List UInt8 := [99, 104, 117, 110, 107, 101, 100]

def connectName : List UInt8 := [67, 79, 78, 78, 69, 67, 84]

end Http
