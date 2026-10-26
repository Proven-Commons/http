# Specification: http

This library reads the head of an HTTP/1.1 request, decides whether a server must refuse the request, and gives how the body after the head is framed. A reviewer who did not write this specification approves it. The approval also covers `Spec.lean`, `Spec/Abnf.lean`, `Spec/Rules.lean`, `Spec/Defs.lean`, `Http/Types.lean`, `Http/Abnf.lean`, and the other files `bar.toml` lists.

Throughout, a message is a sequence of octets, as RFC 9112 section 2.2 requires: "A recipient MUST parse an HTTP message as a sequence of octets in an encoding that is a superset of US-ASCII".

## The grammar

The grammar is the ABNF of the RFCs, written in a small notation of regular expressions over octets (`Http/Abnf.lean`, with its meaning in `Spec/Abnf.lean`). `Spec/Rules.lean` writes each rule as the RFC does, in the RFC's order of alternatives:

- RFC 5234: `ALPHA`, `DIGIT`, `HEXDIG`, `VCHAR`, `SP`, `HTAB`.
- RFC 9110: `tchar`, `token`, `OWS`, `obs-text`, `field-vchar`, `field-content`, `field-value`, `field-name`, `Content-Length`, `absolute-path` and `Host`.
- RFC 3986: `unreserved`, `pct-encoded`, `sub-delims`, `pchar`, `segment`, `query`, `scheme`, `userinfo`, `h16`, `dec-octet`, `IPv4address`, `ls32`, `IPv6address`, `IPvFuture`, `IP-literal`, `reg-name`, `host`, `port`, `authority`, the path rules, `hier-part` and `absolute-URI`.
- RFC 9112: `method`, `origin-form`, `absolute-form`, `authority-form`, `asterisk-form` and `request-target`.

A quoted string in ABNF matches ASCII letters in either case (RFC 5234, section 2.3), so `"v"` in `IPvFuture` also matches `V`, and `HEXDIG` matches `a` to `f`.

## The head

RFC 9112 section 2.1 gives the message:

```
HTTP-message   = start-line CRLF
                 *( field-line CRLF )
                 CRLF
                 [ message-body ]
request-line   = method SP request-target SP HTTP-version
HTTP-version   = HTTP-name "/" DIGIT "." DIGIT
HTTP-name      = %s"HTTP"
field-line     = field-name ":" OWS field-value OWS
```

`parseHead` reads a head from the start of the input: the request line, the field lines and the empty line. It gives the head, and the octets after the empty line, which are the start of the body or of the next request. The head keeps:
- the method, the target and each field name and value as written;
- the two digits of the version as numbers;
- the fields in order.

A field's value does not include the optional whitespace around it (section 5.1).

- Before the request line, any number of empty lines are skipped, as section 2.2 asks: a server "SHOULD ignore at least one empty line (CRLF) received prior to the request-line".
- Every line ends in CRLF. A field value cannot hold a CR, LF, NUL or other control octet, and no other part of the head can either. So `parseHead` rejects:
  - a bare CR, or a bare LF as a line end;
  - a line starting with whitespace, which is how both whitespace after the request line and a folded line (`obs-fold`) begin;
  - whitespace before a colon;
  - any separator in the request line other than one SP.
- The target is one of the four forms of section 3.2:
  - `origin-form`, a path with an optional query;
  - `absolute-form`, an absolute URI;
  - `authority-form`, a host and port;
  - `asterisk-form`, `*`.

  Each form is in its RFC 3986 grammar, with percent-escapes of two hex digits, and IPv6 and IPvFuture literals. A fragment (`#`) is not part of any form.

RFC 9112 allows a recipient to repair some of these instead of rejecting them. Section 2.2 allows a single LF as a line end, and a bare CR replaced by SP. Section 3 allows parsing the request line on other whitespace. Section 5.2 allows a folded line to be replaced by SP. This library takes none of those choices: it rejects. Section 5.1 leaves no choice for whitespace before a colon: "A server MUST reject ... any received request message that contains whitespace between a header field name and colon".

`Head.print` writes a head back, with one SP after each colon, as section 5.1 prefers.

## Accepting a request, and framing its body

