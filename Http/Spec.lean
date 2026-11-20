import Http.Lemmas

namespace Http.Spec

open Http

theorem splitCRLF_sound (bs line rest : List UInt8) :
    splitCRLF bs = some (line, rest) ↔
      NoBareLineBreak line ∧ bs = line ++ [0x0D, 0x0A] ++ rest := by
  simpa [NoBareLineBreak, noBareLineBreak] using Http.splitCRLF_sound bs line rest

theorem splitCRLF_prefix_free (bs line rest extra : List UInt8)
    (h : splitCRLF bs = some (line, rest)) :
    splitCRLF (bs ++ extra) = some (line, rest ++ extra) :=
  Http.splitCRLF_prefix_free bs line rest extra h

theorem parseDec_printDec (n : Nat) (h : n ≤ maxUInt64) :
    parseDec (natToDecChars n) = some n :=
  Http.parseDec_printDec n h

theorem parseHex_printHex (n : Nat) (h : n ≤ maxUInt64) :
    parseHex (natToHexLower n) = some n :=
  Http.parseHex_printHex n h

theorem determineFraming_disjoint (v : Version) (hdrs : List Header) (f1 f2 : Framing)
    (h1 : determineFraming v hdrs = some f1) (h2 : determineFraming v hdrs = some f2) :
    f1 = f2 :=
  Http.determineFraming_disjoint v hdrs f1 f2 h1 h2

theorem determineFraming_rejects_cl_and_te (v : Version) (hdrs : List Header)
    (hte : ∃ h, h ∈ hdrs ∧ lowerBytes h.name = teNameLower)
    (hcl : ∃ h, h ∈ hdrs ∧ lowerBytes h.name = clNameLower) :
    determineFraming v hdrs = none :=
  Http.determineFraming_rejects_cl_and_te v hdrs hte hcl

theorem determineFraming_rejects_http10_te (hdrs : List Header)
    (hte : ∃ h, h ∈ hdrs ∧ lowerBytes h.name = teNameLower) :
    determineFraming .http10 hdrs = none :=
  Http.determineFraming_rejects_http10_te hdrs hte

/-- Chunked framing is HTTP/1.1, with no Content-Length, and the combined
Transfer-Encoding list is exactly `[chunked]` after empty elements are dropped. -/
theorem determineFraming_rejects_nonfinal_chunked (v : Version) (hdrs : List Header)
    (h : determineFraming v hdrs = some .chunked) :
    v = .http11 ∧ (∀ hdr, hdr ∈ hdrs → lowerBytes hdr.name ≠ clNameLower) ∧
      normalizedCodings hdrs = some [chunkedToken] :=
  Http.determineFraming_rejects_nonfinal_chunked v hdrs h

theorem chunked_requires_http11_without_cl (v : Version) (hdrs : List Header)
    (h : determineFraming v hdrs = some .chunked) :
    v = .http11 ∧ ∀ hdr, hdr ∈ hdrs → lowerBytes hdr.name ≠ clNameLower :=
  Http.chunked_requires_http11_without_cl v hdrs h

theorem determineFraming_rejects_bad_te (v : Version) (hdrs : List Header)
    (hte : ∃ h, h ∈ hdrs ∧ lowerBytes h.name = teNameLower)
    (hbad : normalizedCodings hdrs ≠ some [chunkedToken]) :
    determineFraming v hdrs = none :=
  Http.determineFraming_rejects_bad_te v hdrs hte hbad

theorem decodeChunked_encodeChunked (body : List UInt8) (h : body.length ≤ maxUInt64) :
    decodeChunked (encodeChunked body) = some (body, [], []) :=
  Http.decodeChunked_encodeChunked body h

theorem decodeChunked_prefix_free (buf body rest extra : List UInt8) (trailers : List Header)
    (h : decodeChunked buf = some (body, trailers, rest)) :
    decodeChunked (buf ++ extra) = some (body, trailers, rest ++ extra) :=
  Http.decodeChunked_prefix_free buf body rest extra trailers h

theorem parseRequest_serializeFixed (hd : RequestHead) (body wire : List UInt8)
    (hs : serializeFixed hd body = some wire) :
    ∃ r, parseRequest wire = some r ∧ r.head.method = hd.method ∧
      r.head.target = hd.target ∧ r.head.version = hd.version ∧
      r.body = body ∧ r.rest = [] :=
  Http.parseRequest_serializeFixed hd body wire hs

theorem parseRequest_serializeChunked (hd : RequestHead) (body wire : List UInt8)
    (hs : serializeChunked hd body = some wire) :
    ∃ r, parseRequest wire = some r ∧ r.head.method = hd.method ∧
      r.head.target = hd.target ∧ r.head.version = .http11 ∧
      r.body = body ∧ r.rest = [] :=
  Http.parseRequest_serializeChunked hd body wire hs

theorem parseRequest_prefix_free (stream extra : List UInt8) (r : FramedRequest)
    (h : parseRequest stream = some r) :
    parseRequest (stream ++ extra) = some { r with rest := r.rest ++ extra } :=
  Http.parseRequest_prefix_free stream extra r h

theorem parseRequest_stream_unique (stream tail1 tail2 : List UInt8)
    (msgs1 msgs2 : List (RequestHead × List UInt8))
    (hlen : msgs1.length = msgs2.length)
    (h1 : StreamFrames msgs1 tail1 stream)
    (h2 : StreamFrames msgs2 tail2 stream) :
    msgs1 = msgs2 ∧ tail1 = tail2 :=
  Http.parseRequest_stream_unique stream tail1 tail2 msgs1 msgs2 hlen h1 h2

theorem reject_smuggling_vectors :
    ∀ v, v ∈ smugglingVectors → parseRequest v = none :=
  Http.reject_smuggling_vectors

end Http.Spec
