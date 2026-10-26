# Specification: http

This library reads the head of an HTTP/1.1 request, decides whether to refuse the request, and gives how the body after the head is framed. Each refusal is either required by the RFCs or allowed by them and chosen here. The section "Which refusals the RFCs require" lists which is which. A reviewer who did not write this specification approves it. The approval also covers `Spec.lean`, `Spec/Abnf.lean`, `Spec/Rules.lean`, `Spec/Defs.lean`, `Http/Types.lean`, `Http/Abnf.lean`, and the other files `bar.toml` lists.

Throughout, a message is a sequence of octets, as RFC 9112 section 2.2 requires: "A recipient MUST parse an HTTP message as a sequence of octets in an encoding that is a superset of US-ASCII".

## The grammar

The grammar is the ABNF of the RFCs, written in a small notation of regular expressions over octets (`Http/Abnf.lean`, with its meaning in `Spec/Abnf.lean`). `Spec/Rules.lean` writes each rule as the RFC does, in the RFC's order of alternatives:

- RFC 5234: `ALPHA`, `DIGIT`, `HEXDIG`, `VCHAR`, `SP`, `HTAB`.
- RFC 9110: `tchar`, `token`, `OWS`, `obs-text`, `field-vchar`, `field-content`, `field-value`, `field-name`, `Content-Length`, `absolute-path`, `uri-host` and `Host`; `http-URI` and `https-URI` with a host that is not empty and no `userinfo` (sections 4.2.1, 4.2.2 and 4.2.4); and a list of one element as a recipient reads it (section 5.6.1.2).
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
- Every line ends in CRLF. A field value cannot hold a CR, LF, NUL or any control octet other than HTAB. HTAB may appear inside a value and in the optional whitespace around it. The request line and the field names hold no control octet. So `parseHead` rejects:
  - a bare CR, or a bare LF as a line end;
  - a line starting with whitespace, which is how both whitespace after the request line and a folded line (`obs-fold`) begin;
  - whitespace before a colon;
  - any separator in the request line other than one SP.
- The target is one of the four forms of section 3.2:
  - `origin-form`, a path with an optional query;
  - `absolute-form`, an absolute URI;
  - `authority-form`, a host and port;
  - `asterisk-form`, `*`.

  Each form is in its RFC 3986 grammar, with percent-escapes of two hex digits, and IPv6 and IPvFuture literals. A fragment (`#`) is not part of any form. The head keeps percent-escapes as written and does not decode them.

RFC 9112 allows a recipient to repair some of these instead of rejecting them. Section 2.2 allows a single LF as a line end, and a bare CR replaced by SP. Section 3 allows parsing the request line on other whitespace. Section 5.2 allows a folded line to be replaced by SP. This library takes none of those choices: it rejects. Section 5.1 leaves no choice for whitespace before a colon: "A server MUST reject ... any received request message that contains whitespace between a header field name and colon".

`Head.print` writes a head back, with one SP after each colon, as section 5.1 prefers.

## Accepting a request, and framing its body

`Head.framing` gives the framing of the body after the head: a length in octets, which is 0 for no body, or the chunked coding. It gives `none` when this library refuses the request. `Spec.Accepts` in `Spec/Defs.lean` states the rules below, and `Spec.framing_iff` says that `Head.framing` follows them. Field names are compared without regard to ASCII case (RFC 9110, section 5.1).

