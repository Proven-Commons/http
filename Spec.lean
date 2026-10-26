/-
  The statements: what the code in `Http/` must do. A reviewer approves
  this file, with the definitions in `Spec/` and the types in
  `Http/Types.lean` and `Http/Abnf.lean`. Each `sorry` here is proved in
  `Proofs/`, and `lake comparator` checks that each proof proves
  exactly the statement here.
-/

import Http
import Spec.Abnf
import Spec.Rules
import Spec.Defs

open Http

/-! ## The grammar notation -/

/-- The matcher decides what a rule matches. -/
theorem Spec.isMatch_iff (r : Re) (s : List UInt8) : r.isMatch s = true ↔ Spec.Matches r s := sorry

/-! ## The head -/

/-- `parseHead` reads exactly the request heads of the grammar of
    RFC 9112 and RFC 9110, after any empty lines, with the choices in
    `Spec/Defs.lean`, and returns the head as written and the octets
    after it. -/
theorem Spec.parseHead_iff (bs : List UInt8) (h : Head) (rest : List UInt8) :
    parseHead bs = some (h, rest) ↔ Spec.Reads bs h rest := sorry

/-- A head prints as the grammar writes it, with one SP after each
    colon. -/
theorem Spec.print_eq (h : Head) : h.print = Spec.render h := sorry

/-- Round trip: printing a head of the grammar, then parsing it, gives
    it back, whatever follows it. -/
theorem Spec.parseHead_print (h : Head) (rest : List UInt8) (hv : Spec.HeadValid h) :
    parseHead (h.print ++ rest) = some (h, rest) := sorry

/-! ## Acceptance and framing -/

/-- `framing` decides which heads this library accepts, by the version,
    the Host rule of RFC 9112 section 3.2, the CONNECT rule of RFC 9110
    section 9.3.6, and section 6.3 with the choices in `Spec/Defs.lean`,
    and how it frames the body. -/
theorem Spec.framing_iff (h : Head) (fr : Framing) : h.framing = some fr ↔ Spec.Accepts h fr := sorry

/-- A head with both Transfer-Encoding and Content-Length is rejected. -/
theorem Spec.framing_te_cl (h : Head) (hte : Spec.named h "transfer-encoding" ≠ [])
    (hcl : Spec.named h "content-length" ≠ []) : h.framing = none := sorry

/-- A head with two Content-Length field lines is rejected, even when
    they agree. -/
theorem Spec.framing_two_cl (h : Head) (h2 : 2 ≤ (Spec.named h "content-length").length) :
    h.framing = none := sorry

/-- The examples of RFC 9112 sections 3.2.1 to 3.2.4 are accepted, with
    no body. So are Transfer-Encoding lists of the one coding `chunked`
    with empty elements, which RFC 9110 section 5.6.1.2 says a recipient
    must accept. The classic shapes of request smuggling are rejected:
    two Content-Length values, Content-Length with Transfer-Encoding, a
    Transfer-Encoding value other than a list of the one coding
    `chunked`, chunked twice, two Transfer-Encoding lines that list
    another coding, whitespace before a colon, a folded line, a bare LF,
    a bare CR, and Transfer-Encoding in HTTP/1.0. So are an HTTP/1.1
    request with no Host or with two, and a CONNECT with an empty port,
    port 0, a port above 65535, or a target that is not a host and
    port. -/
