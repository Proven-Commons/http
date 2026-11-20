import Http.ChunkProofs

open Http

theorem Spec.determineFraming_rejects_nonfinal_chunked (h : Head)
    (hf : determineFraming h = some .chunked) :
    h.major = 1 ∧ 1 ≤ h.minor ∧
      (∀ f, f ∈ h.fields → f.isNamed contentLengthName = false) ∧
      Grammar.chunkedList.isMatch
        (List.intercalate [0x2C]
          ((h.fields.filter (·.isNamed transferEncodingName)).map (·.value))) = true ∧
      h.method ≠ connectName ∧ h.target.head? ≠ some 0x3A :=
  Http.determineFraming_rejects_nonfinal_chunked h hf

theorem Spec.chunked_requires_http11_without_cl (h : Head)
    (hf : determineFraming h = some .chunked) :
    h.major = 1 ∧ 1 ≤ h.minor ∧
      (∀ f, f ∈ h.fields → f.isNamed contentLengthName = false) :=
  Http.chunked_requires_http11_without_cl h hf

theorem Spec.determineFraming_rejects_bad_te (h : Head)
    (hte : ∃ f, f ∈ h.fields ∧ f.isNamed transferEncodingName = true)
    (hbad : Grammar.chunkedList.isMatch
        (List.intercalate [0x2C]
          ((h.fields.filter (·.isNamed transferEncodingName)).map (·.value))) = false) :
    determineFraming h ≠ some .chunked :=
  Http.determineFraming_rejects_bad_te h hte hbad

theorem Spec.determineFraming_rejects_http10_te (h : Head) (hminor : h.minor = 0)
    (hte : ∃ f, f ∈ h.fields ∧ f.isNamed transferEncodingName = true) :
    determineFraming h ≠ some .chunked :=
  Http.determineFraming_rejects_http10_te h hminor hte

theorem Spec.determineFraming_disjoint (h : Head) (f1 f2 : Framing)
    (h1 : determineFraming h = some f1) (h2 : determineFraming h = some f2) :
    f1 = f2 :=
  Http.determineFraming_disjoint h f1 f2 h1 h2

theorem Spec.decodeChunked_encodeChunked (body : List UInt8) (h : body.length ≤ maxUInt64) :
    decodeChunked (encodeChunked body) = some (body, [], []) :=
  Http.decodeChunked_encodeChunked body h

theorem Spec.parseRequest_serializeFixed (h : Head) (body : List UInt8)
    (hf : h.framing = some (.length body.length))
    (hp : parseHead (h.print ++ body) = some (h, body)) :
    parseRequest (h.print ++ body) = some { head := h, body := body, rest := [] } :=
  Http.parseRequest_serializeFixed h body hf hp

theorem Spec.parseRequest_serializeChunked (h : Head) (body : List UInt8)
    (hlen : body.length ≤ maxUInt64) (hf : h.framing = some .chunked)
    (hp : parseHead (h.print ++ encodeChunked body) = some (h, encodeChunked body)) :
    parseRequest (h.print ++ encodeChunked body) =
      some { head := h, body := body, rest := [] } :=
  Http.parseRequest_serializeChunked h body hlen hf hp

theorem Spec.parseRequest_stream_unique (stream tail1 tail2 : List UInt8)
    (msgs1 msgs2 : List (Head × List UInt8))
    (h1 : StreamFrames msgs1 tail1 stream) (h2 : StreamFrames msgs2 tail2 stream)
    (hlen : msgs1.length = msgs2.length) :
    msgs1 = msgs2 ∧ tail1 = tail2 :=
  Http.parseRequest_stream_unique stream tail1 tail2 msgs1 msgs2 h1 h2 hlen