- **The version:** only major version 1 is accepted. RFC 9110 section 6.2 lets a server refuse other major versions with 505. A minor version of 1 or more is handled as 1.1, as section 6.2 asks of a version higher than the recipient implements.
- **Host:** a request with more than one Host field line is refused. So is a request with a minor version of 1 or more and no Host line, and a Host whose value is not `uri-host [ ":" port ]` (RFC 9112, section 3.2).
- **CONNECT:** when the method is `CONNECT`, the target must be `uri-host ":" port`, and the port, read as a decimal number, must be from 1 to 65535. Leading zeros are allowed, so `a:00080` is port 80. An empty port is refused, and so is a target that is not a host and port, such as `/` or `*`. RFC 9110 section 9.3.6 says "A server MUST reject a CONNECT request that targets an empty or invalid port number". It does not say which port numbers are invalid. Here a valid one is from 1 to 65535: a TCP port number is 16 bits (RFC 9293, section 3.1), and 0 is a Reserved port number (RFC 6335, section 6). A server need not accept CONNECT at all ("An origin server MAY accept a CONNECT request"), so refusing port 0 is allowed however "invalid" is read. The method is compared as written, since "The method token is case-sensitive" (section 9.1). So `connect` is another method, and this rule does not apply to it.
- **http and https targets:** when the method is not exactly `CONNECT` and the target starts with `http:` or `https:`, in any case, the target must match

  ```
  ( "http" / "https" ) "://" host [ ":" port ] path-abempty [ "?" query ]
  ```

  where the `host` is not empty. That is an `http-URI` or `https-URI` (RFC 9110, sections 4.2.1 and 4.2.2) with no `userinfo` in its authority. Of the three kinds of `host`, only `reg-name` can be empty, so `Spec.hostNonEmpty` in `Spec/Rules.lean` is `host` with the `*` of `reg-name` made `1*`. The scheme may be in any case, since "schemes are case-insensitive" (RFC 3986, section 3.1). Sections 4.2.1 and 4.2.2 say of an http or https URI with an empty host: "A recipient that processes such a URI reference MUST reject it as invalid". Section 4.2.4 says "a recipient SHOULD parse for userinfo and treat its presence as an error". So these are refused:
  - an empty host, such as `http://`, `http:///a` or `https://:443/`;
  - userinfo, such as `https://u@a/`, or the empty userinfo of `http://@a/`;
  - no authority, such as `http:` or `http:/a`. That is not an `http-URI` or `https-URI` at all, since both need `"://" authority`.

  An empty port is allowed, since "If the port subcomponent is empty or not given, TCP port 80 (the reserved port for WWW services) is the default" (section 4.2.1), and section 4.2.2 says the same of port 443. So `HTTP://a:/x` is accepted. A CONNECT target is not a URI. It consists "of only the host and port number of the tunnel destination" (section 9.3.6), so this rule does not apply to it: `CONNECT http:80` names the host `http` and the port 80. The method is compared as written here too, so `connect http:80` is held to this rule, and refused. With any method other than `CONNECT`, `http:80` is refused, though it also fits the authority-form.
- **Transfer-Encoding:** all its field lines are read as one value. That combined field value is their values in order, joined with commas (RFC 9110, section 5.2). Transfer-Encoding is accepted only when the combined value is a list of the one coding `chunked`, in any case, in a request with a minor version of 1 or more and no Content-Length. Then the body is chunked. The list may have empty elements, which "do not contribute to the count of elements present", and RFC 9110 section 5.6.1.2 says a recipient MUST accept such lists. So the value must match `*( OWS "," OWS ) "chunked" *( OWS "," OWS )`. For example, `chunked,` and `, chunked` are chunked, and so is a `chunked` line together with an empty Transfer-Encoding line. Every other use is refused:
  - Transfer-Encoding with Content-Length. Section 6.1 lets a server refuse it: "A server MAY reject a request that contains both Content-Length and Transfer-Encoding".
  - Transfer-Encoding in HTTP/1.0, which section 6.1 says must be treated "as if the framing is faulty".
  - A value with no coding, such as an empty value or `,`, or with chunked not last, such as `xchunked` or `chunked, identity`. Section 6.3 says that then "the server MUST respond with the 400 (Bad Request) status code".
  - Chunked twice, such as `chunked, chunked`, or `chunked` on two lines. Section 6.1 says "A sender MUST NOT apply the chunked transfer coding more than once", and RFC 9110 section 15.5.1 lets a server answer "invalid request message framing" with 400.
  - Another coding before chunked, such as `gzip, chunked`. This library does not understand that coding, and section 6.1 says a server that receives "a transfer coding it does not understand SHOULD respond with 501".
