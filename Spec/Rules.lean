/-
  The ABNF rules this library reads, written in the notation of
  `Http/Abnf.lean`, rule for rule and in the RFCs' own order of
  alternatives. Part of the approved specification, with `Spec.lean`,
  and written from the RFCs, independently of the code in `Http/`.

  The sources:
  - RFC 5234, Appendix B.1: the core rules.
  - RFC 9110, sections 4.1, 5.1, 5.5, 5.6.1.2, 5.6.2, 5.6.3, 7.2 and
    8.6: tokens, whitespace, field names and values, a list of one
    element, `absolute-path`, `Host` and `Content-Length`.
  - RFC 3986, Appendix A: the URI rules the request target uses.
  - RFC 9112, sections 3 and 3.2: the method and the four forms of
    request target. The version, whose digits `Head` keeps as numbers,
    is in `Spec/Defs.lean`.

  A quoted string in ABNF is case-insensitive (RFC 5234, section 2.3),
  so it is written `litCI`.
-/

import Http.Abnf

open Http Http.Re

/-! ## RFC 5234, Appendix B.1 -/

/-- `ALPHA = %x41-5A / %x61-7A ; A-Z / a-z` -/
def Spec.ALPHA : Re := alt (range 0x41 0x5A) (range 0x61 0x7A)

/-- `DIGIT = %x30-39 ; 0-9` -/
def Spec.DIGIT : Re := range 0x30 0x39

/-- `HEXDIG = DIGIT / "A" / "B" / "C" / "D" / "E" / "F"` -/
def Spec.HEXDIG : Re :=
  any [Spec.DIGIT, litCI "A", litCI "B", litCI "C", litCI "D", litCI "E", litCI "F"]

/-- `VCHAR = %x21-7E ; visible (printing) characters` -/
def Spec.VCHAR : Re := range 0x21 0x7E

/-- `SP = %x20` -/
def Spec.SP : Re := byte 0x20

/-- `HTAB = %x09 ; horizontal tab` -/
def Spec.HTAB : Re := byte 0x09

/-! ## RFC 9110 -/

/-- `tchar = "!" / "#" / "$" / "%" / "&" / "'" / "*" / "+" / "-" / "." /
    "^" / "_" / "`" / "|" / "~" / DIGIT / ALPHA` (section 5.6.2) -/
def Spec.tchar : Re :=
  any [litCI "!", litCI "#", litCI "$", litCI "%", litCI "&", litCI "'", litCI "*", litCI "+",
    litCI "-", litCI ".", litCI "^", litCI "_", litCI "`", litCI "|", litCI "~", Spec.DIGIT,
    Spec.ALPHA]

/-- `token = 1*tchar` (section 5.6.2) -/
def Spec.token : Re := plus Spec.tchar

/-- `OWS = *( SP / HTAB )` (section 5.6.3) -/
def Spec.OWS : Re := star (alt Spec.SP Spec.HTAB)

/-- `obs-text = %x80-FF` (section 5.6.4) -/
def Spec.obsText : Re := range 0x80 0xFF

/-- `field-vchar = VCHAR / obs-text` (section 5.5) -/
def Spec.fieldVchar : Re := alt Spec.VCHAR Spec.obsText

/-- `field-content = field-vchar [ 1*( SP / HTAB / field-vchar ) field-vchar ]`
    (section 5.5) -/
def Spec.fieldContent : Re :=
  cat Spec.fieldVchar (opt (cat (plus (any [Spec.SP, Spec.HTAB, Spec.fieldVchar])) Spec.fieldVchar))

/-- `field-value = *field-content` (section 5.5) -/
def Spec.fieldValue : Re := star Spec.fieldContent

/-- `field-name = token` (section 5.1) -/
def Spec.fieldName : Re := Spec.token

/-- `Content-Length = 1*DIGIT` (section 8.6) -/
def Spec.contentLength : Re := plus Spec.DIGIT

/-- A list with one element, `e`, as a recipient reads a list (section
    5.6.1.2): "a recipient MUST accept lists that satisfy the following
    syntax: `#element => [ element ] *( OWS "," OWS [ element ] )`",
    where "Empty elements do not contribute to the count of elements
    present". With one element present and every other one empty, that
    is `*( OWS "," OWS ) element *( OWS "," OWS )`. -/
def Spec.listOne (e : Re) : Re :=
  seq [star (seq [Spec.OWS, litCI ",", Spec.OWS]), e, star (seq [Spec.OWS, litCI ",", Spec.OWS])]

