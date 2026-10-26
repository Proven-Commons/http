/-
  The grammar of the request target, the Host field and a
  Transfer-Encoding list, for the code: the rules that `isMatch` checks
  a target, a Host value and a Transfer-Encoding value against.
  `Proofs/` shows each is the rule of the same name in
  `Spec/Rules.lean`.
-/

import Http.Abnf

open Http.Re

namespace Http.Grammar

/-! ## RFC 5234, Appendix B.1 -/

/-- `ALPHA = %x41-5A / %x61-7A ; A-Z / a-z` -/
def ALPHA : Re := alt (range 0x41 0x5A) (range 0x61 0x7A)

/-- `DIGIT = %x30-39 ; 0-9` -/
def DIGIT : Re := range 0x30 0x39

/-- `HEXDIG = DIGIT / "A" / "B" / "C" / "D" / "E" / "F"` -/
def HEXDIG : Re :=
  any [DIGIT, litCI "A", litCI "B", litCI "C", litCI "D", litCI "E", litCI "F"]

/-! ## RFC 3986, Appendix A -/

/-- `unreserved = ALPHA / DIGIT / "-" / "." / "_" / "~"` -/
def unreserved : Re := any [ALPHA, DIGIT, litCI "-", litCI ".", litCI "_", litCI "~"]

/-- `pct-encoded = "%" HEXDIG HEXDIG` -/
def pctEncoded : Re := seq [litCI "%", HEXDIG, HEXDIG]

/-- `sub-delims = "!" / "$" / "&" / "'" / "(" / ")" / "*" / "+" / "," / ";" / "="` -/
def subDelims : Re :=
  any [litCI "!", litCI "$", litCI "&", litCI "'", litCI "(", litCI ")", litCI "*", litCI "+",
    litCI ",", litCI ";", litCI "="]

/-- `pchar = unreserved / pct-encoded / sub-delims / ":" / "@"` -/
def pchar : Re := any [unreserved, pctEncoded, subDelims, litCI ":", litCI "@"]

/-- `segment = *pchar` -/
def segment : Re := star pchar

/-- `segment-nz = 1*pchar` -/
def segmentNz : Re := plus pchar

/-- `query = *( pchar / "/" / "?" )` -/
def query : Re := star (any [pchar, litCI "/", litCI "?"])

/-- `scheme = ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )` -/
def scheme : Re := cat ALPHA (star (any [ALPHA, DIGIT, litCI "+", litCI "-", litCI "."]))

/-- `userinfo = *( unreserved / pct-encoded / sub-delims / ":" )` -/
def userinfo : Re := star (any [unreserved, pctEncoded, subDelims, litCI ":"])

/-- `h16 = 1*4HEXDIG` -/
def h16 : Re := between 1 4 HEXDIG

/-- `dec-octet = DIGIT / %x31-39 DIGIT / "1" 2DIGIT / "2" %x30-34 DIGIT /
    "25" %x30-35` -/
def decOctet : Re :=
  any [DIGIT, cat (range 0x31 0x39) DIGIT, cat (litCI "1") (rep 2 DIGIT),
    seq [litCI "2", range 0x30 0x34, DIGIT], cat (litCI "25") (range 0x30 0x35)]

/-- `IPv4address = dec-octet "." dec-octet "." dec-octet "." dec-octet` -/
def IPv4address : Re :=
  seq [decOctet, litCI ".", decOctet, litCI ".", decOctet, litCI ".", decOctet]

/-- `ls32 = ( h16 ":" h16 ) / IPv4address` -/
def ls32 : Re := alt (seq [h16, litCI ":", h16]) IPv4address

/-- `h16 ":"`, which `IPv6address` repeats. -/
def h16c : Re := cat h16 (litCI ":")

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
def IPv6address : Re :=
  any [
    cat (rep 6 h16c) ls32,
    seq [litCI "::", rep 5 h16c, ls32],
    seq [opt h16, litCI "::", rep 4 h16c, ls32],
    seq [opt (cat (upTo 1 h16c) h16), litCI "::", rep 3 h16c, ls32],
    seq [opt (cat (upTo 2 h16c) h16), litCI "::", rep 2 h16c, ls32],
    seq [opt (cat (upTo 3 h16c) h16), litCI "::", h16, litCI ":", ls32],
    seq [opt (cat (upTo 4 h16c) h16), litCI "::", ls32],
    seq [opt (cat (upTo 5 h16c) h16), litCI "::", h16],
    cat (opt (cat (upTo 6 h16c) h16)) (litCI "::")]

