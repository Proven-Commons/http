/-
  The statements: what the code in `Http/` must do. A reviewer approves
  this file, with the definitions in `Spec/` and the types in
  `Http/Types.lean` and `Http/Abnf.lean`. Each `sorry` here is proved in
  `Proofs/`, and `lake comparator` checks that each proof proves
  exactly the statement here.
-/

import Http
import Http.ChunkProofs
import Spec.Abnf
import Spec.Rules
import Spec.Defs

open Http

/-! ## The grammar notation -/

/-- The matcher decides what a rule matches. -/
theorem Spec.isMatch_iff (r : Re) (s : List UInt8) : r.isMatch s = true ↔ Spec.Matches r s := sorry

/-! ## The head -/

/-- `parseHead` reads exactly the request heads of the grammar of
    RFC 9112, RFC 9110 and RFC 3986, after any empty lines, with the choices in
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
    section 9.3.6, the rule of RFC 9110 section 4.2 for http and https
    targets, the empty-host rule for an authority-form target (RFC 9112
    section 3.3, then RFC 9110 section 4.2.1: a target that begins with
    `:`), no content on CONNECT (RFC 9110 section 9.3.6: Transfer-Encoding,
    or a Content-Length that is not 0), and RFC 9112 section 6.3 with the
    choices in `Spec/Defs.lean`, and how it frames the body. -/
theorem Spec.framing_iff (h : Head) (fr : Framing) : h.framing = some fr ↔ Spec.Accepts h fr := sorry

/-- A head with both Transfer-Encoding and Content-Length is rejected. -/
theorem Spec.framing_te_cl (h : Head) (hte : Spec.named h "transfer-encoding" ≠ [])
    (hcl : Spec.named h "content-length" ≠ []) : h.framing = none := sorry

/-- A head with two Content-Length field lines is rejected, even when
    they agree. -/
theorem Spec.framing_two_cl (h : Head) (h2 : 2 ≤ (Spec.named h "content-length").length) :
    h.framing = none := sorry

/-- Test vectors, each with the answer `framing` gives.
    - Accepted, with no body: the examples of RFC 9112 sections 3.2.1 to
      3.2.4, an HTTP/1.0 request with no Host, an empty Host value,
      `CONNECT [::1]:65535`, `CONNECT http:80` (the host `http`), and
      `HTTP://a:/x` (a scheme in upper case and an empty port).
    - Accepted with a body: `Content-Length: 5`, and Transfer-Encoding
      lists of the one coding `chunked`, in any case, with empty
      elements, which RFC 9110 section 5.6.1.2 says a recipient must
      accept, and after a tab or more than one space.
    - Rejected, the classic shapes of request smuggling: two
      Content-Length values, Content-Length with Transfer-Encoding, a
      Transfer-Encoding value other than a list of the one coding
      `chunked`, chunked twice, two Transfer-Encoding lines that list
      another coding, `chunked` with a parameter, whitespace before a
      colon, a folded line, a bare LF, a bare CR, and Transfer-Encoding
      in HTTP/1.0.
    - Rejected too: an HTTP/1.1 request with no Host or with two; a Host
      value with an empty host, `:80` or `:`; a CONNECT with an empty
      port, port 0, a port above 65535, an empty host, or a target that
      is not a host and port; a CONNECT with content, by Content-Length
      or Transfer-Encoding (a CONNECT with `Content-Length: 0` is
      accepted); an authority-form target with an empty host for any
      method, `GET :80` and `OPTIONS :`; and an http or https target with
      no authority, an empty host or userinfo. -/
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
    -- Optional whitespace before the value: a tab, and two spaces
    (parseHead (Spec.ascii "POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding:\tchunked\r\n\r\n")).bind
      (·.1.framing) = some .chunked ∧
    (parseHead (Spec.ascii "POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding:  chunked\r\n\r\n")).bind
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
    (parseHead (Spec.ascii "POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked;a=b\r\n\r\n")).bind
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
    -- A CONNECT has no content (RFC 9110, section 9.3.6)
    (parseHead (Spec.ascii "CONNECT a:443 HTTP/1.1\r\nHost: a\r\nContent-Length: 5\r\n\r\nhello")).bind
      (·.1.framing) = none ∧
    (parseHead (Spec.ascii "CONNECT a:443 HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n")).bind
      (·.1.framing) = none ∧
    (parseHead (Spec.ascii "CONNECT a:443 HTTP/1.1\r\nHost: a\r\nContent-Length: 0\r\n\r\n")).bind
      (·.1.framing) = some (.length 0) ∧
    -- An authority-form target with an empty host, for any method (RFC 9112, section 3.3)
    (parseHead (Spec.ascii "GET :80 HTTP/1.1\r\nHost: a\r\n\r\n")).bind (·.1.framing) = none ∧
    (parseHead (Spec.ascii "OPTIONS : HTTP/1.1\r\nHost: a\r\n\r\n")).bind (·.1.framing) = none ∧
    -- http and https targets (RFC 9110, sections 4.2.1, 4.2.2 and 4.2.4)
    (parseHead (Spec.ascii "GET http: HTTP/1.1\r\nHost: a\r\n\r\n")).bind (·.1.framing) = none ∧
    (parseHead (Spec.ascii "GET http:///a HTTP/1.1\r\nHost: a\r\n\r\n")).bind (·.1.framing) = none ∧
    (parseHead (Spec.ascii "GET https://u@a/ HTTP/1.1\r\nHost: a\r\n\r\n")).bind (·.1.framing) = none ∧
    (parseHead (Spec.ascii "GET HTTP://a:/x HTTP/1.1\r\nHost: a\r\n\r\n")).bind
      (·.1.framing) = some (.length 0) ∧
    (parseHead (Spec.ascii "CONNECT http:80 HTTP/1.1\r\nHost: http\r\n\r\n")).bind
      (·.1.framing) = some (.length 0) := sorry

