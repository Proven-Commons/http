# http: HTTP/1.1 request heads, proved

This library reads the head of an HTTP/1.1 request, as in `GET /where?q=now HTTP/1.1` followed by its header fields. The head is the request line, the field lines and the empty line that ends them. The library then decides whether to refuse the request, and if not, how the body after the head is framed: by a length, or by the chunked coding. Each refusal is either required by the RFCs or allowed by them and chosen here. `SPEC.md` lists which is which. Machine-checked proofs show three things:
- It reads exactly the heads that the grammar of RFC 9112, RFC 9110 and RFC 3986 allows, with every part as written.
- Printing a head of the grammar and reading it back gives the same head.
- Its refusals and its framing follow the rules of RFC 9112 sections 3.2 and 6.3 and RFC 9110 section 9.3.6, with the choices in `SPEC.md`.

Where the RFC lets a recipient choose between rejecting a malformed request and repairing it, this library rejects. That includes a bare CR or LF, a folded line, and Transfer-Encoding with Content-Length. Whitespace before a colon is not a choice: RFC 9112 section 5.1 says a server MUST reject it, and this library does.

These are the points where two servers can read the same bytes as different requests. That difference is request smuggling. Some public cases:
- In Node's llhttp, Transfer-Encoding was not parsed and checked correctly (CVE-2022-32213), and requests were not strictly delimited by CRLF (CVE-2022-32214).
- Go's net/http accepted, and normalized, a space before the colon in a field name (CVE-2019-16276).

The library is tested against a separate Python copy of the same rules. `tests/TEST-RESULTS.md` has the record: 300000 inputs, 0 failures.

