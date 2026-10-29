# Planted bugs

Written by `python3 tests/planted_bugs.py`. Each row is one small change to the
code, made in a copy. The tests ran on 300,000 inputs from their recorded seed
against the changed tool. A bug is caught when they report failures.

| Bug | File | Failures |
|-----|------|----------|
| bare LF ends a line | `Http/Head.lean` | 6090 |
| bare CR kept in a line | `Http/Head.lean` | 0, equivalent: the code gives `none` for a CR that is not followed by LF, and the change keeps that CR in the line instead. Every line is then read by parseHead or parseField, and neither accepts a CR: not in the method (a token), the target (no rule of the target grammar has 0x0D), the version (exactly `HTTP/` digit `.` digit), a field name (a token) or a field value (trim removes only SP and HTAB, and isFieldValue allows only field-vchar, SP and HTAB). A line holding a CR is not empty, so it never ends the head. So parseHead gives `none` in both, and on every other input the code is the same |
| space before colon dropped | `Http/Head.lean` | 8646 |
| trailing whitespace kept | `Http/Head.lean` | 206968 |
| NUL allowed in a value | `Http/Head.lean` | 3433 |
| a double quote in a token | `Http/Head.lean` | 17 |
| empty lines first not skipped | `Http/Head.lean` | 38254 |
| minor version digit unchecked | `Http/Head.lean` | 67 |
| Host not required in HTTP/1.1 | `Http/Framing.lean` | 5825 |
| two Host lines accepted | `Http/Framing.lean` | 929 |
| upper-case field names matched twice | `Http/Framing.lean` | 0, equivalent: on every head that parseHead gives, the only heads the tool frames, it matches the same fields. `n.map (c - 0x20)` is `HOST` for `host`, which the first test already matches. For `content-length` and `transfer-encoding` it turns `-` (0x2D) into CR (0x0D), and a field name is a token, so it never holds a CR. The proof of framing_iff, which covers every Head, would catch it; the tests cannot |
| any major version accepted | `Http/Framing.lean` | 17711 |
| first of several Content-Length taken | `Http/Framing.lean` | 4234 |
| Content-Length and port digits read backwards | `Http/Framing.lean` | 23606 |
| Transfer-Encoding overrides Content-Length | `Http/Framing.lean` | 1889 |
| Transfer-Encoding in HTTP/1.0 accepted | `Http/Framing.lean` | 2891 |
| chunked compared case-sensitively | `Http/Grammar.lean` | 7112 |
| list: no empty elements before chunked | `Http/Grammar.lean` | 4546 |
| list: no empty elements after chunked | `Http/Grammar.lean` | 5047 |
| list: at most one empty element before chunked | `Http/Grammar.lean` | 2785 |
| list: a tab is not OWS | `Http/Grammar.lean` | 2335 |
| Transfer-Encoding only as one field line | `Http/Framing.lean` | 3057 |
| only the first Transfer-Encoding line read | `Http/Framing.lean` | 3880 |
| Transfer-Encoding lines joined with no comma | `Http/Framing.lean` | 351 |
| CONNECT rule removed | `Http/Framing.lean` | 1786 |
| CONNECT port up to 65536 | `Http/Framing.lean` | 84 |
| CONNECT port 0 and empty port accepted | `Http/Framing.lean` | 393 |
| CONNECT port 0 accepted | `Http/Framing.lean` | 209 |
| CONNECT port limited to five digits | `Http/Framing.lean` | 306 |
| CONNECT port leading zeros counted as digits | `Http/Framing.lean` | 485 |
| CONNECT method compared case-insensitively | `Http/Framing.lean` | 549 |
| CONNECT target form unchecked | `Http/Framing.lean` | 128 |
| CONNECT target may have an empty host | `Http/Grammar.lean` | 0, equivalent: `hostNonEmpty` and `uriHost` differ only on the empty host, so the change lets through only a CONNECT target that begins with `:`. `Head.framing` refuses every target that begins with `:` (an authority-form target with an empty host, RFC 9112 section 3.3), for any method, so the answer is the same on every input |
| empty host allowed in an authority-form target | `Http/Framing.lean` | 542 |
| CONNECT content accepted | `Http/Framing.lean` | 1222 |
| CONNECT with Content-Length accepted | `Http/Framing.lean` | 828 |
| CONNECT content rule in any case of the method | `Http/Framing.lean` | 429 |
| empty host allowed in a Host value | `Http/Grammar.lean` | 4026 |
| CONNECT port read from every digit | `Http/Framing.lean` | 1234 |
| http target rule removed | `Http/Framing.lean` | 3624 |
| userinfo allowed in an http target | `Http/Grammar.lean` | 942 |
| empty host allowed in an http target (reg-name star) | `Http/Grammar.lean` | 5227 |
| scheme compared case-sensitively in the http target grammar | `Http/Grammar.lean` | 3003 |
| scheme compared case-sensitively in the http and https prefix test | `Http/Framing.lean` | 1777 |
| CONNECT not exempt from the http target rule | `Http/Framing.lean` | 245 |
| CONNECT exempt from the http target rule in any case | `Http/Framing.lean` | 174 |
| https targets not checked | `Http/Framing.lean` | 1836 |
| a percent escape's second digit unchecked | `Http/Grammar.lean` | 90 |
| 256 as an IPv4 octet | `Http/Grammar.lean` | 159 |
| dec-octet 25 then any digit | `Http/Grammar.lean` | 320 |
| dec-octet 2 then any two digits | `Http/Grammar.lean` | 654 |
| dec-octet with a leading zero | `Http/Grammar.lean` | 357 |
| dec-octet as 1*3DIGIT | `Http/Grammar.lean` | 1667 |
| IP literal with a zone ID | `Http/Grammar.lean` | 2582 |
| host may be a bare IPv6 address | `Http/Grammar.lean` | 1193 |
| IPvFuture v case-sensitive | `Http/Grammar.lean` | 2936 |

