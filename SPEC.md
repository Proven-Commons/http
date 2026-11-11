# HTTP/1.1 Message Framing and Chunked Transfer Coding (`Http`)

This specification defines the wire-level rules for parsing and framing an HTTP/1.x request message from a byte stream under RFC 9112 (HTTP/1.1) and RFC 9110 (HTTP Semantics), taking the strict reading wherever lenient parsers permit request-boundary disagreement.

## Scope

1. **Line Termination (`splitCRLF`)**: Every start-line, header field line, chunk-size line, chunk-data record, and trailer section MUST end with `CRLF` (`0x0D 0x0A`). Any bare `CR` (`0x0D` not followed by `0x0A`) or bare `LF` (`0x0A` not preceded by `0x0D`) inside a line is rejected (`none`).
2. **Request-Line (`parseRequestLine`, RFC 9112 Section 3)**: Must split on single `SP` (`0x20`) into three components `method SP request-target SP HTTP-version`. Runs of multiple spaces, `HTAB`, or control characters are rejected. `method` is `1*tchar`; `request-target` is `1*VCHAR`; `HTTP-version` is `HTTP/1.1` or `HTTP/1.0`.
3. **Header Section (`parseHeaders`, RFC 9112 Section 5)**:
   - Obsolete line folding (`obs-fold`, lines beginning with `SP` or `HTAB`, Section 5.2) is rejected.
   - Whitespace between `field-name` and `:` (Section 5.1) is rejected; `field-name` must satisfy `1*tchar`.
   - Leading and trailing optional whitespace (`OWS`: `SP` / `HTAB`) around `field-value` is stripped; interior bytes must satisfy RFC 9110 Section 5.5 (`field-vchar` or `OWS`, no `NUL` or control octets).
4. **Message Body Framing (`determineFraming`, RFC 9112 Sections 6.1-6.3)**:
   - **Combined `Transfer-Encoding` and `Content-Length` (Sections 6.1 / 6.3)**: Unconditionally rejected to prevent `CL.TE` and `TE.CL` boundary ambiguity.
   - **`Transfer-Encoding` in `HTTP/1.0` (Section 6.1, EEF-CVE-2026-94194)**: Unconditionally rejected.
   - **Transfer-Coding List (Sections 6.1 / 6.3, EEF-CVE-2026-94194)**: Tokenized across comma-separated values; empty elements, non-token characters, repeated `chunked`, or non-final `chunked` (`Transfer-Encoding: chunked, gzip`) are rejected. Only `[chunked]` (case-insensitively) selects chunked framing in this slice.
   - **`Content-Length` (Section 6.2 / RFC 9110 Section 8.6)**: Duplicate `Content-Length` header fields are rejected; a single `Content-Length` value must match `1*DIGIT` (`< 2^64`, no `+`, `-`, or comma list).
   - **Default**: Requests with neither `Transfer-Encoding` nor `Content-Length` have a zero-byte body (`fixed 0`).
5. **Chunked Transfer Coding (`decodeChunked`, RFC 9112 Section 7.1)**:
   - `chunk-size` is `1*HEXDIG` (`< 2^64`). Optional chunk extensions after `;` must contain only `OWS` and `field-vchar`.
   - Every non-zero chunk payload of `sz` bytes MUST be followed immediately by `0x0D 0x0A` (`CRLF`); non-CRLF terminators (CVE-2025-23167 class) are rejected.
   - The terminating `0` chunk is followed by an optional RFC 9112 Section 7.1.2 trailer section (`*( field-line CRLF )`) and final `CRLF`.
