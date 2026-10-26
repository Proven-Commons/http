/-
  The definitions the statements use: the text of a request head, and
  the rules of RFC 9112 and RFC 9110 for which requests this library
  accepts and how the body that follows the head is framed. Part of the
  approved specification, with `Spec.lean`, and written from the RFCs,
  independently of the code in `Http/`.
-/

import Http.Types
import Spec.Abnf
import Spec.Rules

open Http

/-! ## Octets -/

/-- The octets of an ASCII string. -/
def Spec.ascii (s : String) : List UInt8 := s.toList.map fun c => c.toNat.toUInt8

/-- `CRLF = CR LF ; Internet standard newline` (RFC 5234, Appendix B.1). -/
def Spec.crlf : List UInt8 := [0x0D, 0x0A]

/-- The octet of a decimal digit. -/
def Spec.digit (n : Nat) : UInt8 := (0x30 + n).toUInt8

/-! ## The head

RFC 9112, section 2.1:

```
HTTP-message   = start-line CRLF
                 *( field-line CRLF )
                 CRLF
                 [ message-body ]
```

and for a request, `start-line` is `request-line` (section 3):

```
request-line   = method SP request-target SP HTTP-version
HTTP-version  = HTTP-name "/" DIGIT "." DIGIT
HTTP-name     = %s"HTTP"
field-line   = field-name ":" OWS field-value OWS
```

Section 5.1: "The field line value does not include that leading or
trailing whitespace". Section 2.2: "a server that is expecting to
receive and parse a request-line SHOULD ignore at least one empty line
(CRLF) received prior to the request-line"; here any number of them is
ignored.

Where RFC 9112 lets a recipient choose to repair a message, the head
here does not allow it, and so it is rejected:
- "a recipient MAY recognize a single LF as a line terminator"
  (section 2.2): only CRLF ends a line here;
- "A recipient of such a bare CR MUST consider that element to be
  invalid or replace each bare CR with SP" (section 2.2);
- "A recipient that receives whitespace between the start-line and the
  first header field MUST either reject the message as invalid or
  consume each whitespace-preceded line" (section 2.2);
- "recipients MAY instead parse on whitespace-delimited word boundaries"
  in the request line (section 3);
- obs-fold: "MUST either reject the message by sending a 400 (Bad
  Request) ... or replace each received obs-fold with one or more SP
  octets" (section 5.2).

None of these fit the grammar: a field line cannot begin with
whitespace, and a field value holds no CR, LF or NUL. Section 5.1 leaves
no choice: "A server MUST reject ... any received request message that
contains whitespace between a header field name and colon".
-/

/-- The request line of a head. -/
def Spec.requestLine (h : Head) : List UInt8 :=
  h.method ++ [0x20] ++ h.target ++ [0x20] ++ Spec.ascii "HTTP/" ++
    [Spec.digit h.major, 0x2E, Spec.digit h.minor]

/-- A field line's name is a `field-name` and its value a `field-value`. -/
def Spec.FieldValid (f : Field) : Prop :=
  Spec.Matches Spec.fieldName f.name ∧ Spec.Matches Spec.fieldValue f.value

/-- A head of the grammar: the method is a `method`, the target a
    `request-target`, each version number a `DIGIT`, and each field
    valid. -/
def Spec.HeadValid (h : Head) : Prop :=
  Spec.Matches Spec.method h.method ∧ Spec.Matches Spec.requestTarget h.target ∧
    h.major ≤ 9 ∧ h.minor ≤ 9 ∧ ∀ f ∈ h.fields, Spec.FieldValid f

/-- `t` is a field line for `f`: `field-name ":" OWS field-value OWS`. -/
def Spec.FieldLineText (f : Field) (t : List UInt8) : Prop :=
  ∃ w1 w2, Spec.Matches Spec.OWS w1 ∧ Spec.Matches Spec.OWS w2 ∧
    t = f.name ++ [0x3A] ++ w1 ++ f.value ++ w2

/-- `t` is a field line for each field in order, each with its CRLF,
    then the empty line. -/
def Spec.FieldsText : List Field → List UInt8 → Prop
  | [], t => t = Spec.crlf
  | f :: fs, t => ∃ l t', Spec.FieldLineText f l ∧ Spec.FieldsText fs t' ∧ t = l ++ Spec.crlf ++ t'

/-- `t` is the head `h` as written: its request line and CRLF, then its
    fields and the empty line. -/
