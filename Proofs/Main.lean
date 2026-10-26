/-
  The proofs of the statements in `Spec.lean`, under the same names.
-/

import Http
import Spec.Abnf
import Spec.Rules
import Spec.Defs
import Proofs.Match
import Proofs.Head
import Proofs.Framing

open Http

/-! ## The grammar notation -/

/-- The matcher decides what a rule matches. -/
theorem Spec.isMatch_iff (r : Re) (s : List UInt8) : r.isMatch s = true ↔ Spec.Matches r s :=
  Proofs.Match.isMatch_iff r s

/-! ## The head -/

/-- `parseHead` reads exactly the request heads of the grammar of
    RFC 9112, RFC 9110 and RFC 3986, after any empty lines, with the choices in
    `Spec/Defs.lean`, and returns the head as written and the octets
    after it. -/
theorem Spec.parseHead_iff (bs : List UInt8) (h : Head) (rest : List UInt8) :
    parseHead bs = some (h, rest) ↔ Spec.Reads bs h rest :=
  Proofs.Head.parseHead_iff bs h rest

/-- A head prints as the grammar writes it, with one SP after each
    colon. -/
theorem Spec.print_eq (h : Head) : h.print = Spec.render h :=
  Proofs.Head.print_eq h

/-- Round trip: printing a head of the grammar, then parsing it, gives
    it back, whatever follows it. -/
theorem Spec.parseHead_print (h : Head) (rest : List UInt8) (hv : Spec.HeadValid h) :
    parseHead (h.print ++ rest) = some (h, rest) :=
  Proofs.Head.parseHead_print h rest hv

/-! ## Acceptance and framing -/

/-- `framing` decides which heads this library accepts, by the version,
    the Host rule of RFC 9112 section 3.2, the CONNECT rule of RFC 9110
    section 9.3.6, the rule of RFC 9110 section 4.2 for http and https
    targets, and RFC 9112 section 6.3 with the choices in
    `Spec/Defs.lean`, and how it frames the body. -/
theorem Spec.framing_iff (h : Head) (fr : Framing) : h.framing = some fr ↔ Spec.Accepts h fr :=
  Proofs.Framing.framing_iff h fr

/-- A head with both Transfer-Encoding and Content-Length is rejected. -/
theorem Spec.framing_te_cl (h : Head) (hte : Spec.named h "transfer-encoding" ≠ [])
    (hcl : Spec.named h "content-length" ≠ []) : h.framing = none :=
  Proofs.Framing.framing_te_cl h hte hcl

/-- A head with two Content-Length field lines is rejected, even when
    they agree. -/
theorem Spec.framing_two_cl (h : Head) (h2 : 2 ≤ (Spec.named h "content-length").length) :
    h.framing = none :=
  Proofs.Framing.framing_two_cl h h2

/-- Test vectors, each with the answer `framing` gives.
    - Accepted, with no body: the examples of RFC 9112 sections 3.2.1 to
      3.2.4, an HTTP/1.0 request with no Host, an empty Host value,
      `CONNECT [::1]:65535`, `CONNECT http:80` (the host `http`), and
      `HTTP://a:/x` (a scheme in upper case and an empty port).
    - Accepted with a body: `Content-Length: 5`, and Transfer-Encoding
      lists of the one coding `chunked`, in any case and with empty
      elements, which RFC 9110 section 5.6.1.2 says a recipient must
      accept.
    - Rejected, the classic shapes of request smuggling: two
      Content-Length values, Content-Length with Transfer-Encoding, a
      Transfer-Encoding value other than a list of the one coding
      `chunked`, chunked twice, two Transfer-Encoding lines that list
      another coding, whitespace before a colon, a folded line, a bare
      LF, a bare CR, and Transfer-Encoding in HTTP/1.0.
    - Rejected too: an HTTP/1.1 request with no Host or with two; a Host
      value with an empty host, `:80` or `:`; a CONNECT with an empty
      port, port 0, a port above 65535, an empty host, or a target that
      is not a host and port; and an http or https target with no
      authority, an empty host or userinfo. -/
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
    (parseHead (Spec.ascii "GET / HTTP/1.1\r\nHost:\r\n\r\n")).bind (·.1.framing) = some (.length 0) ∧
    (parseHead (Spec.ascii "GET / HTTP/1.1\r\nHost: :80\r\n\r\n")).bind (·.1.framing) = none ∧
    (parseHead (Spec.ascii "GET / HTTP/1.1\r\nHost: :\r\n\r\n")).bind (·.1.framing) = none ∧
    -- The CONNECT rule (RFC 9110, section 9.3.6)
    (parseHead (Spec.ascii "CONNECT a: HTTP/1.1\r\nHost: a\r\n\r\n")).bind (·.1.framing) = none ∧
    (parseHead (Spec.ascii "CONNECT a:0 HTTP/1.1\r\nHost: a\r\n\r\n")).bind (·.1.framing) = none ∧
    (parseHead (Spec.ascii "CONNECT a:65536 HTTP/1.1\r\nHost: a\r\n\r\n")).bind (·.1.framing) = none ∧
    (parseHead (Spec.ascii "CONNECT / HTTP/1.1\r\nHost: a\r\n\r\n")).bind (·.1.framing) = none ∧
    (parseHead (Spec.ascii "CONNECT :80 HTTP/1.1\r\nHost: a\r\n\r\n")).bind (·.1.framing) = none ∧
    (parseHead (Spec.ascii "CONNECT [::1]:65535 HTTP/1.1\r\nHost: a\r\n\r\n")).bind
      (·.1.framing) = some (.length 0) ∧
    -- http and https targets (RFC 9110, sections 4.2.1, 4.2.2 and 4.2.4)
    (parseHead (Spec.ascii "GET http: HTTP/1.1\r\nHost: a\r\n\r\n")).bind (·.1.framing) = none ∧
    (parseHead (Spec.ascii "GET http:///a HTTP/1.1\r\nHost: a\r\n\r\n")).bind (·.1.framing) = none ∧
    (parseHead (Spec.ascii "GET https://u@a/ HTTP/1.1\r\nHost: a\r\n\r\n")).bind (·.1.framing) = none ∧
    (parseHead (Spec.ascii "GET HTTP://a:/x HTTP/1.1\r\nHost: a\r\n\r\n")).bind
      (·.1.framing) = some (.length 0) ∧
    (parseHead (Spec.ascii "CONNECT http:80 HTTP/1.1\r\nHost: http\r\n\r\n")).bind
      (·.1.framing) = some (.length 0) := by
  simp only [Head.framing]
  rw [Proofs.Framing.httpTargetOK_chars]
  and_intros <;> decide +kernel