- **Content-Length:** with no Transfer-Encoding, it must be one field line whose value is `1*DIGIT` (RFC 9110, section 8.6). Then the body has that many octets. Section 6.3 lets a recipient accept a list of equal values such as `5, 5`. This library refuses it, and refuses two Content-Length lines even when they agree.
- **Neither field:** the body has length 0, by section 6.3: "If this is a request message and none of the above are true, then the message body length is zero".

## Which refusals the RFCs require

Each kind of request this library refuses is in one of two groups.

Refusals the RFCs require:
- whitespace before a colon (RFC 9112, section 5.1);
- no Host line in a request with a minor version of 1 or more, two Host lines, or a Host value that is not of the grammar (RFC 9112, section 3.2). The RFC says this of HTTP/1.1, and a later 1.x is handled as 1.1 here;
- a `CONNECT` whose target is not a host and port, or whose port is empty or above 65535. That is this library's reading of "an empty or invalid port number" (RFC 9110, section 9.3.6). A server need not accept CONNECT at all, so these refusals are allowed however that is read;
- an `http` or `https` target with an empty host, such as `http://` or `http:///a`, when the method is not `CONNECT` (RFC 9110, sections 4.2.1 and 4.2.2: a recipient that processes such a URI "MUST reject it as invalid");
- Transfer-Encoding with no coding, or with chunked not last (RFC 9112, section 6.3);
- Transfer-Encoding in HTTP/1.0, which section 6.1 says a server MUST treat "as if the framing is faulty";
- a Content-Length that is not digits, with no Transfer-Encoding, such as `+5` or `5, 6`, or two lines `5` and `6` (RFC 9112, section 6.3: "the recipient MUST treat it as an unrecoverable error").

Refusals the RFCs allow, chosen here:
- a bare CR or LF, whitespace before the first field line, other whitespace in the request line, and a folded line, which RFC 9112 sections 2.2, 3 and 5.2 let a recipient repair instead;
- a NUL in a field value, which RFC 9110 section 5.5 lets a recipient replace with SP, and any other control octet but HTAB, which that section calls invalid but lets a recipient keep in a safe context;
- any other head that is not of the grammar, such as one with a target outside RFC 3986. For these RFC 9112 section 2.2 says a server "SHOULD respond with a 400 (Bad Request) response";
- a major version other than 1 (RFC 9110, section 6.2: a server "can send a 505");
- Transfer-Encoding with Content-Length (RFC 9112, section 6.1: "MAY reject");
- two Content-Length lines that agree, or a list of equal values such as `5, 5` (RFC 9110, section 8.6: a recipient "MAY either reject the message as invalid or replace" the value);
- chunked twice, which a sender must not send (RFC 9112, section 6.1);
- a coding other than chunked, which this library does not understand (RFC 9112, section 6.1: "SHOULD respond with 501");
- a `CONNECT` with port 0, a Reserved port number (RFC 6335, section 6), since a server need not accept CONNECT;
- an `http` or `https` target with userinfo, such as `https://u@a/` (RFC 9110, section 4.2.4: a recipient "SHOULD parse for userinfo and treat its presence as an error");
- a target with the scheme http or https but no authority, such as `http:` or `http:/a`. It fits `absolute-URI`, but it is not an `http-URI` or `https-URI` at all, and RFC 3986 section 3.1 says that a URI that "violates one or more scheme-specific restrictions" should be flagged "as an error".

No theorem says that this library refuses every request the RFCs require a server to refuse. The statements are about its own rules, and the lists above are this specification's reading of the RFCs. What a server does after a refusal is also outside this library. For example, for an invalid Content-Length, RFC 9112 section 6.3 says "the server MUST respond with a 400 (Bad Request) status code and then close the connection". This library only decides that the request is refused.

## Errors