It is a project of [Proven Commons](https://github.com/Proven-Commons/mission), built to the verified bar published there.

Status: in progress. The specification has not yet been approved by a reviewer apart from its author, so this is not verified.

## Use it

```
lake build
printf 'POST /a HTTP/1.1\r\nHost: example.org\r\nContent-Length: 5\r\n\r\nhello' | .lake/build/bin/httphead check
```

It prints the request line and each field, then the framing, here `length 5`. It prints `reject` when this library refuses the request, and `invalid` when the input does not start with a head of the grammar. It exits with 0 only for a request this library accepts. From Lean, the functions are these:

- `Http.parseHead : List UInt8 → Option (Head × List UInt8)` reads a head and gives the octets after it.
- `Http.Head.print` writes a head.
- `Http.Head.framing : Head → Option Framing` gives the framing, or `none` when this library refuses the request.
- `Http.Re.isMatch` matches a string against a rule of the grammar.

`SPEC.md` says what each one does.

## What is proved

The statements are in `Spec.lean`, and the proofs are in `Proofs/`. The statements use:
- the grammar, written rule for rule from the RFCs, in `Spec/Rules.lean`;
- the meaning of the grammar notation, in `Spec/Abnf.lean`;
- the other definitions, in `Spec/Defs.lean`;
- the types, in `Http/Types.lean` and `Http/Abnf.lean`.

| Claim | Theorem |
|-------|---------|
| The matcher, by Brzozowski derivatives, decides exactly what a rule of the grammar notation matches. | `Spec.isMatch_iff` |
| `parseHead` reads exactly the request heads of the grammar, after any empty lines, and returns the head as written and the octets after it. A head is a request line `method SP request-target SP HTTP-version`, then field lines `field-name ":" OWS field-value OWS`, each ending in CRLF, then an empty line. The method and field names are tokens. The target is one of the four forms of RFC 9112 section 3.2, each in its RFC 3986 grammar, IPv6 literals included. Each value is a field value of RFC 9110 section 5.5. So it rejects a bare CR or LF, whitespace before a colon, a line that starts with whitespace (a folded line included), a CR, LF, NUL or any control octet other than HTAB in a value, and any other whitespace in the request line. HTAB may appear inside a value and in the optional whitespace around it. The request line and the field names hold no control octet. | `Spec.parseHead_iff` |
| A head prints as the grammar writes it, with one SP after each colon. | `Spec.print_eq` |
| Printing a head of the grammar, then reading it, gives it back, whatever follows it. | `Spec.parseHead_print` |
| `framing` gives a framing exactly when this library accepts the request by the rules below, and it is the framing they give. Only major version 1 is accepted. An HTTP/1.1 request, or a later 1.x, needs exactly one Host field, and any request at most one, with a value of the `Host` grammar. A request whose method is exactly `CONNECT` needs the target `uri-host ":" port`, with a port from 1 to 65535. Transfer-Encoding is accepted only in HTTP/1.1 or a later 1.x, without Content-Length, and only when its combined value is a list of the one coding `chunked`, in any case. The combined value is the values of all its field lines, joined with commas, and the list may have empty elements. Then the body is chunked. Content-Length is accepted only as one field line of digits, without Transfer-Encoding, and gives the length. With neither, the body has length 0. | `Spec.framing_iff` |
| A request with both Transfer-Encoding and Content-Length is rejected. | `Spec.framing_te_cl` |
| A request with two Content-Length field lines is rejected, even when they agree. | `Spec.framing_two_cl` |
| The examples of RFC 9112 sections 3.2.1 to 3.2.4 are accepted, with no body. `Content-Length: 5` frames the five octets after the head, and `Transfer-Encoding: Chunked` is chunked. So are Transfer-Encoding lists with empty elements: `chunked,`, `, chunked`, and a `chunked` line with an empty Transfer-Encoding line. The classic shapes of request smuggling are rejected: two Content-Length values, Content-Length with Transfer-Encoding, `xchunked`, `chunked, identity`, `chunked, chunked`, a `chunked` line with a line of another coding, whitespace before a colon, a folded line, a bare LF, a bare CR, and Transfer-Encoding in HTTP/1.0. So are a missing Host and a repeated Host in HTTP/1.1, while HTTP/1.0 needs no Host. A `CONNECT` with an empty port, port 0, port 65536 or the target `/` is rejected, and `CONNECT [::1]:65535` is accepted. | `Spec.head_vectors` |

The command-line tool in `Main.lean` calls these functions directly.

## What is not proved

- Reading requests and printing answers in `Main.lean`: the hex coding in `serve` mode, reading standard input in `check` mode, and the output and exit codes. The differential tests cover them, with malformed requests and CR LF line endings.
- The body. This library frames the body but does not read it. It does not decode chunked data, chunk extensions or trailers, and does not count the octets of a length-framed body.
- What a server does with a request it accepts: the meaning of the method, the target and the fields, routing by Host, and the response.
- Completeness against the RFCs. No theorem says that this library refuses every request the RFCs say a server must refuse. The statements are about its own rules, written from the RFCs. For example, RFC 9110 sections 4.2.1 and 4.2.2 say that a recipient that processes an `http` or `https` URI with an empty host MUST reject it as invalid. This library checks a target only against the grammar of RFC 3986, so it accepts targets such as `http:` and `http:///a`. A server that uses the target must check this itself.
- Repairs the RFC allows. Where RFC 9112 or RFC 9110 lets a recipient either reject or repair, this library always rejects. That covers a bare LF as a line end, a bare CR, whitespace before the first field line, a folded line, whitespace other than one SP in the request line, a NUL in a value, Transfer-Encoding with Content-Length, two Content-Length lines that agree, and a Content-Length list of equal values such as `5, 5`. A server that repairs these accepts requests that this one refuses.
- Transfer codings other than chunked. RFC 9112 allows `gzip, chunked`, for example. This library decodes no other coding, so it refuses a Transfer-Encoding that names another coding, as RFC 9112 section 6.1 lets a server do for a coding it does not understand.
- The pairing of method and target form. RFC 9112 says the authority-form is only used for CONNECT and the asterisk-form only for OPTIONS. Those are rules for senders, so this library accepts any other method with any form. RFC 9110 section 9.3.6 has one rule for servers: "A server MUST reject a CONNECT request that targets an empty or invalid port number". This library reads it as: a `CONNECT` must have the target `uri-host ":" port`, with a port from 1 to 65535 (see `SPEC.md`). The method is case-sensitive, so `connect` is another method, and the rule does not apply to it. `a:1` fits both the absolute-form and the authority-form, and the head keeps the target as written.
- Percent-escapes in the target. A target may hold escaped octets such as `%0D%0A` or `%00`, as RFC 3986 allows, and the head keeps them as written. A proxy that decodes a target and writes it into another request must reject or re-escape them. Apache's mod_proxy, with some rewrite rules, did not (CVE-2023-25690).
- Limits on length. The grammar sets none, and neither does this library. A server should cap the size of a head before it reads it.
- Incomplete input. `parseHead` gives `none` both for a head that is not of the grammar and for one that has not fully arrived. It cannot tell a caller to wait for more octets.
- Speed. The code works on lists of octets, which suits proofs, not bulk data. The target and Host grammars are matched by derivatives, which is fast enough for heads of ordinary size.

## What you must trust

- The Lean kernel and the five external kernels shipped with Lean, which all check the proofs.
- `lake comparator`, which builds the statements and the proofs in a sandbox, exports them, and checks that each proof proves exactly its statement.
- bubblewrap and the Linux kernel's namespaces, which keep the untrusted build from tampering with that check.
- The Lean compiler, with the C compiler and linker shipped with it, and the runtime, which turn the proved definitions into the program that runs.
- Lean's core library, including the compiled code it puts in place of some definitions the proofs reason about (by `implemented_by` and `extern`), such as the arithmetic on natural numbers and on octets.
- The operating system and hardware it runs on.
- The transcription of the grammar in `Spec/Rules.lean`. A reviewer checks it against the RFCs rule by rule. The differential tests compare the code with a second transcription, the Python one, and check the IPv6 rule against Python's `ipaddress`.

This project has no dependencies beyond Lean itself.

## Other parsers

`tests/CROSS-CHECK.md` records a one-off comparison with Node's built-in server, which uses llhttp in its default strict mode, with Go's `net/http` server, and with Python's `h11`. It is not part of the verified bar.

Each parser was sent all 5991 heads in the first 6000 inputs of the differential tests. The other inputs are malformed requests to the tool. A parser accepts a head when it reads it and passes the request on. After a head this project accepts, the body it frames is sent: the whole body for a Content-Length up to 1,000,000, and a chunked body with 5 octets of data. The parsers give the same verdict as this project on 4130 heads (Node), 4722 (Go) and 4560 (h11). Where both accept and the answer gives a count, the body lengths agree every time: on 837 heads for Node, 207 of them with a length that is not zero; on 1414 for Go, 447 not zero; on 1623 for h11, 519 not zero. Node's answers to 73 heads give no count, since Node reads what follows a CONNECT as a tunnel. h11 was sent no body for 7 heads with a Content-Length above 1,000,000.

The main differences are below. `tests/CROSS-CHECK.md` lists them all, with counts and examples.

- **All three:**
  - They accept a Host value with a bad IP literal, such as `Host: ::1`, and other Host values outside RFC 3986. RFC 9112 section 3.2 says a server MUST answer these with 400.
  - They accept a CONNECT whose port is empty, 0 or above 65535, or whose target is not a host and port. RFC 9110 section 9.3.6 says a server MUST reject an empty or invalid port. Which ports are invalid is this library's reading.
  - They accept a target with a bad IP literal, such as `http://[1::2::3]/`. RFC 9112 section 3 says a server SHOULD answer an invalid request line with 400 or 301.
  - They accept Transfer-Encoding in HTTP/1.0, which RFC 9112 section 6.1 says a server MUST treat "as if the framing is faulty".
  - They reject Transfer-Encoding lists with empty elements, such as `chunked,`. RFC 9110 section 5.6.1.2 says a recipient MUST accept them.
- **Node:**
  - Repairs the RFC allows: other whitespace in the request line, such as `GET  /a`, and a bare LF before the request line.
  - It rejects requests the RFC says to accept: an absolute-form target with no authority, such as `x:`, or with a digit, `+`, `-` or `.` in its scheme (RFC 9112 section 3.2.2: a server MUST accept the absolute-form), and HTTP/1.2 to 1.9 (RFC 9110 section 6.2: SHOULD process it as 1.1). It also rejects a tab after a Content-Length or Transfer-Encoding value, though that tab is optional whitespace, not part of the value.
  - It accepts requests the RFC says to refuse: two Host lines (RFC 9112 section 3.2, MUST), and `Transfer-Encoding:` with no coding, which it reads as no body (RFC 9112 section 6.3, MUST).
  - Other choices: it rejects methods it does not know and the authority-form with a method other than CONNECT. It accepts HTTP/2.0 and `gzip, chunked`.
  - It rejects an `http` or `https` target with no host, such as `http:`, as RFC 9110 sections 4.2.1 and 4.2.2 ask of a recipient that processes it. This library accepts it (see What is not proved).
- **Go:**
  - Repairs the RFC allows: a bare LF, a folded line, Transfer-Encoding with Content-Length, which it reads as chunked, and two equal Content-Length lines.
  - It rejects requests the RFC says to accept: empty lines before the request line, even a single CRLF (RFC 9112 section 2.2: SHOULD ignore at least one), and a percent-escape of an ASCII octet in the host of the target, such as `%6C`. RFC 3986 allows that in a host name, and RFC 9112 section 3.2.2 says a server MUST accept the absolute-form.
  - Other choices: it rejects the authority-form with a method other than CONNECT.
- **h11:**
  - Repairs the RFC allows: a bare LF, a folded line, a Content-Length list of equal values such as `5, 5`, two equal Content-Length lines, and Transfer-Encoding with Content-Length, which it reads as chunked.
  - It rejects requests the RFC says to accept: empty lines before the request line, even a single CRLF.
  - It accepts requests the RFC says to refuse: no Host in HTTP/1.2 to 1.9. RFC 9112 section 3.2 requires a Host in HTTP/1.1, and RFC 9110 section 6.2 asks a server to handle a later 1.x as 1.1.
  - Other choices: it accepts HTTP/2.0 and HTTP/0.9, a bad percent-escape such as `/%4g`, and control octets in a field line.

## Re-check it

Needs Linux, [elan](https://github.com/leanprover/elan), bubblewrap (`apt install bubblewrap`), and Python 3.11 or later.

```
lake build
lake comparator --paranoid
python3 tests/run_tests.py
```

`lake comparator --paranoid` builds the statements and the proofs in a sandbox. It checks that each theorem in `Proofs/` proves exactly the statement in `Spec.lean`, using only the axioms `propext`, `Classical.choice`, and `Quot.sound`, and replays it through every kernel shipped with Lean.

The test script compares the tool with the rules of RFC 9112, RFC 9110 and RFC 3986, written again in the script, on 300000 inputs from a recorded seed. Besides valid and mutated heads, the inputs include `CONNECT` targets whose port is empty, 0, above 65535 or has leading zeros, http and https targets with an empty host, with no `//` or with userinfo, Transfer-Encoding lists with empty elements on one line or several, and IP literals that RFC 3986 does not allow. The script then rewrites `tests/TEST-RESULTS.md`. `tests/planted_bugs.py` plants 49 small bugs in the tool, one at a time in a copy, and `tests/PLANTED-BUGS.md` records that the tests catch 47 of them and why the other 2 change nothing the tool prints. The cross-check, `python3 tests/cross_check.py`, also needs Node, Go, and `h11` in `.lake/oracle-packages` (`pip install --target .lake/oracle-packages h11`).

## Layout

- `Http/Types.lean`: the head, field and framing types. It is part of the specification.
- `Http/Abnf.lean`: the grammar notation, a small language of regular expressions over octets. It is part of the specification.
- `Http/Match.lean`, `Http/Grammar.lean`, `Http/Head.lean`, `Http/Framing.lean`: the code under proof. `Http/Grammar.lean` is the code's copy of the target, Host and Transfer-Encoding list rules, which the proofs show equal to the spec's.
- `Spec.lean`: the statements, with `sorry` for proofs. A reviewer approves this file.
- `Spec/Abnf.lean`: what a rule of the notation matches.
- `Spec/Rules.lean`: the ABNF rules, from RFC 5234, RFC 9110, RFC 3986 and RFC 9112.
- `Spec/Defs.lean`: the text of a head, and the acceptance and framing rules, with the RFC text they come from and this library's choices.
- `Proofs.lean` and `Proofs/`: the proofs.
- `Main.lean`: the command-line tool.
- `lakefile.toml`: the build. It names the package and its version, its libraries and executable, and the default targets, and sets nothing else.
- `comparator.json`: which theorems `lake comparator` checks, and which axioms it allows.
- `bar.toml`: the record for the bar check: status, authors, approvals, and where things are.
- `SPEC.md`: the specification in plain words.
- `tests/run_tests.py`: the differential tests.
- `tests/cross_check.py` and `tests/cross_check/`: the one-off comparison with Node, Go and h11.