theorem Spec.head_vectors :
    -- Sections 3.2.1 to 3.2.4
    (parseHead (Spec.ascii "GET /where?q=now HTTP/1.1\r\nHost: www.example.org\r\n\r\n")).bind
      (·.1.framing) = some (.length 0) ∧
    (parseHead (Spec.ascii
      "GET http://www.example.org/pub/WWW/TheProject.html HTTP/1.1\r\nHost: www.example.org\r\n\r\n")).bind
      (·.1.framing) = some (.length 0) ∧
    (parseHead (Spec.ascii "CONNECT www.example.com:80 HTTP/1.1\r\nHost: www.example.com\r\n\r\n")).bind
      (·.1.framing) = some (.length 0) ∧
    (parseHead (Spec.ascii "OPTIONS * HTTP/1.1\r\nHost: www.example.org:8001\r\n\r\n")).bind
      (·.1.framing) = some (.length 0) ∧
    -- A body framed by length and by chunked coding
    (parseHead (Spec.ascii "POST /a HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\n\r\nhello")).map
      (fun p => (p.1.framing, p.2)) = some (some (.length 5), Spec.ascii "hello") ∧
    (parseHead (Spec.ascii "POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: Chunked\r\n\r\n")).bind
      (·.1.framing) = some .chunked ∧
    -- Lists with empty elements (RFC 9110, section 5.6.1.2)
    (parseHead (Spec.ascii "POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked,\r\n\r\n")).bind
      (·.1.framing) = some .chunked ∧
    (parseHead (Spec.ascii "POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: , chunked\r\n\r\n")).bind
      (·.1.framing) = some .chunked ∧
    (parseHead (Spec.ascii
      "POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nTransfer-Encoding:\r\n\r\n")).bind
      (·.1.framing) = some .chunked ∧
    -- Smuggling shapes
    (parseHead (Spec.ascii
      "POST /a HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nContent-Length: 6\r\n\r\n")).bind
      (·.1.framing) = none ∧
    (parseHead (Spec.ascii
      "POST /a HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nTransfer-Encoding: chunked\r\n\r\n")).bind
      (·.1.framing) = none ∧
    (parseHead (Spec.ascii "POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: xchunked\r\n\r\n")).bind
      (·.1.framing) = none ∧
    (parseHead (Spec.ascii
      "POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked, identity\r\n\r\n")).bind
      (·.1.framing) = none ∧
    (parseHead (Spec.ascii
      "POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked, chunked\r\n\r\n")).bind
      (·.1.framing) = none ∧
    (parseHead (Spec.ascii
      "POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nTransfer-Encoding: x\r\n\r\n")).bind
      (·.1.framing) = none ∧
    parseHead (Spec.ascii "POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding : chunked\r\n\r\n") = none ∧
    parseHead (Spec.ascii "POST /a HTTP/1.1\r\nHost: x\r\nX: y\r\n Transfer-Encoding: chunked\r\n\r\n") =
      none ∧
    parseHead (Spec.ascii "POST /a HTTP/1.1\r\nHost: x\nTransfer-Encoding: chunked\r\n\r\n") = none ∧
    parseHead (Spec.ascii "POST /a HTTP/1.1\r\nHost: x\rTransfer-Encoding: chunked\r\n\r\n") = none ∧
    (parseHead (Spec.ascii "POST /a HTTP/1.0\r\nTransfer-Encoding: chunked\r\n\r\n")).bind
      (·.1.framing) = none ∧
    -- The Host rule
    (parseHead (Spec.ascii "GET / HTTP/1.1\r\n\r\n")).bind (·.1.framing) = none ∧
    (parseHead (Spec.ascii "GET / HTTP/1.1\r\nHost: a\r\nHost: a\r\n\r\n")).bind (·.1.framing) = none ∧
    (parseHead (Spec.ascii "GET / HTTP/1.0\r\n\r\n")).bind (·.1.framing) = some (.length 0) ∧
    -- The CONNECT rule (RFC 9110, section 9.3.6)
    (parseHead (Spec.ascii "CONNECT a: HTTP/1.1\r\nHost: a\r\n\r\n")).bind (·.1.framing) = none ∧
    (parseHead (Spec.ascii "CONNECT a:0 HTTP/1.1\r\nHost: a\r\n\r\n")).bind (·.1.framing) = none ∧
    (parseHead (Spec.ascii "CONNECT a:65536 HTTP/1.1\r\nHost: a\r\n\r\n")).bind (·.1.framing) = none ∧
    (parseHead (Spec.ascii "CONNECT / HTTP/1.1\r\nHost: a\r\n\r\n")).bind (·.1.framing) = none ∧
    (parseHead (Spec.ascii "CONNECT [::1]:65535 HTTP/1.1\r\nHost: a\r\n\r\n")).bind
      (·.1.framing) = some (.length 0) := sorry