`parseHead` returns `none` for any input that does not start with a complete head of the grammar. That includes input that ends before the empty line. `Head.framing` returns `none` for a request this library refuses. No function can fail any other way.

## The command-line tool

The command-line tool in `Main.lean` has two modes:

- `httphead check` reads a request on standard input. It prints the request line, each field and the framing: `length N`, `chunked` or `reject`. It prints `invalid` for input with no head of the grammar. It exits with 0 only for a request this library accepts.
- `httphead serve` answers requests from the differential tests, one per line, with octets sent as hex digits. The header comment of `Main.lean` gives the protocol.

Every answer comes from `parseHead`, `Head.print` and `Head.framing`.

## What must always hold

Each property is a theorem in `Spec.lean`, under the name given.

| Property | Theorem |
|----------|---------|
| `isMatch` decides `Spec.Matches`, what a rule of the notation matches. | `Spec.isMatch_iff` |
| `parseHead bs` is `(h, rest)` exactly when `h` is a head of the grammar and `bs` is empty lines, then `h` as written with any optional whitespace around its values, then `rest`. | `Spec.parseHead_iff` |
| `Head.print` writes the head as `Spec.render` gives it. | `Spec.print_eq` |
| For a head of the grammar, reading what `Head.print` wrote gives the head back, whatever follows it. | `Spec.parseHead_print` |
| `Head.framing h` is `some fr` exactly when `Spec.Accepts h fr`: the version, the Host rule, the CONNECT rule, the rule for http and https targets, and the framing rules above. | `Spec.framing_iff` |
| Transfer-Encoding with Content-Length is refused. | `Spec.framing_te_cl` |
| Two Content-Length field lines are refused. | `Spec.framing_two_cl` |
| The examples of RFC 9112 sections 3.2.1 to 3.2.4 are accepted, with no body, and so are an HTTP/1.0 request with no Host, `CONNECT [::1]:65535`, `CONNECT http:80` and `GET HTTP://a:/x`. A length and a chunked body are framed. Transfer-Encoding lists with empty elements, on one line or two, are chunked. The shapes of request smuggling are refused, and so are a missing or repeated Host in HTTP/1.1, a `CONNECT` with an empty port, port 0, port 65536 or the target `/`, and the targets `http:`, `http:///a` and `https://u@a/`. | `Spec.head_vectors` |

Together, these fix every output.

- `parseHead` is fixed for every input. The head of the grammar at its start, if any, is unique: each line ends at the first CRLF, the request line splits at its two SPs, and a field line splits at its first colon.
- `Head.print` is fixed for every head, and `Head.framing` for every head.
- A parser that accepted nothing would fail `Spec.parseHead_print`, and one that accepted too much would fail `Spec.parseHead_iff`.

## Oracle

The differential tests compare the tool with the grammar and rules above, written again in Python from the RFCs, with the choices of this specification. They are regular expressions for the request line, the field lines and the four target forms, then the Host rule, the CONNECT rule, the rule for http and https targets and the framing rules. As here, the Transfer-Encoding lines are read as one list. The rule for http and https targets is written another way than `Spec.httpTarget`: it ends the authority at the first `/`, `?` or `#`, as RFC 3986 section 3.2 says, then looks for an `@` and for an empty host. The inputs come from a recorded seed. Besides valid and mutated heads, they include `CONNECT` targets whose port is empty, 0, above 65535 or has leading zeros, the other methods `connect` and `Connect`, http and https targets in any case with a host, an empty host, no `//`, userinfo or an empty port, targets of other schemes such as `httpx` and `ws`, `CONNECT` targets that name the host http or https, Transfer-Encoding lists with empty elements on one line or several, IP literals that RFC 3986 does not allow, and every input of `Spec.head_vectors`. The Python IPv6 rule is itself checked against Python's `ipaddress` module on generated addresses. `tests/TEST-RESULTS.md` has the record of the last run: 300000 inputs, 0 failures, and 20000 addresses checked against `ipaddress` with 0 disagreements.
