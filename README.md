# http: HTTP/1.1 request framing and chunked decoding, proved

This library specifies, frames, and serializes HTTP/1.x request messages in Lean 4 following RFC 9112 (Sections 2, 3, 5, 6, and 7.1), targeting machine-checked theorems for prefix-free stream framing and rejection of HTTP request-boundary ambiguities (`CL.TE`, `TE.CL`, `TE.TE`, `HTTP/1.0` `Transfer-Encoding`, and malformed chunk terminators).

Status: in progress. The specification has not yet been approved by an independent reviewer on the org's list, so this is not yet verified.

## Planned and Drafted Theorems (`Http.Spec` / `Http.Proofs`)

| Claim | Theorem |
| :--- | :--- |
| `splitCRLF` splits at the earliest `CRLF` with no bare `CR` or `LF` in the line. | `Http.Spec.splitCRLF_sound` |
| `splitCRLF` is prefix-free when trailing pipelined bytes are appended. | `Http.Spec.splitCRLF_prefix_free` |
| Decimal formatting of numbers below `2^64` parses back to the same number. | `Http.Spec.parseDec_printDec` |
| Hexadecimal formatting of numbers below `2^64` parses back to the same number. | `Http.Spec.parseHex_printHex` |
| Body framing resolution assigns at most one framing mode to any header list. | `Http.Spec.determineFraming_disjoint` |
| Requests carrying both `Transfer-Encoding` and `Content-Length` are always rejected. | `Http.Spec.determineFraming_rejects_cl_and_te` |
| `HTTP/1.0` requests carrying `Transfer-Encoding` are always rejected (EEF-CVE-2026-94194). | `Http.Spec.determineFraming_rejects_http10_te` |
| Chunked framing requires `HTTP/1.1` and zero `Content-Length` headers. | `Http.Spec.determineFraming_rejects_nonfinal_chunked` |
| `encodeChunked` round-trips through `decodeChunked` with empty remainder. | `Http.Spec.decodeChunked_encodeChunked` |
| `decodeChunked` is prefix-free across pipelined TCP byte streams. | `Http.Spec.decodeChunked_prefix_free` |
| Canonical fixed-length request serialization round-trips through `parseRequest`. | `Http.Spec.parseRequest_serializeFixed` |
| Canonical chunked request serialization round-trips through `parseRequest`. | `Http.Spec.parseRequest_serializeChunked` |
| `parseRequest` is prefix-free when pipelined bytes follow on the TCP stream. | `Http.Spec.parseRequest_prefix_free` |
| Multi-message TCP streams decompose uniquely under `StreamFrames`. | `Http.Spec.parseRequest_stream_unique` |
| Normative RFC 9112 / CVE boundary-ambiguity vectors are rejected. | `Http.Spec.reject_smuggling_vectors` |

## What is not proved

- Hex CLI decoding/encoding in `Main.lean` (covered by differential tests).
- HTTP response framing (`1xx`, `204`, `304`, and `HEAD` bodyless response rules in RFC 9112 Section 6.3).
- Content-coding decompression (`gzip`, `deflate`, `br`) and TLS / socket I/O.