def Spec.HeadText (h : Head) (t : List UInt8) : Prop :=
  ∃ t', Spec.FieldsText h.fields t' ∧ t = Spec.requestLine h ++ Spec.crlf ++ t'

/-- `bs` begins with the head `h`, after any number of empty lines, and
    `rest` follows it. -/
def Spec.Reads (bs : List UInt8) (h : Head) (rest : List UInt8) : Prop :=
  Spec.HeadValid h ∧
    ∃ k t, Spec.HeadText h t ∧ bs = (List.replicate k Spec.crlf).flatten ++ t ++ rest

/-- The head as a sender writes it, with one SP after each colon, as
    section 5.1 prefers. -/
def Spec.render (h : Head) : List UInt8 :=
  Spec.requestLine h ++ Spec.crlf ++
    (h.fields.map fun f => f.name ++ [0x3A, 0x20] ++ f.value ++ Spec.crlf).flatten ++ Spec.crlf

/-! ## Which requests are accepted, and their framing

RFC 9110, section 5.1: "Field names are case-insensitive."

RFC 9110, section 6.2: "A server can send a 505 (HTTP Version Not
Supported) response if it wishes, for any reason, to refuse service of
the client's major protocol version", and "A recipient that receives a
message with a major version number that it implements and a minor
version number higher than what it implements SHOULD process the
message as if it were in the highest minor version within that major
version to which the recipient is conformant". Here only major version
1 is accepted, and a minor version of 1 or more is handled as 1.1.

RFC 9112, section 3.2: "A server MUST respond with a 400 (Bad Request)
status code to any HTTP/1.1 request message that lacks a Host header
field and to any request message that contains more than one Host header
field line or a Host header field with an invalid field value."

RFC 9110, section 9.3.6: "CONNECT uses a special form of request
target, unique to this method, consisting of only the host and port
number of the tunnel destination, separated by a colon", and "A server
MUST reject a CONNECT request that targets an empty or invalid port
number". Section 9.1: "The method token is case-sensitive", so the
method is compared as written. The RFC does not say which port numbers
are invalid. Here a valid one is from 1 to 65535: a TCP port number is
16 bits (RFC 9293, section 3.1), and 0 is a Reserved port number (RFC
6335, section 6). A server need not accept CONNECT at all (section
9.3.6: "An origin server MAY accept a CONNECT request"), so refusing
port 0 is allowed however "invalid" is read.

RFC 9110, sections 4.2.1 and 4.2.2: "A sender MUST NOT generate an
"http" URI with an empty host identifier. A recipient that processes
such a URI reference MUST reject it as invalid", and the same for
"https". Section 4.2.4: "a recipient SHOULD parse for userinfo and treat
its presence as an error". So a target whose scheme is http or https, in
any case (RFC 3986, section 3.1: "schemes are case-insensitive"), must
be an `http-URI` or `https-URI` with a host that is not empty and no
userinfo. A CONNECT target is a host and a port, not a URI, so the rule
does not apply to it: `CONNECT http:80` names the host `http`.

RFC 9110, section 5.2: when a field name is repeated, "its combined
field value consists of the list of corresponding field line values
within that section, concatenated in order, with each field line value
separated by a comma".

RFC 9112, section 6.3, for a request, with this library's choices where
the RFC gives one:
- "If a message is received with both a Transfer-Encoding and a
  Content-Length header field ... Such a message might indicate an
  attempt to perform request smuggling ... and ought to be handled as an
  error", and section 6.1: "A server MAY reject a request that contains
  both Content-Length and Transfer-Encoding". Rejected here.
- "If a Transfer-Encoding header field is present and the chunked
  transfer coding (Section 7.1) is the final encoding, the message body
  length is determined by reading and decoding the chunked data". This
  library decodes no other coding, and section 6.1 says "A server that
  receives a request message with a transfer coding it does not
  understand SHOULD respond with 501 (Not Implemented)". So
  Transfer-Encoding is accepted only when its combined field value is a
  list of the one coding `chunked`, in any case (RFC 9112, section 7:
  "All transfer-coding names are case-insensitive"). Transfer-Encoding
  is `#transfer-coding` (section 6.1), and empty list elements do not
  count (RFC 9110, section 5.6.1.2), so `chunked,` and `, chunked` are
  such lists, and so is a `chunked` field line with an empty one. Any
  other value is rejected:
  - with no coding, or chunked not last, section 6.3 says "the server
    MUST respond with the 400 (Bad Request) status code";
  - with chunked twice, the sender broke section 6.1, "A sender MUST NOT
    apply the chunked transfer coding more than once", and RFC 9110,
    section 15.5.1, lets a server answer "invalid request message
    framing" with 400;
  - otherwise, the value names a coding this library does not
    understand.