/-! ## Chunked framing and the body -/

/-- Chunked framing is HTTP/1.1 or a later 1.x, with no Content-Length
    field, and the combined Transfer-Encoding value matches a list of the
    one coding `chunked` (empty elements allowed). The method is not
    `CONNECT`, and the target does not begin with `:`. -/
theorem Spec.determineFraming_rejects_nonfinal_chunked (h : Head)
    (hf : determineFraming h = some .chunked) :
    h.major = 1 ∧ 1 ≤ h.minor ∧
      (∀ f, f ∈ h.fields → f.isNamed contentLengthName = false) ∧
      Grammar.chunkedList.isMatch
        (List.intercalate [0x2C]
          ((h.fields.filter (·.isNamed transferEncodingName)).map (·.value))) = true ∧
      h.method ≠ connectName ∧ h.target.head? ≠ some 0x3A :=
  Http.determineFraming_rejects_nonfinal_chunked h hf

/-- The same hypothesis, without the claim about the combined
    Transfer-Encoding value. -/
theorem Spec.chunked_requires_http11_without_cl (h : Head)
    (hf : determineFraming h = some .chunked) :
    h.major = 1 ∧ 1 ≤ h.minor ∧
      (∀ f, f ∈ h.fields → f.isNamed contentLengthName = false) :=
  Http.chunked_requires_http11_without_cl h hf

/-- A Transfer-Encoding field whose combined value is not that list is
    not framed as chunked. -/
theorem Spec.determineFraming_rejects_bad_te (h : Head)
    (hte : ∃ f, f ∈ h.fields ∧ f.isNamed transferEncodingName = true)
    (hbad : Grammar.chunkedList.isMatch
        (List.intercalate [0x2C]
          ((h.fields.filter (·.isNamed transferEncodingName)).map (·.value))) = false) :
    determineFraming h ≠ some .chunked :=
  Http.determineFraming_rejects_bad_te h hte hbad

/-- HTTP/1.0 with a Transfer-Encoding field is not framed as chunked. -/
theorem Spec.determineFraming_rejects_http10_te (h : Head) (hminor : h.minor = 0)
    (hte : ∃ f, f ∈ h.fields ∧ f.isNamed transferEncodingName = true) :
    determineFraming h ≠ some .chunked :=
  Http.determineFraming_rejects_http10_te h hminor hte

/-- A head has at most one framing. -/
theorem Spec.determineFraming_disjoint (h : Head) (f1 f2 : Framing)
    (h1 : determineFraming h = some f1) (h2 : determineFraming h = some f2) :
    f1 = f2 :=
  Http.determineFraming_disjoint h f1 f2 h1 h2

/-- `decodeChunked` reads what `encodeChunked` wrote, for a body of at
    most 2^64 − 1 octets. An empty body is the chunk `0`. -/
theorem Spec.decodeChunked_encodeChunked (body : List UInt8) (h : body.length ≤ maxUInt64) :
    decodeChunked (encodeChunked body) = some (body, [], []) :=
  Http.decodeChunked_encodeChunked body h

/-- A length-framed body that `parseHead` returns after the printed head
    is the body `parseRequest` returns, with nothing after it. -/
theorem Spec.parseRequest_serializeFixed (h : Head) (body : List UInt8)
    (hf : h.framing = some (.length body.length))
    (hp : parseHead (h.print ++ body) = some (h, body)) :
    parseRequest (h.print ++ body) = some { head := h, body := body, rest := [] } :=
  Http.parseRequest_serializeFixed h body hf hp

/-- A chunked body that `encodeChunked` wrote, after a printed head that
    `parseHead` returns and that is framed as chunked, is the body
    `parseRequest` returns. -/
theorem Spec.parseRequest_serializeChunked (h : Head) (body : List UInt8)
    (hlen : body.length ≤ maxUInt64) (hf : h.framing = some .chunked)
    (hp : parseHead (h.print ++ encodeChunked body) = some (h, encodeChunked body)) :
    parseRequest (h.print ++ encodeChunked body) =
      some { head := h, body := body, rest := [] } :=
  Http.parseRequest_serializeChunked h body hlen hf hp

/-- Two readings of one byte string into the same number of requests
    agree on the requests and on the octets left over. -/
theorem Spec.parseRequest_stream_unique (stream tail1 tail2 : List UInt8)
    (msgs1 msgs2 : List (Head × List UInt8))
    (h1 : StreamFrames msgs1 tail1 stream) (h2 : StreamFrames msgs2 tail2 stream)
    (hlen : msgs1.length = msgs2.length) :
    msgs1 = msgs2 ∧ tail1 = tail2 :=
  Http.parseRequest_stream_unique stream tail1 tail2 msgs1 msgs2 h1 h2 hlen
