# HTTP/1.1 request framing and chunked bodies

This specification is the framing half of an HTTP/1.1 request parser. It reads one request from a byte string: the head, then a body framed by a length or by the chunked coding, and the octets that follow. It is written to agree with the request-head rules of the companion parser (the four target forms, Host, and CONNECT), and then to decode the body those rules frame.

Where RFC 9112 lets a recipient reject or repair, this library rejects. Field names are compared without regard to ASCII case.

Status: in progress.

## What this library checks

### Lines

Every request line, field line, chunk-size line, and trailer line ends in CRLF. A bare CR or a bare LF in that line is rejected. Empty lines before the request line are skipped. An empty line ends the header section, and another ends the trailer section.

### Request line

The request line is `method SP request-target SP HTTP-version`, split on a single SP into three components. The method is a token (`1*tchar`). The version is `HTTP/1.0`, or `HTTP/1.1` through `HTTP/1.9`. A minor version of 1 or more is HTTP/1.1 for every rule below. Any other version is rejected.

### The four target forms

The target is one of the four forms of RFC 9112 section 3.2, checked as a stated subset of RFC 3986. It is a string of VCHARs, and `#` is rejected in every form, so `GET /#frag` is refused.

- **origin-form** begins with `/`.
- **asterisk-form** is exactly `*`.
- **absolute-form** for the schemes `http` and `https`, in any case, is `( "http" / "https" ) "://" host [ ":" port ] path-abempty [ "?" query ]` with a host that is not empty and no userinfo. `http://a/x` and `HTTP://a:/x` are accepted. `http:`, `http:/a`, `http://`, `http:///a`, and `https://u@a/` are rejected. An empty port is allowed.
- **any other scheme** is `scheme ":" 1*VCHAR` with no `#`, where `scheme` is an ALPHA followed by ALPHA, DIGIT, `+`, `-`, or `.`. This is not the full `absolute-URI` grammar. The caller that needs that grammar is the request-head parser.
- **authority-form** is what remains: `host [ ":" port ]` with no `/` and no `?`. The host is not empty. A target that begins with `:`, such as `GET :80` or `OPTIONS :`, is refused for every method: it is an authority-form target with an empty host, and RFC 9112 section 3.3 plus RFC 9110 section 4.2.1 require that URI to be rejected.

A host here is either a run of VCHARs with no colon, or a bracketed literal: `[` then at least one octet then `]` then an optional `:` and a port of digits. The port may be empty. **The octets inside the brackets are not matched against the IPv6 grammar of RFC 3986.** That match is the request-head parser's derivative matcher, and this library does not repeat it. `CONNECT [::1]:443` and `Host: [::1]` are accepted here because the brackets are nonempty and the port is digits, not because `::1` was proved to be an IPv6 address.

### Host

A request with a minor version of 1 or more needs exactly one Host field. Any other request needs at most one. The value is empty, or a host that is not empty with an optional port, so `Host: :80` and `Host: :` are refused and an empty Host is accepted. An invalid Host value is refused. This is the same reading as the request-head parser: RFC 9112 section 3.2 for the count, and sections 3.2 and 3.3 together with RFC 9110 section 4.2.1 for an empty host before a colon.

### CONNECT

When the method is exactly `CONNECT` (the method token is case-sensitive, so `connect` is a different method):

- the target is `uri-host ":" port` with a nonempty host and a port from 1 to 65535, leading zeros allowed, so `a:00080` is port 80;
- an empty port, port 0, a port above 65535, and a target that is not a host and port (`/`, `*`, `:80`) are refused;
- the request has no content. Transfer-Encoding, or a Content-Length that is not numerically 0, is refused. `Content-Length: 0` and `Content-Length: 000` are accepted. RFC 9110 section 9.3.6 says a CONNECT request does not have content, and a server need not accept CONNECT at all.

`CONNECT http:80` is the host `http` and the port 80. It is not an http URI. `connect http:80`, with the method in lower case, is held to the http-target rule and refused.

### Framing

`determineFraming` looks only at the version and the fields.

Transfer-Encoding field lines are one combined value: their values in order, joined with commas. That value is split on commas, each element is trimmed of OWS (SP or HTAB), and empty elements are dropped. Empty elements do not count. `, chunked`, `chunked,`, and a `chunked` line beside an empty Transfer-Encoding line are the coding `chunked`. A tab or spaces around the token are OWS and are trimmed. Each remaining element must be a bare token, so `chunked;a=b` is refused.

Chunked framing is returned only when the version is HTTP/1.1 (or a later 1.x), there is no Content-Length field, and the normalized list is exactly `[chunked]`. In particular:

- no coding (`Transfer-Encoding:` or `Transfer-Encoding: ,`) is rejected;
- chunked not last (`chunked, gzip`, `gzip, chunked`) is rejected;
- chunked repeated (`chunked, chunked`, or `chunked` on two lines) is rejected;
- Transfer-Encoding together with Content-Length is rejected;
- Transfer-Encoding on HTTP/1.0 is rejected.

Content-Length is accepted only as one field whose value is `1*DIGIT` and whose number is at most `2^64 - 1`. It frames that many octets. With neither Content-Length nor Transfer-Encoding, the body has length 0. Two Content-Length lines are rejected even when they agree. A sign, a comma, or any other non-digit is rejected.

### Chunked bodies

`chunk-size` is `1*HEXDIG`, at most `2^64 - 1`. The size is the hex number, and what follows it on the line is a chunk extension, not ignored whitespace.

A chunk extension is the grammar of RFC 9112 section 7.1.1, not a whitelist of field characters: `;` OWS `token` [OWS `=` OWS (`token` / quoted-string)], and the extension may repeat. `token` is `1*tchar`. A quoted-string is the usual quoted text, with a backslash escape of HTAB, SP, VCHAR, or an octet at least 128. This library accepts a well-formed extension it does not understand, including a quoted value such as `1;a="x"`. It rejects a missing name (`1;=x`) and a quote that never closes (`1;a="x`).

Each non-zero chunk is that many octets followed by CRLF. Any other terminator is rejected. The zero chunk is followed by a trailer section of the same shape as the header section, then the octets after the trailer. The trailer is parsed and then discarded: this library does not interpret trailer fields.

## What is delegated

These checks belong to the request-head parser, and this specification does not claim them:

- the RFC 3986 IPv6 and IPvFuture grammar inside brackets;
- the full `absolute-URI` grammar for schemes other than the shape above;
- percent-encoding, and what a proxy does after it decodes a target;
- a limit on the size of a head;
- the response a server sends after a refusal.

## Smuggling inputs

The ten messages in `Http.Spec.smugglingVectors` are rejected. They are Content-Length with Transfer-Encoding, Transfer-Encoding with Content-Length, `chunked, gzip`, Transfer-Encoding on HTTP/1.0, a chunk whose terminator is not CRLF, a space before a colon, a folded line, a bare LF, two Content-Length lines, and `Content-Length: +5`.