## The changes

**bare LF ends a line** in `Http/Head.lean`:

```
-     else if c == 0x0A then none
- 
+     else if c == 0x0A then some ([], rest)
+ 
```

**bare CR kept in a line** in `Http/Head.lean`:

```
-       | d :: rest' => if d == 0x0A then some (acc.reverse, rest') else none
+       | d :: rest' => if d == 0x0A then some (acc.reverse, rest') else takeLineFrom (c :: acc) rest
```

**space before colon dropped** in `Http/Head.lean`:

```
-   let name := line.takeWhile (· != 0x3A)
- 
+   let name := (line.takeWhile (· != 0x3A)).filter (· != 0x20)
+ 
```

**trailing whitespace kept** in `Http/Head.lean`:

```
-   ((v.dropWhile isWs).reverse.dropWhile isWs).reverse
+   v.dropWhile isWs
```

**NUL allowed in a value** in `Http/Head.lean`:

```
- def isVchar (c : UInt8) : Bool := (0x21 ≤ c && c ≤ 0x7E) || 0x80 ≤ c
+ def isVchar (c : UInt8) : Bool := (0x21 ≤ c && c ≤ 0x7E) || 0x80 ≤ c || c == 0
```

**a double quote in a token** in `Http/Head.lean`:

```
-     0x60, 0x7C, 0x7E].contains c
+     0x60, 0x7C, 0x7E, 0x22].contains c
```

**empty lines first not skipped** in `Http/Head.lean`:

```
-   | c :: d :: rest => if c == 0x0D && d == 0x0A then skipEmpty rest else c :: d :: rest
+   | c :: d :: rest => c :: d :: rest
```

**minor version digit unchecked** in `Http/Head.lean`:

```
-         isDigit a && isDigit b then
+         isDigit a then
```

**Host not required in HTTP/1.1** in `Http/Framing.lean`:

```
-  || (1 ≤ h.minor && hosts.length != 1)
+ 
```

**two Host lines accepted** in `Http/Framing.lean`:

```
-  || hosts.length > 1
+ 
```

**upper-case field names matched twice** in `Http/Framing.lean`:

```
- def Field.isNamed (f : Field) (n : List UInt8) : Bool := f.name.map lower == n
+ def Field.isNamed (f : Field) (n : List UInt8) : Bool := f.name.map lower == n || f.name == n.map (fun c => c - 0x20)
```

**any major version accepted** in `Http/Framing.lean`:

```
-   if h.major != 1 ||
+   if
```

**first of several Content-Length taken** in `Http/Framing.lean`:

```
-     | [], [f] => if
+     | [], f :: _ => if
```

**Content-Length and port digits read backwards** in `Http/Framing.lean`:

```
- def decimal (ds : List UInt8) : Nat := ds.foldl (fun n d => 10 * n + (d.toNat - 0x30)) 0
+ def decimal (ds : List UInt8) : Nat := ds.foldr (fun d n => 10 * n + (d.toNat - 0x30)) 0
```

**Transfer-Encoding overrides Content-Length** in `Http/Framing.lean`:

```
-     | _, _ => none
- 
+     | t :: ts, _ =>
+       if 1 ≤ h.minor && Grammar.chunkedList.isMatch (List.intercalate [0x2C] ((t :: ts).map (·.value)))
+       then some .chunked else none
+     | _, _ => none
+ 
```

**Transfer-Encoding in HTTP/1.0 accepted** in `Http/Framing.lean`:

```
- if 1 ≤ h.minor && Grammar.chunkedList.isMatch
+ if Grammar.chunkedList.isMatch
```

**chunked compared case-sensitively** in `Http/Grammar.lean`:

```
- def chunkedList : Re := listOne (litCI "chunked")
+ def chunkedList : Re := listOne (lit "chunked")
```

**list: no empty elements before chunked** in `Http/Grammar.lean`:

```
-   seq [star (seq [OWS, litCI ",", OWS]), e, star (seq [OWS, litCI ",", OWS])]
+   seq [e, star (seq [OWS, litCI ",", OWS])]
```

**list: no empty elements after chunked** in `Http/Grammar.lean`:

```
-   seq [star (seq [OWS, litCI ",", OWS]), e, star (seq [OWS, litCI ",", OWS])]
+   seq [star (seq [OWS, litCI ",", OWS]), e]
```

**list: at most one empty element before chunked** in `Http/Grammar.lean`:

```
-   seq [star (seq [OWS, litCI ",", OWS]), e, star (seq [OWS, litCI ",", OWS])]
+   seq [opt (seq [OWS, litCI ",", OWS]), e, star (seq [OWS, litCI ",", OWS])]
```

**list: a tab is not OWS** in `Http/Grammar.lean`:

```
- def OWS : Re := star (alt SP HTAB)
+ def OWS : Re := star SP
```

**Transfer-Encoding only as one field line** in `Http/Framing.lean`:

```
-     | t :: ts, [] =>
-       if 1 ≤ h.minor && Grammar.chunkedList.isMatch (List.intercalate [0x2C] ((t :: ts).map (·.value)))
- 
+     | [t], [] =>
+       if 1 ≤ h.minor && Grammar.chunkedList.isMatch t.value
+ 
```

**only the first Transfer-Encoding line read** in `Http/Framing.lean`:

```
- ((t :: ts).map (·.value))
+ ([t].map (·.value))
```

**Transfer-Encoding lines joined with no comma** in `Http/Framing.lean`:

```
- List.intercalate [0x2C]
+ List.intercalate []
```

**CONNECT rule removed** in `Http/Framing.lean`:

```
- !h.connectOK || 
+ 
```

**CONNECT port up to 65536** in `Http/Framing.lean`:

```
- decimal ds ≤ 65535 else false
+ decimal ds ≤ 65536 else false
```

**CONNECT port 0 and empty port accepted** in `Http/Framing.lean`:

```
- then 1 ≤ decimal ds &&
+ then 0 ≤ decimal ds &&
```

**CONNECT port 0 accepted** in `Http/Framing.lean`:

```
- portInRange (portOf h.target))
+ (portInRange (portOf h.target) || (!(portOf h.target).isEmpty && (portOf h.target).all (· == 0x30))))
```

**CONNECT port limited to five digits** in `Http/Framing.lean`:

```
- then 1 ≤ decimal ds && decimal ds ≤ 65535 else false
+ then 1 ≤ decimal ds else false
```

**CONNECT port leading zeros counted as digits** in `Http/Framing.lean`:

```
-   let ds := ds.dropWhile (· == 0x30)
- 
+ 
```

**CONNECT method compared case-insensitively** in `Http/Framing.lean`:

```
-   h.method != connectName ||
+   h.method.map lower != connectName.map lower ||
```

**CONNECT target form unchecked** in `Http/Framing.lean`:

```
-     (Grammar.connectTarget.isMatch h.target && portInRange
+     (portInRange
```

**CONNECT target may have an empty host** in `Http/Grammar.lean`:

```
- def connectTarget : Re := seq [hostNonEmpty, litCI ":", port]
+ def connectTarget : Re := seq [uriHost, litCI ":", port]
```

**empty host allowed in an authority-form target** in `Http/Framing.lean`:

```
- h.target.head? == some 0x3A || 
+ 
```

**CONNECT content accepted** in `Http/Framing.lean`:

```
-  || (h.method == connectName && fr != .length 0)
+ 
```

**CONNECT with Content-Length accepted** in `Http/Framing.lean`:

```
- (h.method == connectName && fr != .length 0)
+ (h.method == connectName && fr == .chunked)
```