/-- `IPvFuture = "v" 1*HEXDIG "." 1*( unreserved / sub-delims / ":" )` -/
def IPvFuture : Re :=
  seq [litCI "v", plus HEXDIG, litCI ".", plus (any [unreserved, subDelims, litCI ":"])]

/-- `IP-literal = "[" ( IPv6address / IPvFuture ) "]"` -/
def IPliteral : Re := seq [litCI "[", alt IPv6address IPvFuture, litCI "]"]

/-- `reg-name = *( unreserved / pct-encoded / sub-delims )` -/
def regName : Re := star (any [unreserved, pctEncoded, subDelims])

/-- `host = IP-literal / IPv4address / reg-name` -/
def host : Re := any [IPliteral, IPv4address, regName]

/-- `port = *DIGIT` -/
def port : Re := star DIGIT

/-- `authority = [ userinfo "@" ] host [ ":" port ]` -/
def authority : Re :=
  seq [opt (cat userinfo (litCI "@")), host, opt (cat (litCI ":") port)]

/-- `path-abempty = *( "/" segment )` -/
def pathAbempty : Re := star (cat (litCI "/") segment)

/-- `path-absolute = "/" [ segment-nz *( "/" segment ) ]` -/
def pathAbsolute : Re := cat (litCI "/") (opt (cat segmentNz pathAbempty))

/-- `path-rootless = segment-nz *( "/" segment )` -/
def pathRootless : Re := cat segmentNz pathAbempty

/-- `path-empty = 0<pchar>` -/
def pathEmpty : Re := eps

/-- `hier-part = "//" authority path-abempty / path-absolute / path-rootless /
    path-empty` -/
def hierPart : Re :=
  any [seq [litCI "//", authority, pathAbempty], pathAbsolute, pathRootless,
    pathEmpty]

/-- `absolute-URI = scheme ":" hier-part [ "?" query ]` -/
def absoluteURI : Re := seq [scheme, litCI ":", hierPart, opt (cat (litCI "?") query)]

/-! ## RFC 9110, sections 4.1 and 7.2 -/

/-- `absolute-path = 1*( "/" segment )` (section 4.1) -/
def absolutePath : Re := plus (cat (litCI "/") segment)

/-- `uri-host = <host, see [URI], Section 3.2.2>` -/
def uriHost : Re := host

/-- `Host = uri-host [ ":" port ]` (section 7.2) -/
def hostValue : Re := cat uriHost (opt (cat (litCI ":") port))

/-! ## RFC 9110, sections 5.6.1.2 and 5.6.3 -/

/-- `SP = %x20` -/
def SP : Re := byte 0x20

/-- `HTAB = %x09 ; horizontal tab` -/
def HTAB : Re := byte 0x09

/-- `OWS = *( SP / HTAB )` (section 5.6.3) -/
def OWS : Re := star (alt SP HTAB)

/-- A list with one element, `e`, as a recipient reads a list (section
    5.6.1.2): `*( OWS "," OWS ) element *( OWS "," OWS )`. -/
def listOne (e : Re) : Re :=
  seq [star (seq [OWS, litCI ",", OWS]), e, star (seq [OWS, litCI ",", OWS])]

/-- A Transfer-Encoding value that lists the one coding `chunked`. -/
def chunkedList : Re := listOne (litCI "chunked")

/-! ## RFC 9112 -/

/-- `origin-form = absolute-path [ "?" query ]` (section 3.2.1) -/
def originForm : Re := cat absolutePath (opt (cat (litCI "?") query))

/-- `absolute-form = absolute-URI` (section 3.2.2) -/
def absoluteForm : Re := absoluteURI

/-- `authority-form = uri-host ":" port` (section 3.2.3) -/
def authorityForm : Re := seq [uriHost, litCI ":", port]

/-- `asterisk-form = "*"` (section 3.2.4) -/
def asteriskForm : Re := litCI "*"

/-- `request-target = origin-form / absolute-form / authority-form /
    asterisk-form` (section 3.2) -/
def requestTarget : Re :=
  any [originForm, absoluteForm, authorityForm, asteriskForm]

end Http.Grammar
