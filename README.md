# http: HTTP/1.1 request heads, proved

This library reads the head of an HTTP/1.1 request, as in `GET /where?q=now HTTP/1.1` followed by its header fields. The head is the request line, the field lines and the empty line that ends them. The library then decides whether a server must refuse the request, and if not, how the body after the head is framed: by a length, or by the chunked coding. Machine-checked proofs show three things:
- It reads exactly the heads that the grammar of RFC 9112, RFC 9110 and RFC 3986 allows, with every part as written.
- Printing a head and reading it back gives the same head.
- The framing follows the rules of RFC 9112 sections 3.2 and 6.3.

Where the RFC lets a recipient choose between rejecting a malformed request and repairing it, this library rejects. That includes a bare CR or LF, a folded line, whitespace before a colon, and Transfer-Encoding with Content-Length.

These are the points where two servers can read the same bytes as different requests. That difference is request smuggling. Some public cases:
- In Node's llhttp, Transfer-Encoding was not parsed and checked correctly (CVE-2022-32213), and requests were not strictly delimited by CRLF (CVE-2022-32214).
- Go's net/http accepted, and normalized, a space before the colon in a field name (CVE-2019-16276).
- Apache's mod_proxy could split a request through a rewritten target (CVE-2023-25690).

The library is tested against a separate Python copy of the same rules; `tests/TEST-RESULTS.md` has the record.