/-! ## RFC 3986, Appendix A -/

/-- `unreserved = ALPHA / DIGIT / "-" / "." / "_" / "~"` -/
def Spec.unreserved : Re := any [Spec.ALPHA, Spec.DIGIT, litCI "-", litCI ".", litCI "_", litCI "~"]

/-- `pct-encoded = "%" HEXDIG HEXDIG` -/
def Spec.pctEncoded : Re := seq [litCI "%", Spec.HEXDIG, Spec.HEXDIG]

/-- `sub-delims = "!" / "$" / "&" / "'" / "(" / ")" / "*" / "+" / "," / ";" / "="` -/
def Spec.subDelims : Re :=
  any [litCI "!", litCI "$", litCI "&", litCI "'", litCI "(", litCI ")", litCI "*", litCI "+",
    litCI ",", litCI ";", litCI "="]

/-- `pchar = unreserved / pct-encoded / sub-delims / ":" / "@"` -/
def Spec.pchar : Re := any [Spec.unreserved, Spec.pctEncoded, Spec.subDelims, litCI ":", litCI "@"]

/-- `segment = *pchar` -/
def Spec.segment : Re := star Spec.pchar

/-- `segment-nz = 1*pchar` -/
def Spec.segmentNz : Re := plus Spec.pchar

/-- `query = *( pchar / "/" / "?" )` -/
def Spec.query : Re := star (any [Spec.pchar, litCI "/", litCI "?"])

/-- `scheme = ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )` -/
def Spec.scheme : Re := cat Spec.ALPHA (star (any [Spec.ALPHA, Spec.DIGIT, litCI "+", litCI "-", litCI "."]))

/-- `userinfo = *( unreserved / pct-encoded / sub-delims / ":" )` -/
def Spec.userinfo : Re := star (any [Spec.unreserved, Spec.pctEncoded, Spec.subDelims, litCI ":"])

/-- `h16 = 1*4HEXDIG` -/
def Spec.h16 : Re := between 1 4 Spec.HEXDIG

/-- `dec-octet = DIGIT / %x31-39 DIGIT / "1" 2DIGIT / "2" %x30-34 DIGIT /
    "25" %x30-35` -/
def Spec.decOctet : Re :=
  any [Spec.DIGIT, cat (range 0x31 0x39) Spec.DIGIT, cat (litCI "1") (rep 2 Spec.DIGIT),
    seq [litCI "2", range 0x30 0x34, Spec.DIGIT], cat (litCI "25") (range 0x30 0x35)]

/-- `IPv4address = dec-octet "." dec-octet "." dec-octet "." dec-octet` -/
def Spec.IPv4address : Re :=
  seq [Spec.decOctet, litCI ".", Spec.decOctet, litCI ".", Spec.decOctet, litCI ".", Spec.decOctet]

/-- `ls32 = ( h16 ":" h16 ) / IPv4address` -/
def Spec.ls32 : Re := alt (seq [Spec.h16, litCI ":", Spec.h16]) Spec.IPv4address

/-- `h16 ":"`, which `IPv6address` repeats. -/
def Spec.h16c : Re := cat Spec.h16 (litCI ":")

/-- ```
    IPv6address =                            6( h16 ":" ) ls32
                /                       "::" 5( h16 ":" ) ls32
                / [               h16 ] "::" 4( h16 ":" ) ls32
                / [ *1( h16 ":" ) h16 ] "::" 3( h16 ":" ) ls32
                / [ *2( h16 ":" ) h16 ] "::" 2( h16 ":" ) ls32
                / [ *3( h16 ":" ) h16 ] "::"    h16 ":"   ls32
                / [ *4( h16 ":" ) h16 ] "::"              ls32
                / [ *5( h16 ":" ) h16 ] "::"              h16
                / [ *6( h16 ":" ) h16 ] "::"
    ``` -/
def Spec.IPv6address : Re :=
  any [
    cat (rep 6 Spec.h16c) Spec.ls32,
    seq [litCI "::", rep 5 Spec.h16c, Spec.ls32],
    seq [opt Spec.h16, litCI "::", rep 4 Spec.h16c, Spec.ls32],
    seq [opt (cat (upTo 1 Spec.h16c) Spec.h16), litCI "::", rep 3 Spec.h16c, Spec.ls32],
    seq [opt (cat (upTo 2 Spec.h16c) Spec.h16), litCI "::", rep 2 Spec.h16c, Spec.ls32],
    seq [opt (cat (upTo 3 Spec.h16c) Spec.h16), litCI "::", Spec.h16, litCI ":", Spec.ls32],
    seq [opt (cat (upTo 4 Spec.h16c) Spec.h16), litCI "::", Spec.ls32],
    seq [opt (cat (upTo 5 Spec.h16c) Spec.h16), litCI "::", Spec.h16],
    cat (opt (cat (upTo 6 Spec.h16c) Spec.h16)) (litCI "::")]