- Section 6.1: "A server or client that receives an HTTP/1.0 message
  containing a Transfer-Encoding header field MUST treat the message as
  if the framing is faulty". Rejected here.
- "If a message is received without Transfer-Encoding and with an
  invalid Content-Length header field, then the message framing is
  invalid and the recipient MUST treat it as an unrecoverable error,
  unless the field value can be successfully parsed as a comma-separated
  list ... and all values in the list are the same". This library does
  not take that exception: Content-Length must be one field line whose
  value is `1*DIGIT` (RFC 9110, section 8.6).
- "If a valid Content-Length header field is present without
  Transfer-Encoding, its decimal value defines the expected message body
  length in octets."
- "If this is a request message and none of the above are true, then
  the message body length is zero".
-/

/-- ASCII lower case. -/
def Spec.lower (c : UInt8) : UInt8 := if 0x41 ≤ c ∧ c ≤ 0x5A then c + 0x20 else c

/-- The fields of the head named `n`, given in lower case, compared
    without regard to ASCII case. -/
def Spec.named (h : Head) (n : String) : List Field :=
  h.fields.filter fun f => f.name.map Spec.lower = Spec.ascii n

/-- The number that a string of decimal digits writes. -/
def Spec.decimal (ds : List UInt8) : Nat := ds.foldl (fun n d => 10 * n + (d.toNat - 0x30)) 0

/-- The Host rule of section 3.2. -/
def Spec.HostOK (h : Head) : Prop :=
  (Spec.named h "host").length ≤ 1 ∧ (1 ≤ h.minor → (Spec.named h "host").length = 1) ∧
    ∀ f ∈ Spec.named h "host", Spec.Matches Spec.hostValue f.value

/-- The rule of RFC 9110 section 9.3.6 for CONNECT: the target is
    `uri-host ":" port`, with a port from 1 to 65535. An empty port
    writes 0, so it is refused. -/
def Spec.ConnectOK (h : Head) : Prop :=
  h.method = Spec.ascii "CONNECT" →
    ∃ host port, h.target = host ++ [0x3A] ++ port ∧ Spec.Matches Spec.uriHost host ∧
      Spec.Matches Spec.port port ∧ 1 ≤ Spec.decimal port ∧ Spec.decimal port ≤ 65535

/-- The rule of RFC 9110 sections 4.2.1, 4.2.2 and 4.2.4 for a target
    whose scheme is http or https, for any method but CONNECT. -/
def Spec.HttpTargetOK (h : Head) : Prop :=
  h.method ≠ Spec.ascii "CONNECT" →
    (Spec.ascii "http:" <+: h.target.map Spec.lower ∨ Spec.ascii "https:" <+: h.target.map Spec.lower) →
      Spec.Matches Spec.httpTarget h.target

/-- The combined field value of the field lines `fs` (RFC 9110, section
    5.2): their values in order, separated by commas. -/
def Spec.combined (fs : List Field) : List UInt8 := List.intercalate [0x2C] (fs.map (·.value))

/-- The body after the head is framed as `fr`, by section 6.3 with the
    choices above. -/
def Spec.FramedAs (h : Head) : Framing → Prop
  | .chunked =>
    1 ≤ h.minor ∧ Spec.named h "content-length" = [] ∧ Spec.named h "transfer-encoding" ≠ [] ∧
      Spec.Matches (Spec.listOne (Re.litCI "chunked")) (Spec.combined (Spec.named h "transfer-encoding"))
  | .length n =>
    Spec.named h "transfer-encoding" = [] ∧
      ((Spec.named h "content-length" = [] ∧ n = 0) ∨
        ∃ f, Spec.named h "content-length" = [f] ∧ Spec.Matches Spec.contentLength f.value ∧
          n = Spec.decimal f.value)

/-- This library accepts the head, and frames its body as `fr`. -/
def Spec.Accepts (h : Head) (fr : Framing) : Prop :=
  h.major = 1 ∧ Spec.HostOK h ∧ Spec.ConnectOK h ∧ Spec.HttpTargetOK h ∧ Spec.FramedAs h fr