It is a project of [Proven Commons](https://github.com/Proven-Commons/mission), built to the verified bar published there.

Status: in progress. The specification has not yet been approved by a reviewer apart from its author, so this is not verified.

## Use it

```
lake build
printf 'POST /a HTTP/1.1\r\nHost: example.org\r\nContent-Length: 5\r\n\r\nhello' | .lake/build/bin/httphead check
```

It prints the request line and each field, then the framing, here `length 5`. It prints `reject` when a server must refuse the request, and `invalid` when the input does not start with a head of the grammar. It exits with 0 only for a request a server may accept. From Lean, the functions are these:

- `Http.parseHead : List UInt8 → Option (Head × List UInt8)` reads a head and gives the octets after it.
- `Http.Head.print` writes a head.
- `Http.Head.framing : Head → Option Framing` gives the framing, or `none` when the request must be rejected.
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
| `parseHead` reads exactly the request heads of the grammar, after any empty lines, and returns the head as written and the octets after it. A head is a request line `method SP request-target SP HTTP-version`, then field lines `field-name ":" OWS field-value OWS`, each ending in CRLF, then an empty line. The method and field names are tokens. The target is one of the four forms of RFC 9112 section 3.2, each in its RFC 3986 grammar, IPv6 literals included. Each value is a field value of RFC 9110 section 5.5. So it rejects a bare CR or LF, whitespace before a colon, a line that starts with whitespace (a folded line included), a CR, LF, NUL or other control octet in a value, and any other whitespace in the request line. | `Spec.parseHead_iff` |
| A head prints as the grammar writes it, with one SP after each colon. | `Spec.print_eq` |
| Printing a head of the grammar, then reading it, gives it back, whatever follows it. | `Spec.parseHead_print` |
| `framing` decides which requests a server accepts, and how it frames the body. Only HTTP/1.x is accepted. An HTTP/1.1 request needs exactly one Host field, and any request at most one, with a value of the `Host` grammar. Transfer-Encoding is accepted only as one field line whose value is `chunked`, in HTTP/1.1, without Content-Length. Content-Length is accepted only as one field line of digits. With neither, the body has length 0. | `Spec.framing_iff` |
| A request with both Transfer-Encoding and Content-Length is rejected. | `Spec.framing_te_cl` |
| A request with two Content-Length field lines is rejected, even when they agree. | `Spec.framing_two_cl` |
| The examples of RFC 9112 sections 3.2.1 to 3.2.4 are accepted. The classic shapes of request smuggling are rejected: two Content-Length values, Content-Length with Transfer-Encoding, `xchunked`, `chunked, identity`, two Transfer-Encoding lines, whitespace before a colon, a folded line, a bare LF, a bare CR, and Transfer-Encoding in HTTP/1.0. So are a missing Host and a repeated Host in HTTP/1.1. | `Spec.head_vectors` |

The command-line tool in `Main.lean` calls these functions directly.

## What is not proved

- Reading requests and printing answers in `Main.lean`: the hex coding in `serve` mode, reading standard input in `check` mode, and the output and exit codes. The differential tests cover them, with malformed requests and CR LF line endings.
- The body. This library frames the body but does not read it. It does not decode chunked data, chunk extensions or trailers, and does not count the octets of a length-framed body.
- What a server does with a request it accepts: the meaning of the method, the target and the fields, routing by Host, and the response.
- Repairs the RFC allows. Where RFC 9112 lets a recipient either reject or repair, this library always rejects. That covers a bare LF as a line end, a bare CR, whitespace before the first field line, a folded line, whitespace other than one SP in the request line, Transfer-Encoding with Content-Length, and a Content-Length list of equal values such as `5, 5`. A server that repairs these accepts requests that this one refuses.
- Transfer codings other than chunked. RFC 9112 allows `gzip, chunked`, for example. This library decodes no other coding, so it rejects any Transfer-Encoding but `chunked` alone, as RFC 9112 section 6.1 lets a server do for a coding it does not understand.
- The pairing of method and target form. RFC 9112 says the authority-form is only used for CONNECT and the asterisk-form only for OPTIONS. Those are rules for senders, and this library accepts any method with any form. `a:1` fits both the absolute-form and the authority-form, and the head keeps the target as written.
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

`tests/CROSS-CHECK.md` records a one-off comparison with Node's built-in server, which uses llhttp in its default strict mode, with Go's `net/http` server, and with Python's `h11`. Each gets the first 6000 heads of the differential tests. The comparison is not part of the verified bar. Where both accept a head, they read the same body length. The differences it found are below; most are repairs the RFC allows.

- **Node:**
  - It rejects methods it does not know, absolute-form targets with no `//` such as `x:`, the authority-form with a method other than CONNECT, and HTTP/1.2 to 1.9.
  - It accepts HTTP/2.0 and HTTP/0.9 in the request line, two Host lines, Host values outside RFC 3986 such as `a b`, and a target with `%zz` or a fragment.
- **Go:**
  - It rejects empty lines before the request line, which RFC 9112 asks a server to ignore, and the authority-form with a method other than CONNECT.
  - It accepts Transfer-Encoding in HTTP/1.0, which RFC 9112 says must be treated as faulty framing.
  - It accepts a bare LF, folded lines, Transfer-Encoding with Content-Length, and two equal Content-Length lines.
- **h11:**
  - It rejects empty lines before the request line.
  - It accepts HTTP/2.0 and HTTP/0.9, folded lines, a bare LF, and Host values outside RFC 3986.

## Re-check it

Needs Linux, [elan](https://github.com/leanprover/elan), bubblewrap (`apt install bubblewrap`), and Python 3.11 or later.

```
lake build
lake comparator --paranoid
python3 tests/run_tests.py
```

`lake comparator --paranoid` builds the statements and the proofs in a sandbox. It checks that each theorem in `Proofs/` proves exactly the statement in `Spec.lean`, using only the axioms `propext`, `Classical.choice`, and `Quot.sound`, and replays it through every kernel shipped with Lean.

The test script compares the tool with the rules of RFC 9112, RFC 9110 and RFC 3986, written in the script, on heads from a recorded seed. It then rewrites `tests/TEST-RESULTS.md`. The cross-check, `python3 tests/cross_check.py`, also needs Node, Go, and `h11` in `.lake/oracle-packages` (`pip install --target .lake/oracle-packages h11`).

## Layout

- `Http/Types.lean`: the head, field and framing types. It is part of the specification.
- `Http/Abnf.lean`: the grammar notation, a small language of regular expressions over octets. It is part of the specification.
- `Http/Match.lean`, `Http/Grammar.lean`, `Http/Head.lean`, `Http/Framing.lean`: the code under proof. `Http/Grammar.lean` is the code's copy of the target and Host rules, which the proofs show equal to the spec's.
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