/-- `IPvFuture = "v" 1*HEXDIG "." 1*( unreserved / sub-delims / ":" )` -/
def Spec.IPvFuture : Re :=
  seq [litCI "v", plus Spec.HEXDIG, litCI ".", plus (any [Spec.unreserved, Spec.subDelims, litCI ":"])]

/-- `IP-literal = "[" ( IPv6address / IPvFuture ) "]"` -/
def Spec.IPliteral : Re := seq [litCI "[", alt Spec.IPv6address Spec.IPvFuture, litCI "]"]

/-- `reg-name = *( unreserved / pct-encoded / sub-delims )` -/
def Spec.regName : Re := star (any [Spec.unreserved, Spec.pctEncoded, Spec.subDelims])

/-- `host = IP-literal / IPv4address / reg-name` -/
def Spec.host : Re := any [Spec.IPliteral, Spec.IPv4address, Spec.regName]

/-- `port = *DIGIT` -/
def Spec.port : Re := star Spec.DIGIT

/-- `authority = [ userinfo "@" ] host [ ":" port ]` -/
def Spec.authority : Re :=
  seq [opt (cat Spec.userinfo (litCI "@")), Spec.host, opt (cat (litCI ":") Spec.port)]

/-- `path-abempty = *( "/" segment )` -/
def Spec.pathAbempty : Re := star (cat (litCI "/") Spec.segment)

/-- `path-absolute = "/" [ segment-nz *( "/" segment ) ]` -/
def Spec.pathAbsolute : Re := cat (litCI "/") (opt (cat Spec.segmentNz Spec.pathAbempty))

/-- `path-rootless = segment-nz *( "/" segment )` -/
def Spec.pathRootless : Re := cat Spec.segmentNz Spec.pathAbempty

/-- `path-empty = 0<pchar>` -/
def Spec.pathEmpty : Re := eps

/-- `hier-part = "//" authority path-abempty / path-absolute / path-rootless /
    path-empty` -/
def Spec.hierPart : Re :=
  any [seq [litCI "//", Spec.authority, Spec.pathAbempty], Spec.pathAbsolute, Spec.pathRootless,
    Spec.pathEmpty]

/-- `absolute-URI = scheme ":" hier-part [ "?" query ]` -/
def Spec.absoluteURI : Re := seq [Spec.scheme, litCI ":", Spec.hierPart, opt (cat (litCI "?") Spec.query)]

/-! ## RFC 9110, sections 4.1 and 7.2 -/

/-- `absolute-path = 1*( "/" segment )` (section 4.1) -/
def Spec.absolutePath : Re := plus (cat (litCI "/") Spec.segment)

/-- `uri-host = <host, see [URI], Section 3.2.2>` -/
def Spec.uriHost : Re := Spec.host

/-- `Host = uri-host [ ":" port ]` (section 7.2) -/
def Spec.hostValue : Re := cat Spec.uriHost (opt (cat (litCI ":") Spec.port))

/-! ## RFC 9112 -/

/-- `method = token` (section 3.1) -/
def Spec.method : Re := Spec.token

/-- `origin-form = absolute-path [ "?" query ]` (section 3.2.1) -/
def Spec.originForm : Re := cat Spec.absolutePath (opt (cat (litCI "?") Spec.query))

/-- `absolute-form = absolute-URI` (section 3.2.2) -/
def Spec.absoluteForm : Re := Spec.absoluteURI

/-- `authority-form = uri-host ":" port` (section 3.2.3) -/
def Spec.authorityForm : Re := seq [Spec.uriHost, litCI ":", Spec.port]

/-- `asterisk-form = "*"` (section 3.2.4) -/
def Spec.asteriskForm : Re := litCI "*"

/-- `request-target = origin-form / absolute-form / authority-form /
    asterisk-form` (section 3.2) -/
def Spec.requestTarget : Re :=
  any [Spec.originForm, Spec.absoluteForm, Spec.authorityForm, Spec.asteriskForm]