**CONNECT content rule in any case of the method** in `Http/Framing.lean`:

```
- (h.method == connectName && fr != .length 0)
+ (h.method.map lower == connectName.map lower && fr != .length 0)
```

**empty host allowed in a Host value** in `Http/Grammar.lean`:

```
- def hostField : Re := opt (cat hostNonEmpty (opt (cat (litCI ":") port)))
+ def hostField : Re := opt (cat host (opt (cat (litCI ":") port)))
```

**CONNECT port read from every digit** in `Http/Framing.lean`:

```
- def portOf (t : List UInt8) : List UInt8 := (t.reverse.takeWhile isDigit).reverse
+ def portOf (t : List UInt8) : List UInt8 := t.filter isDigit
```

**http target rule removed** in `Http/Framing.lean`:

```
-  || !h.httpTargetOK
+ 
```

**userinfo allowed in an http target** in `Http/Grammar.lean`:

```
- litCI "://", hostNonEmpty,
+ litCI "://", opt (cat userinfo (litCI "@")), hostNonEmpty,
```

**empty host allowed in an http target (reg-name star)** in `Http/Grammar.lean`:

```
- plus (any [unreserved, pctEncoded, subDelims])
+ star (any [unreserved, pctEncoded, subDelims])
```

**scheme compared case-sensitively in the http target grammar** in `Http/Grammar.lean`:

```
- alt (litCI "http") (litCI "https")
+ alt (lit "http") (lit "https")
```

**scheme compared case-sensitively in the http and https prefix test** in `Http/Framing.lean`:

```
- !(httpColon.isPrefixOf (h.target.map lower) || httpsColon.isPrefixOf (h.target.map lower))
+ !(httpColon.isPrefixOf h.target || httpsColon.isPrefixOf h.target)
```

**CONNECT not exempt from the http target rule** in `Http/Framing.lean`:

```
-   h.method == connectName ||
-     !(
+   !(
```

**CONNECT exempt from the http target rule in any case** in `Http/Framing.lean`:

```
-   h.method == connectName ||
+   h.method.map lower == connectName.map lower ||
```

**https targets not checked** in `Http/Framing.lean`:

```
-  || httpsColon.isPrefixOf (h.target.map lower)
+ 
```

**a percent escape's second digit unchecked** in `Http/Grammar.lean`:

```
- def pctEncoded : Re := seq [litCI "%", HEXDIG, HEXDIG]
+ def pctEncoded : Re := seq [litCI "%", HEXDIG, range 0x30 0x7A]
```

**256 as an IPv4 octet** in `Http/Grammar.lean`:

```
- cat (litCI "25") (range 0x30 0x35)]
+ cat (litCI "25") (range 0x30 0x36)]
```

**dec-octet 25 then any digit** in `Http/Grammar.lean`:

```
- cat (litCI "25") (range 0x30 0x35)]
+ cat (litCI "25") (range 0x30 0x39)]
```

**dec-octet 2 then any two digits** in `Http/Grammar.lean`:

```
- seq [litCI "2", range 0x30 0x34, DIGIT]
+ seq [litCI "2", range 0x30 0x39, DIGIT]
```

**dec-octet with a leading zero** in `Http/Grammar.lean`:

```
- cat (range 0x31 0x39) DIGIT
+ cat DIGIT DIGIT
```

**dec-octet as 1*3DIGIT** in `Http/Grammar.lean`:

```
- def decOctet : Re :=
-   any [DIGIT, cat (range 0x31 0x39) DIGIT, cat (litCI "1") (rep 2 DIGIT),
-     seq [litCI "2", range 0x30 0x34, DIGIT], cat (litCI "25") (range 0x30 0x35)]
+ def decOctet : Re := between 1 3 DIGIT
```

**IP literal with a zone ID** in `Http/Grammar.lean`:

```
- def IPliteral : Re := seq [litCI "[", alt IPv6address IPvFuture, litCI "]"]
+ def IPliteral : Re := seq [litCI "[", any [IPv6address, seq [IPv6address, litCI "%25", plus (alt unreserved pctEncoded)], IPvFuture], litCI "]"]
```

**host may be a bare IPv6 address** in `Http/Grammar.lean`:

```
- def host : Re := any [IPliteral, IPv4address, regName]
+ def host : Re := any [IPliteral, IPv6address, IPv4address, regName]
```

**IPvFuture v case-sensitive** in `Http/Grammar.lean`:

```
- seq [litCI "v", plus HEXDIG
+ seq [byte 0x76, plus HEXDIG
```