`Head.framing` gives the framing of the body after the head: a length in octets, which is 0 for no body, or the chunked coding. It gives `none` when a server must refuse the request. Field names are compared without regard to ASCII case (RFC 9110, section 5.1).

- **The version:** only major version 1 is accepted. RFC 9110 section 6.2 lets a server refuse other major versions with 505. A minor version of 1 or more is handled as 1.1, as section 6.2 asks of a version higher than the recipient implements.
- **Host:** a request with more than one Host field line is refused. So is an HTTP/1.1 request without one, and a Host whose value is not `uri-host [ ":" port ]` (RFC 9112, section 3.2).
- **Transfer-Encoding:** it is accepted only as one field line whose value is `chunked`, in any case, in an HTTP/1.1 request with no Content-Length. Then the body is chunked. Every other use is refused:
  - Transfer-Encoding with Content-Length. Section 6.1 lets a server refuse it: "A server MAY reject a request that contains both Content-Length and Transfer-Encoding".
  - Transfer-Encoding in HTTP/1.0, which section 6.1 says must be treated "as if the framing is faulty".
  - Any value but `chunked` alone. With chunked not last, section 6.3 requires 400. Any other coding is one this library does not understand, for which section 6.1 says a server "SHOULD respond with 501".
  - More than one Transfer-Encoding line.
- **Content-Length:** with no Transfer-Encoding, it must be one field line whose value is `1*DIGIT` (RFC 9110, section 8.6). Then the body has that many octets. Section 6.3 lets a recipient accept a list of equal values such as `5, 5`. This library refuses it, and refuses two Content-Length lines even when they agree.
- **Neither field:** the body has length 0, by section 6.3: "If this is a request message and none of the above are true, then the message body length is zero".

## Errors

`parseHead` returns `none` for any input that does not start with a complete head of the grammar. That includes input that ends before the empty line. `Head.framing` returns `none` for a request a server must refuse. No function can fail any other way.

## The command-line tool

The command-line tool in `Main.lean` has two modes:

- `httphead check` reads a request on standard input. It prints the request line, each field and the framing: `length N`, `chunked` or `reject`. It prints `invalid` for input with no head of the grammar. It exits with 0 only for a request a server may accept.
- `httphead serve` answers requests from the differential tests, one per line, with octets sent as hex digits. The header comment of `Main.lean` gives the protocol.

Every answer comes from `parseHead`, `Head.print` and `Head.framing`.

## What must always hold

Each property is a theorem in `Spec.lean`, under the name given.

| Property | Theorem |
|----------|---------|
| `isMatch` decides `Spec.Matches`, what a rule of the notation matches. | `Spec.isMatch_iff` |
| `parseHead bs` is `(h, rest)` exactly when `h` is a head of the grammar and `bs` is empty lines, then `h` as written with any optional whitespace around its values, then `rest`. | `Spec.parseHead_iff` |
| `Head.print` writes the head as `Spec.render` gives it. | `Spec.print_eq` |
| Reading what `Head.print` wrote gives the head back, whatever follows it. | `Spec.parseHead_print` |
| `Head.framing h` is `fr` exactly when `Spec.Accepts h fr`: the version, the Host rule, and the framing rules above. | `Spec.framing_iff` |
| Transfer-Encoding with Content-Length is refused. | `Spec.framing_te_cl` |
| Two Content-Length field lines are refused. | `Spec.framing_two_cl` |
| The examples of RFC 9112 section 3.2 are accepted, and the shapes of request smuggling refused. | `Spec.head_vectors` |

Together, these fix every output.

- `parseHead` is fixed for every input. The head of the grammar at its start, if any, is unique: each line ends at the first CRLF, the request line splits at its two SPs, and a field line splits at its first colon.
- `Head.print` is fixed for every head, and `Head.framing` for every head.
- A parser that accepted nothing would fail `Spec.parseHead_print`, and one that accepted too much would fail `Spec.parseHead_iff`.

## Oracle

The differential tests compare the tool with the grammar and rules above, written again in Python from the RFCs: regular expressions for the request line, the field lines and the four target forms, then the Host and framing rules. The Python IPv6 rule is itself checked against Python's `ipaddress` module on generated addresses.
