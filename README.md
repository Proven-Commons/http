# http: HTTP/1.1 framing and chunked bodies

This library reads one HTTP/1.x request from a byte string. It parses the head, refuses a head that breaks the rules in `SPEC.md`, and frames the body by a length or by the chunked coding. It then decodes a chunked body, including chunk extensions and the trailer section.

The head rules are the same choices as the request-head parser: the four target forms, one Host on HTTP/1.1, no empty host, and CONNECT with a real port and no content. The body rules are RFC 9112 section 7. Where the RFC lets a recipient reject or repair, this library rejects.

It is a project of [Proven Commons](https://github.com/Proven-Commons/mission), built to the verified bar published there.

Status: in progress. The specification has not yet been approved by a reviewer apart from its author, so this is not verified.

## Use it

```
lake build
.lake/build/bin/http-tool request.bin
```

The tool prints `accept N` with the body length, or `reject`. From Lean, `Http.parseRequest` returns the head, the body, and the octets that follow.

## What is proved

The statements are in `Http/Spec.lean`. The proofs are in `Http/Proofs.lean`, under the same names. Definitions shared with the statements are in `Http/Spec/Defs.lean` and `Http/Types.lean`.

| Claim | Theorem |
|-------|---------|
| A split at CRLF is a line with no bare CR or LF, the two octets `0x0D 0x0A`, and the suffix. | `Http.Spec.splitCRLF_sound` |
| Appending octets after a successful split keeps the line and appends those octets to the suffix. | `Http.Spec.splitCRLF_prefix_free` |
| Printing a length up to `2^64 - 1` in decimal and reading it back gives the same number. | `Http.Spec.parseDec_printDec` |
| Printing a length up to `2^64 - 1` in hex and reading it back gives the same number. | `Http.Spec.parseHex_printHex` |
| A version and a field list determine at most one framing. | `Http.Spec.determineFraming_disjoint` |
| Transfer-Encoding together with Content-Length is rejected. | `Http.Spec.determineFraming_rejects_cl_and_te` |
| Transfer-Encoding on HTTP/1.0 is rejected. | `Http.Spec.determineFraming_rejects_http10_te` |
| Chunked framing implies HTTP/1.1, no Content-Length field, and a normalized Transfer-Encoding list of exactly `[chunked]`. Empty elements are dropped before that comparison, so the list is final and is not repeated. Case variants are normalized to lower case, and field lines are joined before the list is split. | `Http.Spec.determineFraming_rejects_nonfinal_chunked` |
| The same hypothesis implies HTTP/1.1 and no Content-Length, which is the weaker form of the previous statement. | `Http.Spec.chunked_requires_http11_without_cl` |
| A Transfer-Encoding field whose normalized list is anything other than `[chunked]` is rejected, including no coding, a repeated coding, and a coding that is not final. | `Http.Spec.determineFraming_rejects_bad_te` |
| Encoding a body whose length is at most `2^64 - 1` and decoding it gives that body, no trailers, and an empty suffix. | `Http.Spec.decodeChunked_encodeChunked` |
| Appending octets after a successful chunked body keeps the body and the trailers and appends those octets to the suffix. | `Http.Spec.decodeChunked_prefix_free` |
| A request printed with a length framing parses back to the same method, target, version, and body. | `Http.Spec.parseRequest_serializeFixed` |
| A request printed with chunked framing parses back to the same method and target, version HTTP/1.1, and the same body. | `Http.Spec.parseRequest_serializeChunked` |
| Appending octets after a successfully parsed request appends those octets to its suffix. | `Http.Spec.parseRequest_prefix_free` |
| Two ways of splitting one byte string into the same number of requests produce the same requests and the same tail. | `Http.Spec.parseRequest_stream_unique` |
| The ten smuggling messages in `SPEC.md` are rejected. | `Http.Spec.reject_smuggling_vectors` |

`Http.Spec.determineFraming_rejects_nonfinal_chunked` is the strong statement. It includes `normalizedCodings hdrs = some [chunkedToken]`. `Http.Spec.chunked_requires_http11_without_cl` keeps the weaker pair of facts on its own.

## What is not proved

- The command-line tool in `Main.lean`: reading the file and printing the line. The tests run it.
- That every refusal the RFCs require is one of these refusals. `SPEC.md` says which rule each refusal comes from.
- The IPv6 grammar inside brackets, and the full `absolute-URI` grammar for a scheme other than http or https. `SPEC.md` delimits both, and both belong to the request-head parser.
- Trailer fields after they have been parsed. The decoder checks their shape and drops them.
- What a server does with a request it accepts, and the response it sends after a refusal.
- A bound on the size of a message. The chunked decoder stops after a number of steps linear in the input length; that fuel is part of the function, and the round-trip theorems use a body that fits in one chunk.

## What you must trust

- The Lean kernel, which checks the proofs.
- The Lean compiler, which turns the definitions into the program that runs, and the runtime of that program.
- The operating system and the hardware it runs on.
- `lake comparator`, which checks that each proof in `Http/Proofs.lean` proves the statement of the same name in `Http/Spec.lean`.
- The transcription of the rules in `SPEC.md`. A reviewer checks it against RFC 9112 and RFC 9110. The tests compare the tool with a second transcription of those rules.

## Re-check

Needs Linux, [elan](https://github.com/leanprover/elan), bubblewrap (`apt install bubblewrap`), and Python 3.

```
lake build
lake comparator --paranoid
python3 tests/run_tests.py
```

`lake comparator --paranoid` builds the statements and the proofs in a sandbox and checks that each proof proves its statement, using only `propext`, `Classical.choice`, and `Quot.sound`.

`python3 tests/run_tests.py` feeds requests to `http-tool` and compares each answer with the Python transcription of `SPEC.md`. It rewrites `tests/TEST-RESULTS.md`.

## Layout

- `Http/Types.lean`: versions, fields, and framing. It is part of the specification.
- `Http/Bytes.lean`, `Http/Framing.lean`, `Http/Parse.lean`: the code under proof.
- `Http/Lemmas.lean`: the proofs of the statements, which `Http/Spec.lean` and `Http/Proofs.lean` both cite.
- `Http/Spec/Defs.lean`: the line property, the stream relation, and the ten smuggling messages.
- `Http/Spec.lean`: the statements. A reviewer approves this file.
- `Http/Proofs.lean`: the same statements, proved.
- `Main.lean`: the command-line tool.
- `SPEC.md`: the rules, including the Host and CONNECT choices shared with the request-head parser.
