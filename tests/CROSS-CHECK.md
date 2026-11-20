# Cross-check with other HTTP parsers

Written by `tests/cross_check.py`, a one-off comparison that is not part of the verified bar. Its docstring says how the heads are sent and judged, and how a difference gets its category. RFC 9112 lets a recipient repair some malformed heads instead of rejecting them, so a difference here is a different choice, not always an error.

- Heads: the first 5991 inputs of the differential tests (seed 20261025, `--count 6000`, less the malformed requests to the tool). Every parser is sent all 5991. A head whose verdicts differ is also sent again with features changed, to find its category.
- This project rejects 4195 of them. It accepts 1083 with no body, 481 with a Content-Length from 1 to 1,000,000, 223 as chunked, and 9 with a Content-Length above 1,000,000.
- Sent after the head: nothing after a head this project rejects; the whole body for a Content-Length up to 1,000,000; `5\r\nhello\r\n0\r\n\r\n` (5 octets of data) for chunked; nothing for a Content-Length above 1,000,000, so those heads are judged on the head alone.
- A parser accepts a head when it reads it and passes the request on, even when it then waits for a body that is never sent.
- In the tables, "accepts" means the other parser accepts a head this project rejects, and "rejects" means it rejects a head this project accepts. The examples show the head as sent, cut at 100 octets.
- Categories: for a head the other parser accepts, the first reason this project rejects it. For a head the other parser rejects, the first feature whose change alone makes that parser accept it, or, after "together:", the features whose changes it needs at once. The script checks that it finds a reason to reject in each head this project rejects and in no other, and that each change keeps a head this project accepts.

## Node v22.23.4 (llhttp)

- Heads sent: 5991
- Same verdict: 4422 (920 both accept, 3502 both reject)
- Different verdict: 1563 (687 it accepts and this project rejects, 876 it rejects and this project accepts)
- No answer: 6
- Body lengths compared, where both accept: 875. Of those, 581 have no body and 294 a non-zero length (261 by Content-Length, 33 chunked). 875 read the same length and 0 another.
- Not compared, where both accept: 0 with a Content-Length above 1,000,000, and 45 whose answer has no count.

The heads it rejects and this project accepts, by the feature whose change makes it accept them: alone, or together with other changes.

| Feature | Alone | With others |
| --- | --- | --- |
| a method other than the registered ones | 225 | 138 |
| the authority-form with a method other than CONNECT | 122 | 76 |
| an absolute-form target with no authority | 123 | 61 |
| HTTP/1.2 to 1.9 | 93 | 80 |
| a Transfer-Encoding list with empty elements | 62 | 69 |
| a tab after a Content-Length or Transfer-Encoding value | 15 | 12 |
| a scheme with a digit, "+", "-" or "." | 21 | 5 |
| a Content-Length of 2^63 or more | 6 | 3 |

Where it differs from this project (the two shortest examples):

| It | Category | Heads | Examples |
| --- | --- | --- | --- |
| rejects | a method other than the registered ones | 225 | `b'Connect / HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'IyUqp * HTTP/1.1\r\nhOsT:  [::]:80 \r\n\r\n'` |
| accepts | a major version other than 1 | 130 | `b'GET / HTTP/2.0\r\nHost: a\r\n\r\n'`, `b'DELETE * HTTP/2.0\r\nhost::80 \r\n\r\n'` |
| accepts | a Host value with a bad IP literal | 129 | `b'GET / HTTP/1.1\r\nHost: ::1\r\n\r\n'`, `b'GET / HTTP/1.1\r\nHost: [v.a]\r\n\r\n'` |
| rejects | an absolute-form target with no authority | 123 | `b'GET a:80 HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'GET htt:a HTTP/1.1\r\nHost: a\r\n\r\n'` |
| rejects | the authority-form with a method other than CONNECT | 122 | `b'POST 200.9.99.250:443 HTTP/1.1\r\nHOST:  \t\r\n\r\n'`, `b'OPTIONS [::]:0 HTTP/1.1\r\neqg:  \r\nhOsT:  ~x \r\n\r\n'` |
| rejects | HTTP/1.2 to 1.9 | 93 | `b'GET / HTTP/1.2\r\nHost: a\r\n\r\n'`, `b'HEAD /RUXBl HTTP/1.2\r\nhost: [::]:80  \r\n\r\n'` |
| accepts | two Host lines | 70 | `b'GET / HTTP/1.0\r\nHost: a\r\nHost: b\r\n\r\n'`, `b'GET / HTTP/1.1\r\nHost: a\r\nHost: a\r\n\r\n'` |
| rejects | a Transfer-Encoding list with empty elements | 62 | `b'POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked,\r\n\r\n'`, `b'POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: ,chunked,\r\n\r\n'` |
| accepts | a Host value with an empty host, such as `:80` | 53 | `b'GET / HTTP/1.1\r\nHost: :\r\n\r\n'`, `b'GET / HTTP/1.1\r\nHost: :80\r\n\r\n'` |
| rejects | together: a method other than the registered ones; an absolute-form target with no authority | 39 | `b'connect a: HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'\r\n\r\n6 http.s:PhwcQ HTTP/1.0\r\nHost:  [::]:65535  \r\n\r\n'` |
| accepts | CONNECT whose target is not a host and port | 34 | `b'CONNECT * HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'CONNECT / HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | another Host value outside RFC 3986 | 34 | `b'GET / HTTP/1.1\r\nHost: a b\r\n\r\n'`, `b'DELETE /)Uym HTTP/1.1\r\nhost:\tx? \r\n\r\n'` |
| rejects | together: the authority-form with a method other than CONNECT; a method other than the registered ones | 34 | `b'MRoJ%2 P%Cf:443 HTTP/1.1\r\nhOsT:\tx.fZwWC \r\n\r\n'`, `b'ybK54 %7bR2B.~KsMn:8080 HTTP/1.0\r\nhost:255.249.200.99  \r\n\r\n'` |
| accepts | CONNECT with a port above 65535 | 32 | `b'CONNECT ZVPta$%bf:99999 HTTP/1.1\r\n\r\n'`, `b'CONNECT a:65536 HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | an http or https target with userinfo | 25 | `b'GET http://@a/ HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'GET http://u@/ HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | an http or https target with no host | 24 | `b'GET http:// HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'GET https:// HTTP/1.1\r\nHost: a\r\n\r\n'` |
| rejects | together: HTTP/1.2 to 1.9; a method other than the registered ones | 22 | `b'AY0.6C * HTTP/1.9\r\nhOsT: ptF_$dy: \r\n\r\n'`, `b'L#GWP#i9 * HTTP/1.9\r\nhOsT:Xn \r\nEZ9_:,)1"h0H$` \r\n\r\n'` |
| rejects | a scheme with a digit, "+", "-" or "." | 21 | `b'TRACE a+b.c-d://JpR-c%d6:95702 HTTP/1.1\r\nhOsT:A!0(r2.n) \r\n\r\n'`, `b'\r\n\r\nPOST https+x://%3Fbx@/tdT@=v/R9g%89t)?pQXsKH;M HTTP/1.1\r\nhOsT:\t!GJT.U.*.V\t\r\n\r\n'` |
| accepts | CONNECT with content | 19 | `b'CONNECT a:443 HTTP/1.1\r\nHost: a\r\nContent-Length: 5\r\n\r\n'`, `b'CONNECT a:443 HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n'` |
| accepts | CONNECT with an empty host | 18 | `b'CONNECT :443 HTTP/1.0\r\n\r\n'`, `b'CONNECT : HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | Transfer-Encoding in HTTP/1.0 | 18 | `b'POST /a HTTP/1.0\r\nTransfer-Encoding: chunked\r\n\r\n'`, `b'OPTIONS /S1/@ HTTP/1.0\r\nm+PTgQe:_ \t\t\xbfwK  \r\nHost:[::D5a:ed32] \r\nTRANSFER-ENCODING: gzip, chunked \r\n\r\n'` |
| rejects | together: a method other than the registered ones; a Transfer-Encoding list with empty elements | 18 | `b'OZxN!T. * HTTP/1.1\r\nHOST:10.255.255.1\r\n7S: h zQo:!Je \r\nTransfer-Encoding: \t CHUNKED ,\r\n*2u3: \tZw \t \r'`, `b'\r\n\r\nj /=nLs@/%47?Fu HTTP/1.1\r\nHost:[vFA.v&nb]\r\ntransfer-encoding:\t ,   ,\t \t ,  ChUNKed ,  \t ,  \r\nsW:'` |
| rejects | together: HTTP/1.2 to 1.9; a Transfer-Encoding list with empty elements | 17 | `b"OPTIONS /U?XPY HTTP/1.9\r\nko3R69KF:  \x88Y'f\t@$\r\nHost:\t[D02d:C4:F:A:fe58:a7:8:e30]\t\r\nTransfer-Encoding:,"`, `b"GET /'~XD/:P?9nh1s/+o HTTP/1.9\r\nTRANSFER-ENCODING: Chunked \r\nTransfer-Encoding: ,\t\r\nHOST:  199.9.249"` |
| accepts | a target with a bad IP literal | 16 | `b'GET http://[v1.]/ HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'GET http://[1::2::3]/ HTTP/1.1\r\nHost: x\r\n\r\n'` |
| accepts | other whitespace in the request line | 16 | `b'GET  /a HTTP/1.1\r\nHost: x\r\n\r\n'`, `b'PATCH  * HTTP/1.1\r\nHost:   \r\no8s:  \xa9\r\n\r\n'` |
| rejects | a tab after a Content-Length or Transfer-Encoding value | 15 | `b'PUT /n HTTP/1.1\r\nhost: %DCT%Ee7tj-.GL:80  \r\nTransfer-Encoding:\tCHUNKED\t\r\n\r\n'`, `b'TRACE /!:wEp) HTTP/1.1\r\nTransfer-Encoding:\tchunked \t \r\n*`:  P\t-GW:I\t\xe0K\tyO:\r\nHost: %26c%cDJ*$_s:8080\t'` |
| rejects | together: the authority-form with a method other than CONNECT; a Transfer-Encoding list with empty elements | 14 | `b'POST DW~g:443 HTTP/1.1\r\nTRANSFER-ENCODING:\tchunked,\t\r\nhOsT:\t[7::A3A5:0:Ae5]\t\r\n\r\n'`, `b'GET JOg.Nt%BBysUBr.d5T:443 HTTP/1.1\r\ntransfer-encoding:  chunked , , \r\nhost:5.I.Yc%CA&d: \r\nSOsR: l~b'` |
| accepts | a bare LF | 11 | `b'\n\r\nGET / HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'\n\r\nDELETE /R@M HTTP/1.1\r\nhOsT:\t:80 \t \r\n\r\n'` |
| rejects | together: HTTP/1.2 to 1.9; an absolute-form target with no authority | 11 | `b'\r\n\r\nDELETE HTTPX:*%3d=67 HTTP/1.9\r\nHost: \t [0d:BBf5::Da:a7:b3F7]\t\r\n\r\n'`, `b'PATCH https+x: HTTP/1.9\r\nQq2mBD*2:\t \t \r\njuf.:  $mu!\xb7Xn \xc5A\xfb7d \r\nO: \t ^\t\r\nHost: qVt-l:443\t\r\n\r\n'` |
| rejects | together: HTTP/1.2 to 1.9; the authority-form with a method other than CONNECT | 11 | `b"POST [9:ABA:DB::C79:Aa55:f3Ea:2]:8080 HTTP/1.2\r\nHost: %91.qw'zr~:443 \t \r\n\r\n"`, `b'GET 0.250.99.213:0 HTTP/1.2\r\nHOST: 6oeD.2UR%7DbLh7 \r\nContent-Length: 5  \r\n\r\n'` |
| accepts | CONNECT with an empty port | 10 | `b'CONNECT a: HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'CONNECT http: HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | a target with a bad percent escape | 9 | `b'GET /%4g HTTP/1.1\r\nHost: x\r\n\r\n'`, `b'GET /%zz HTTP/1.1\r\nHost: x\r\n\r\n'` |
| accepts | a bare CR | 6 | `b'\r\r\nHEAD / HTTP/1.1\r\nContent-Length: \t 996606  \r\nhOsT: \t :80 \r\n\r\n'`, `b"\rCONNECT /i%f7%7cGy%78/j*QCyl//1S; HTTP/1.1\r\n'5:]!<S1{PE_\t/JD9x \t.I \r\nHOST:\t: \r\nHOST:[VA.uIx2]\r\n\r\n"` |
| accepts | another target outside RFC 3986 | 6 | `b'GET /a#frag HTTP/1.1\r\nHost: x\r\n\r\n'`, `b'CONNECT ::1:80 HTTP/1.1\r\nHost: a\r\n\r\n'` |
| rejects | a Content-Length of 2^63 or more | 6 | `b'DELETE /W,/D8gX@/?B/ HTTP/1.0\r\nhOsT:L.XM\r\nCONTENT-LENGTH: 18446744073709551616  \r\n\r\n'`, `b'PATCH /Vn/Al@/*:%DF:/XPb HTTP/1.1\r\n-:  caD~$\t\xf1{fm\xbf\r\ncontent-length:18446744073709551616 \t \r\nhost:  2'` |
| rejects | together: the authority-form with a method other than CONNECT; a method other than the registered ones; a Transfer-Encoding list with empty elements | 6 | `b'9H 9.99.0.210:80 HTTP/1.1\r\nTRANSFER-ENCODING:  ,  ,  ChunKed \t \r\nIb9e: qQrrk\t\r\nHOST: [B::6FDD:e80b] '`, `b"lWl%c ;y.T:65535 HTTP/1.1\r\ntransfer-encoding: \t, \t \r\ntransfer-encoding: chunked\r\nhost: x&.'RGKJ1 \r\nt"` |
| accepts | a Transfer-Encoding with another coding before chunked | 5 | `b'POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: gzip, chunked\r\n\r\n'`, `b'CONNECT 5%3CsOppl.Yetm%eDk.!%84F)3K:30136 HTTP/1.1\r\nHOST:  rNRE:0\r\nTRANSFER-ENCODING:x\t,\tchunked\t\r\n\r'` |
| accepts | chunked twice | 5 | `b'\r\n\r\nPUT * HTTP/1.1\r\nhost: cFA7:::80\r\nhost: cFA7:::80\r\nTRANSFER-ENCODING: \t ,   ,\t  , chunked\t,, chun'`, `b'PATCH /OzXHrs/@H@ju(/LG%C6Io:/?dLXy%94*fl HTTP/1.1\r\nHost: o)%99v\t\r\noe:2[ kw ~(,}o[^R\t4 \t \r\nTRANSFER-'` |
| rejects | together: HTTP/1.2 to 1.9; the authority-form with a method other than CONNECT; a method other than the registered ones | 5 | `b'XY6N u%F22eY.kK%dDlc%47:65535 HTTP/1.9\r\nO~7ue: \t\r\n8`t\|m.*: \\\t7\tG3/\xeaI \tO?\xc8[)  \r\nHost:\t[V8.z0] \t \r\n\r\n'`, `b'5a3x-oKN [VE.A]:8080 HTTP/1.2\r\ntransfer-encoding:  , chunked  \r\n+b: N \x990~ \xb1\xe2W`7$\r\nhOsT:\t0.9.0.250:80'` |
| rejects | together: a method other than the registered ones; a tab after a Content-Length or Transfer-Encoding value | 5 | `b"02jWd% /,g/ HTTP/1.1\r\nHOST: %AC~m&p2.Y- \r\nv':\t \r\nspapSWcr: \xc33\xa9\x83 \t \r\nTransfer-Encoding: chunked \t \r\n\r"`, `b'qe^M0^V /DM_%CFX// HTTP/1.1\r\nTransfer-Encoding: chunked \t \r\nHost:  200.10.255.250  \r\nR:\tJc8qY\xaa\| \r\n0:'` |
| accepts | CONNECT with port 0 | 4 | `b'CONNECT a:0 HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'CONNECT a:00 HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | a Transfer-Encoding with another coding before chunked, over two or more lines | 3 | `b'POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: gzip\r\nTransfer-Encoding: chunked\r\n\r\n'`, `b'\r\nPUT //y,$?l/z3? HTTP/1.1\r\nhost: 0.1.250.249 \r\ntransfer-encoding:\tchunk \r\nTransfer-Encoding:\tchunke'` |
| accepts | a request line that is not three parts | 3 | `b'GET /lH@EYF?)$ExHTTP/1.0\r\nHost: ZVR58k%F7.)0i_Hc.G!$!Aqm\t\r\n\r\n'`, `b'HEAD Http://200.250.99.99//n/)wXA.T/9lk!HTTP/1.1\r\nY6h: \t   \r\nUH9!Qj:*GG$O\t*;&_\t\t-5 \r\n\r\n'` |
| accepts | no Host, in HTTP/1.1 to 1.9 | 3 | `b"CONNECT mNY.x7%e7hXt+.Y:000000000063466 HTTP/1.1\r\nH0W'`: S\t/p\r\nE0kO: Wi@ZN:u\xfe \r\n\r\n"`, `b'CONNECT ~7g;3%8Eqs.8T0i.-zWt%FA:1 HTTP/1.1\r\n4.W.:\tvO; \r\nn~k90: \t \t> #\|u\xf8  \r\nOsT:jZBoysD.s%5B_QmW3.Tb'` |
| no answer | empty lines before the request line | 3 | `b'\r\n'` |
| rejects | together: an absolute-form target with no authority; a Transfer-Encoding list with empty elements | 3 | `b'PUT a+b.c-d: HTTP/1.1\r\nHost: Z%0B,LFSe,  \r\nTransfer-Encoding:  chunkeD\t,  \r\n\r\n'`, `b'DELETE HTTPX:?%F9e4%Ea:k HTTP/1.1\r\nhost:  249.255.100.99 \t \r\nTRANSFER-ENCODING:  , \t  ,  ChunkEd ,  '` |
| no answer | a bare CR | 2 | `b'\r'`, `b'\r\n\r'` |
| rejects | together: HTTP/1.2 to 1.9; a method other than the registered ones; a Transfer-Encoding list with empty elements | 2 | `b's0i //:SqNz HTTP/1.9\r\nD*: \t ,PB\t\trE\x80mp!\xe8p7u \r\ntransfer-encoding: CHUNKED ,  \r\neal9S*6:  \xecL1{VL8< \t \r'`, `b'\r\n\r\n1It.!%.N ///V1c HTTP/1.9\r\nTransfer-Encoding: \r\nHOST: yKZcsc.y_o*vp.4N2E%4a%25 \r\nTRANSFER-ENCODIN'` |
| rejects | together: HTTP/1.2 to 1.9; a scheme with a digit, "+", "-" or "."; a Transfer-Encoding list with empty elements | 2 | `b"GET a+b.c-d://o'ZHM%4Dz.,_u HTTP/1.9\r\nm8H: P# \r\nTRANSFER-ENCODING: \t ,\t \t , \t  ,CHunked \t ,\t, , \r\nHO"`, `b'OPTIONS a+b.c-d://[BB:fB:b9B:45DE:fB1b:BB:61e3:af]:443/)RS/xTf5q/f HTTP/1.9\r\nWfCF.t: g[\xa6h\xf5S3%2q$0y\r\n'` |
| rejects | together: HTTP/1.2 to 1.9; a tab after a Content-Length or Transfer-Encoding value | 2 | `b"\r\n\r\nOPTIONS /A28) HTTP/1.2\r\nTRANSFER-ENCODING: CHUNKED\t\r\n7JsW: /v}% \r\nCB'^LNQ-:  r=vd \r\nhost:  [1dF:"`, `b'TRACE /Pg HTTP/1.2\r\nLANYr7V:  27<w1a=\xc7LE?\\ I`Sqs\t^\t\r\nw:  u\t\\r\xefov3 \t \r\nT3kESlGR: i\xef}H3+9296Jw4"n; YL '` |
| rejects | together: HTTP/1.2 to 1.9; the authority-form with a method other than CONNECT; a Transfer-Encoding list with empty elements | 2 | `b'\r\n\r\nGET 253.100.99.99:8080 HTTP/1.9\r\ntransfer-encoding: chunked\t,  \r\nHOST:\t[::8:d5:8] \r\n%q:  Ns;\t=NL'`, `b'TRACE R3J.%5A%9Co*S.ws6JR:80 HTTP/1.2\r\nhOsT:  9.250.200.249  \r\ntransfer-encoding:\tChunked \r\nTransfer'` |
| rejects | together: a method other than the registered ones; an absolute-form target with no authority; a Transfer-Encoding list with empty elements | 2 | `b'p66mb http.s: HTTP/1.1\r\nYqe: +<<\xb2\t\xfdWl0QB5 \r\nn57va%p: \t \xcf1a\xdesJ\tQ\t \t \r\nhOsT:[D::]\t\r\nTransfer-Encoding:'`, `b'connect x:443 HTTP/1.1\r\ntransfer-encoding: chunked,  \r\nXvV.s:  \xd1Y\xfdDEEN(8`): \t \r\nHost: [03aC:b5:B44e:'` |
| rejects | together: an absolute-form target with no authority; a tab after a Content-Length or Transfer-Encoding value | 2 | `b'\r\n\r\nOPTIONS https+x:r HTTP/1.1\r\nxO:\t)"{\r\nc&^kZUud:  {nj \r\nSP:YSl  \r\nhost: %88v%E9.uC.OR%41j!=.\t\r\nTRA'`, `b"HEAD ws: HTTP/1.1\r\nXWpL3lb2: D_<:\\ wdtnP }ru, \r\nEDIS8i: pZMl\tw7 \t \r\njhZfF: /iMjB`p#k_ \t \r\nHost:\tYR'O"` |
| accepts | a Transfer-Encoding whose last coding is not chunked | 1 | `b'CONNECT [vE.Q)]:00000000000000000000032110 HTTP/1.1\r\ntransfer-encoding: chunked chunked \r\no: \t \r\nemy'` |
| accepts | a Transfer-Encoding with no coding | 1 | `b'CONNECT a:443 HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: ,\r\n\r\n'` |
| accepts | a Transfer-Encoding with no coding, over two or more lines | 1 | `b"CONNECT 'V.kAIkT.l:000000019020 HTTP/1.1\r\nhost:\t:: \r\nuCl'mwR: B8/5\xc7  \r\nTRANSFER-ENCODING:\t,  \r\nG~4c:"` |
| accepts | chunked twice, over two or more lines | 1 | `b"PATCH /nvr?~ HTTP/1.1\r\nTRANSFER-ENCODING:  CHUNKED \t \r\n0'4!.CS-:   DtNe[FE,\xe3Ie  \r\n8ivVoE:\t;3\|\xc6O^}\\\x96k"` |
| no answer | a request line that is not three parts | 1 | `b''` |
| rejects | together: HTTP/1.2 to 1.9; a method other than the registered ones; a scheme with a digit, "+", "-" or "." | 1 | `b'NFV2lN http.s://G7lhG.bIyy.qo%Fbz-ZE/RyZN/AfQv?w HTTP/1.2\r\nygl:UOw\\ B\xaa \t \r\nu3J: /n]\xc4P\t\xfe*\r\nhost: m&cD'` |
| rejects | together: HTTP/1.2 to 1.9; a method other than the registered ones; an absolute-form target with no authority | 1 | `b'\|tjBInEA x:RL HTTP/1.2\r\nDDP`SEU4: \t tw\xc4o0\tZ6{XaW8\x8d\r\nhOsT: H,:80 \t \r\n^AQXuS2: \t\r\n\r\n'` |
| rejects | together: HTTP/1.2 to 1.9; a scheme with a digit, "+", "-" or "." | 1 | `b'GET http.s://[::]:0/Yu0cR HTTP/1.9\r\nVK4j:\t<<\xc0\xd9 \r\n*8x2j%I:\t\x8c;9\xfavZk\x9c9pYi\xba b3F5W  \r\nhOsT:Bq.Xo3 \t \r\n\r\n'` |
| rejects | together: HTTP/1.2 to 1.9; an absolute-form target with no authority; a Transfer-Encoding list with empty elements | 1 | `b'DELETE x:~cCa HTTP/1.2\r\nhOsT:\ta~3a-g.p8.RS3W:94211  \r\nTRANSFER-ENCODING: \t  , chUNked\t\r\nulA~DkT:  io'` |
| rejects | together: HTTP/1.2 to 1.9; an absolute-form target with no authority; a tab after a Content-Length or Transfer-Encoding value | 1 | `b"HEAD http.s:?%BDns.,%Fc HTTP/1.2\r\nY'V!!w^:\t+\xdbNH$<CMK q5\x86Vu6F<\\r \r\nTBiou^k:\te)\x9cf\xc1\t\r\nHOST: \t \t\r\nTRANSF"` |
| rejects | together: HTTP/1.2 to 1.9; the authority-form with a method other than CONNECT; a method other than the registered ones; a Transfer-Encoding list with empty elements | 1 | `b'\r\nConnect -Qn.3.%97:40608 HTTP/1.9\r\nKR7g: \t  \r\nTransfer-Encoding:,chunked, \r\nFi:  f \x84cjXa  \r\nhOsT: \t'` |
| rejects | together: a method other than the registered ones; a Content-Length of 2^63 or more | 1 | `b'PfqO6 /F,\')/kD4/kpDo%02U?lqzKa HTTP/1.1\r\nuLD8:\tb0Fe"\xa5  \r\nHost: 71.1.250.199  \r\n547Gp:     \r\nContent-'` |
| rejects | together: a scheme with a digit, "+", "-" or "."; a Transfer-Encoding list with empty elements | 1 | `b"POST a+b.c-d://S'p%F5%9C/1%da@3.M/:ol?H=J7Q HTTP/1.1\r\n03`LBSYF:\t[u%`L[#\x8er[[* !jQ \r\npopQ0I:\tr?0 lj P\xf5"` |
| rejects | together: an absolute-form target with no authority; a Content-Length of 2^63 or more | 1 | `b"OPTIONS httpx: HTTP/1.1\r\nContent-Length:18446744073709551616 \r\nHost: \t _u9mc'5.lKf%99vt.U%EA;Q \t \r\n\r"` |
| rejects | together: the authority-form with a method other than CONNECT; a Content-Length of 2^63 or more | 1 | `b'\r\nPOST ;%AC(esd.I-hm.XF%B7E%E7:443 HTTP/1.1\r\nContent-Length: 18446744073709551616\t\r\nhost:iU&f)sz  \r\n'` |
| rejects | together: the authority-form with a method other than CONNECT; a method other than the registered ones; a tab after a Content-Length or Transfer-Encoding value | 1 | `b'5tp j!N:65535 HTTP/1.1\r\n\|7:\t\x96\xb5\t\tp~Ak#`mHXF\t5mg\r\nTransfer-Encoding:  chunked\t\r\nhOsT: \t 6kG(3\r\nuFwH^K_'` |
| rejects | together: the authority-form with a method other than CONNECT; a tab after a Content-Length or Transfer-Encoding value | 1 | `b'POST [::8]:8080 HTTP/1.1\r\nXKS#QC: \xa4vMh\t\r\nkoB-: :@\ttaPwS\xcb,8f\x99S5-bj \r\nHOST: \t [7BC9:d5e:7:Eb:F:D:e4F:E'` |

## Go go1.22.2 net/http

- Heads sent: 5991
- Same verdict: 4714 (1172 both accept, 3542 both reject)
- Different verdict: 1276 (652 it accepts and this project rejects, 624 it rejects and this project accepts)
- No answer: 1
- Body lengths compared, where both accept: 1172. Of those, 803 have no body and 369 a non-zero length (321 by Content-Length, 48 chunked). 1172 read the same length and 0 another.
- Not compared, where both accept: 0 with a Content-Length above 1,000,000, and 0 whose answer has no count.

The heads it rejects and this project accepts, by the feature whose change makes it accept them: alone, or together with other changes.

| Feature | Alone | With others |
| --- | --- | --- |
| empty lines before the request line | 268 | 60 |
| the authority-form with a method other than CONNECT | 139 | 59 |
| a Transfer-Encoding list with empty elements | 105 | 49 |
| a percent escape of an ASCII octet in the host of the target | 18 | 9 |
| a Content-Length of 2^63 or more | 7 | 2 |

Where it differs from this project (the two shortest examples):

| It | Category | Heads | Examples |
| --- | --- | --- | --- |
| rejects | empty lines before the request line | 268 | `b'\r\n\r\nGET / HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'\r\n\r\nPUT x: HTTP/1.1\r\nHost: eu-F\r\n\r\n'` |
| accepts | a Host value with a bad IP literal | 161 | `b'GET / HTTP/1.1\r\nHost: ::1\r\n\r\n'`, `b'GET / HTTP/1.1\r\nHost: [v.a]\r\n\r\n'` |
| rejects | the authority-form with a method other than CONNECT | 139 | `b'MRoJ%2 P%Cf:443 HTTP/1.1\r\nhOsT:\tx.fZwWC \r\n\r\n'`, `b'POST 200.9.99.250:443 HTTP/1.1\r\nHOST:  \t\r\n\r\n'` |
| rejects | a Transfer-Encoding list with empty elements | 105 | `b'POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked,\r\n\r\n'`, `b'POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: , chunked\r\n\r\n'` |
| accepts | Transfer-Encoding in HTTP/1.0 | 90 | `b'POST /a HTTP/1.0\r\nTransfer-Encoding: chunked\r\n\r\n'`, `b'POST /a HTTP/1.0\r\nTransfer-Encoding: chunked,\r\n\r\n'` |
| accepts | a Host value with an empty host, such as `:80` | 69 | `b'GET / HTTP/1.1\r\nHost: :\r\n\r\n'`, `b'GET / HTTP/1.1\r\nHost: :80\r\n\r\n'` |
| accepts | an http or https target with no host | 65 | `b'GET http: HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'GET HTTP:/ HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | a bare LF | 49 | `b'PATCH https:@tR HTTP/1.1\nhOsT:  C.+cH:8080 \r\n\r\n'`, `b'POST /a HTTP/1.1\r\nHost: x\nTransfer-Encoding: chunked\r\n\r\n'` |
| accepts | a folded line (obs-fold) | 36 | `b'CONNECT xbrA:1 HTTP/1.1\r\nHOST: \t \t\r\n\tfolded\r\n\r\n'`, `b'POST /a HTTP/1.1\r\nHost: x\r\nX: y\r\n Transfer-Encoding: chunked\r\n\r\n'` |
| rejects | together: empty lines before the request line; the authority-form with a method other than CONNECT | 31 | `b'\r\n\r\nOPTIONS [9::3]: HTTP/1.0\r\nppWKAY:m\xb0vU4\r\nHost:  pYMaB.E)2(rp)w\r\n\r\n'`, `b'\r\nko2_ [24C7::5Cd5:5:F7:8DC9:e]: HTTP/1.1\r\nHOST: \t 249.100.10.255 \r\n\r\n'` |
| accepts | an http or https target with userinfo | 28 | `b'GET http://@a/ HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'GET http://u@/ HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | CONNECT with a port above 65535 | 24 | `b'CONNECT ZVPta$%bf:99999 HTTP/1.1\r\n\r\n'`, `b'CONNECT a:65536 HTTP/1.1\r\nHost: a\r\n\r\n'` |
| rejects | together: the authority-form with a method other than CONNECT; a Transfer-Encoding list with empty elements | 24 | `b'POST DW~g:443 HTTP/1.1\r\nTRANSFER-ENCODING:\tchunked,\t\r\nhOsT:\t[7::A3A5:0:Ae5]\t\r\n\r\n'`, `b'HEAD 9Xh!.TI~J6.~eoG4n%B8a:65535 HTTP/1.1\r\nhOsT:\tQ.lO1ua4* \r\nTransfer-Encoding:   , \t chUnked\r\n\r\n'` |
| accepts | CONNECT whose target is not a host and port | 23 | `b'CONNECT * HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'CONNECT / HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | Transfer-Encoding with Content-Length | 21 | `b'POST /a HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nTransfer-Encoding: chunked\r\n\r\n'`, `b'POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nContent-Length: 5\r\n\r\n'` |
| accepts | a target with a bad IP literal | 19 | `b'GET http://[v1.]/ HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'GET http://[1::2::3]/ HTTP/1.1\r\nHost: x\r\n\r\n'` |
| rejects | a percent escape of an ASCII octet in the host of the target | 18 | `b'GET http://%41%42/ HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'PUT htTpS://H.%28%EB%9cq HTTP/1.0\r\nHost:GA.I%14mUmi \r\n\r\n'` |
| rejects | together: empty lines before the request line; a Transfer-Encoding list with empty elements | 18 | `b'\r\n\r\nj /=nLs@/%47?Fu HTTP/1.1\r\nHost:[vFA.v&nb]\r\ntransfer-encoding:\t ,   ,\t \t ,  ChUNKed ,  \t ,  \r\nsW:'`, `b"\r\nTRACE /gp?i HTTP/1.1\r\n^3zo+sZ:\t \r\nhOsT: \t '9FV%48o.7*u%A2y \t \r\ntransfer-encoding:  \t ,  ,  , chunk"` |
| accepts | CONNECT with content | 16 | `b'CONNECT a:443 HTTP/1.1\r\nHost: a\r\nContent-Length: 5\r\n\r\n'`, `b'CONNECT a:443 HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n'` |
| accepts | another Host value outside RFC 3986 | 13 | `b'TRACE / HTTP/1.1\r\ny^%6: \t TsP\tPa\tOFC)\t\r\nhOsT:  h:p \r\n\r\n'`, `b'TRACE /Hx.&tP/F:p/%C1pe?2ONf:Zp HTTP/1.0\r\nDF:\t"~ qd\t\r\nHOST: \t h:p\r\n\r\n'` |
| accepts | CONNECT with an empty host | 12 | `b'CONNECT :443 HTTP/1.0\r\n\r\n'`, `b'CONNECT : HTTP/1.1\r\nHost: a\r\n\r\n'` |
| rejects | a Content-Length of 2^63 or more | 7 | `b'DELETE /W,/D8gX@/?B/ HTTP/1.0\r\nhOsT:L.XM\r\nCONTENT-LENGTH: 18446744073709551616  \r\n\r\n'`, `b"OPTIONS httpx: HTTP/1.1\r\nContent-Length:18446744073709551616 \r\nHost: \t _u9mc'5.lKf%99vt.U%EA;Q \t \r\n\r"` |
| accepts | another target outside RFC 3986 | 6 | `b'GET /a#frag HTTP/1.1\r\nHost: x\r\n\r\n'`, `b'CONNECT ::1:80 HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | CONNECT with an empty port | 5 | `b'CONNECT a: HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'CONNECT http: HTTP/1.1\r\nHost: a\r\n\r\n'` |
| rejects | together: empty lines before the request line; a percent escape of an ASCII octet in the host of the target | 5 | `b"\r\nCONNECT %B3%7ET:20987 HTTP/1.1\r\nhost: \t %Fe.B:0  \r\n9Do025f': @ 2b  \r\n\r\n"`, `b'\r\nCONNECT VV=)+.Q.%45:080 HTTP/1.1\r\nQCP:  x \r\nHOST: HIatI%6f;,._D3%05DI;c\t\r\n\r\n'` |
| accepts | CONNECT with port 0 | 4 | `b'CONNECT a:0 HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'CONNECT a:00 HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | a target with octets above 0x7F | 4 | `b'CONNECT /\xe9%049Y?qP! HTTP/1.1\r\nhost: [::Ed6:5:b34:e:a:b%25x~y] \t \r\n\r\n'`, `b"HEAD WS:?%Ff%\xcd16'Vm.;D HTTP/1.1\r\nHykvyu.: \t\r\n2wrdni:  i5e\xa0d]vm\|Tc[LhJJk\tP  \r\nhOsT: 250.9.0.0  \r\n\r\n"` |
| accepts | no Host, in HTTP/1.1 to 1.9 | 4 | `b'CONNECT Rsdb3&.H:65535 HTTP/1.9\r\n7t9.q:  H)h17\tIl+Zch  \r\n\r\n'`, `b"CONNECT mNY.x7%e7hXt+.Y:000000000063466 HTTP/1.1\r\nH0W'`: S\t/p\r\nE0kO: Wi@ZN:u\xfe \r\n\r\n"` |
| accepts | two Content-Length lines with the same value | 3 | `b'POST /a HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nContent-Length: 5\r\n\r\n'`, `b'6py#u //%AAW?%d9%Bd HTTP/1.0\r\nHOST: [vfCB7.2yF]  \r\nContent-Length:  876352\r\nContent-Length:  876352\r'` |
| rejects | together: a percent escape of an ASCII octet in the host of the target; a Transfer-Encoding list with empty elements | 3 | `b"GET a+b.c-d://o'ZHM%4Dz.,_u HTTP/1.9\r\nm8H: P# \r\nTRANSFER-ENCODING: \t ,\t \t , \t  ,CHunked \t ,\t, , \r\nHO"`, `b'DELETE http://Raa%Ed%67.tju%2FN/By:@%A8//Tb HTTP/1.1\r\nhEwvIG: )zj*6\xe1hXLt*1b5\t \t \r\ntransfer-encoding:'` |
| rejects | together: empty lines before the request line; the authority-form with a method other than CONNECT; a Transfer-Encoding list with empty elements | 3 | `b'\r\n\r\nGET 253.100.99.99:8080 HTTP/1.9\r\ntransfer-encoding: chunked\t,  \r\nHOST:\t[::8:d5:8] \r\n%q:  Ns;\t=NL'`, `b'\r\nConnect -Qn.3.%97:40608 HTTP/1.9\r\nKR7g: \t  \r\nTransfer-Encoding:,chunked, \r\nFi:  f \x84cjXa  \r\nhOsT: \t'` |
| no answer | a request line that is not three parts | 1 | `b''` |
| rejects | together: empty lines before the request line; a Content-Length of 2^63 or more | 1 | `b"\r\nHEAD /w/Y$6/_m HTTP/1.0\r\nhost: '+%646%4b%7A.,&s%F8.PUy*)  \r\na-Z8bx&8:  i?AZau   \r\nI~*J85d: h Uy \t "` |
| rejects | together: empty lines before the request line; a percent escape of an ASCII octet in the host of the target; a Transfer-Encoding list with empty elements | 1 | `b'\r\nTRACE WS://%61.(.SokWZnP9 HTTP/1.1\r\ntransfer-encoding:  \t , \t  , chUNked ,   , \r\n_.^&D: \t\r\nW#f8s8W'` |
| rejects | together: empty lines before the request line; the authority-form with a method other than CONNECT; a Content-Length of 2^63 or more | 1 | `b'\r\nPOST ;%AC(esd.I-hm.XF%B7E%E7:443 HTTP/1.1\r\nContent-Length: 18446744073709551616\t\r\nhost:iU&f)sz  \r\n'` |

## h11 0.16.0

- Heads sent: 5991
- Same verdict: 4347 (1336 both accept, 3011 both reject)
- Different verdict: 1643 (1183 it accepts and this project rejects, 460 it rejects and this project accepts)
- No answer: 1
- Body lengths compared, where both accept: 1329. Of those, 892 have no body and 437 a non-zero length (382 by Content-Length, 55 chunked). 1329 read the same length and 0 another.
- Not compared, where both accept: 7 with a Content-Length above 1,000,000, and 0 whose answer has no count.

The heads it rejects and this project accepts, by the feature whose change makes it accept them: alone, or together with other changes.

| Feature | Alone | With others |
| --- | --- | --- |
| empty lines before the request line | 306 | 22 |
| a Transfer-Encoding list with empty elements | 132 | 22 |

Where it differs from this project (the two shortest examples):

| It | Category | Heads | Examples |
| --- | --- | --- | --- |
| accepts | a major version other than 1 | 382 | `b'fe * HTTP/0.9\r\nHOST:e\t\r\n\r\n'`, `b'GET / HTTP/2.0\r\nHost: a\r\n\r\n'` |
| rejects | empty lines before the request line | 306 | `b'\r\n\r\nGET / HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'\r\n\r\nPUT x: HTTP/1.1\r\nHost: eu-F\r\n\r\n'` |
| accepts | a Host value with a bad IP literal | 194 | `b'GET / HTTP/1.1\r\nHost: ::1\r\n\r\n'`, `b'GET / HTTP/1.1\r\nHost: [v.a]\r\n\r\n'` |
| rejects | a Transfer-Encoding list with empty elements | 132 | `b'POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked,\r\n\r\n'`, `b'POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: , chunked\r\n\r\n'` |
| accepts | a Host value with an empty host, such as `:80` | 77 | `b'GET / HTTP/1.1\r\nHost: :\r\n\r\n'`, `b'GET / HTTP/1.1\r\nHost: :80\r\n\r\n'` |
| accepts | a folded line (obs-fold) | 77 | `b'CONNECT xbrA:1 HTTP/1.1\r\nHOST: \t \t\r\n\tfolded\r\n\r\n'`, `b'n4tsvnO /mq. HTTP/1.1\r\nhost:  [veC.&b] \t \r\n folded\r\n\r\n'` |
| accepts | a bare LF | 69 | `b'PATCH https:@tR HTTP/1.1\nhOsT:  C.+cH:8080 \r\n\r\n'`, `b'`IH /x+bv HTTP/2.0\nHOST:\t[17aA::35:7d:E3:7E2f] \t \r\n\r\n'` |
| accepts | an http or https target with no host | 67 | `b'GET http: HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'GET HTTP:/ HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | another Host value outside RFC 3986 | 54 | `b'GET / HTTP/1.1\r\nHost: a b\r\n\r\n'`, `b'DELETE /)Uym HTTP/1.1\r\nhost:\tx? \r\n\r\n'` |
| accepts | a target with a bad IP literal | 37 | `b'GET http://[v1.]/ HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'GET http://[1::2::3]/ HTTP/1.1\r\nHost: x\r\n\r\n'` |
| accepts | an http or https target with userinfo | 29 | `b'GET http://@a/ HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'GET http://u@/ HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | CONNECT with a port above 65535 | 23 | `b'CONNECT a:65536 HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'CONNECT a:65616 HTTP/1.1\r\nHost: a\r\n\r\n'` |
| rejects | together: empty lines before the request line; a Transfer-Encoding list with empty elements | 22 | `b'\r\n\r\nj /=nLs@/%47?Fu HTTP/1.1\r\nHost:[vFA.v&nb]\r\ntransfer-encoding:\t ,   ,\t \t ,  ChUNKed ,  \t ,  \r\nsW:'`, `b'\r\n\r\nGET 253.100.99.99:8080 HTTP/1.9\r\ntransfer-encoding: chunked\t,  \r\nHOST:\t[::8:d5:8] \r\n%q:  Ns;\t=NL'` |
| accepts | CONNECT whose target is not a host and port | 21 | `b'CONNECT * HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'CONNECT / HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | Transfer-Encoding in HTTP/1.0 | 21 | `b'POST /a HTTP/1.0\r\nTransfer-Encoding: chunked\r\n\r\n'`, `b'PATCH /v/5%f7&/Bs.X50/ HTTP/1.0\r\nHost: [279D:4aA:7eC:9:FBCb:CD:4:b]  \r\nTRANSFER-ENCODING: Chunked \r\n'` |
| accepts | a Content-Length list of equal values | 20 | `b'POST /a HTTP/1.1\r\nHost: x\r\nContent-Length: 5, 5\r\n\r\n'`, `b'HEAD /@d// HTTP/1.0\r\nZ:; \t \r\nCONTENT-LENGTH:\t5, 5 \t \r\n\r\n'` |
| accepts | an authority-form target with an empty host | 19 | `b'GET :80 HTTP/1.0\r\n\r\n'`, `b'GET :80 HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | CONNECT with content | 16 | `b'CONNECT a:443 HTTP/1.1\r\nHost: a\r\nContent-Length: 5\r\n\r\n'`, `b'CONNECT a:443 HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n'` |
| accepts | another target outside RFC 3986 | 15 | `b'PATCH - HTTP/1.0\r\nhOsT:  : \r\n\r\n'`, `b'GET /a#frag HTTP/1.1\r\nHost: x\r\n\r\n'` |
| accepts | a target with a bad percent escape | 14 | `b'GET /%4g HTTP/1.1\r\nHost: x\r\n\r\n'`, `b'GET /%zz HTTP/1.1\r\nHost: x\r\n\r\n'` |
| accepts | no Host, in HTTP/1.1 to 1.9 | 12 | `b'DELETE 100.0.0.199:0 HTTP/1.2\r\n\r\n'`, `b'HEAD uedU~js.r63Rkw.G2*:65535 HTTP/1.9\r\n\r\n'` |
| accepts | CONNECT with an empty host | 9 | `b'CONNECT :443 HTTP/1.0\r\n\r\n'`, `b'CONNECT : HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | Transfer-Encoding with Content-Length | 8 | `b'POST /a HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nTransfer-Encoding: chunked\r\n\r\n'`, `b'POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nContent-Length: 5\r\n\r\n'` |
| accepts | CONNECT with an empty port | 7 | `b'CONNECT a: HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'CONNECT http: HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | another control octet in a field line | 5 | `b'PUT 100.9.250.1:80 HTTP/2.0\r\nHOST:\t[37b8::9\x03d6:451D]\t\r\n\r\n'`, `b'POST /6/%E1m( HTTP/1.1\r\nHOST: \t x/y\r\nKr+!HVQT:  \r\n^^AdVr: \t b4J\xf7=5rF>q \r\no:  \x8eg"l^\x14v\xc8Y"\tn\r\n\r\n'` |
| accepts | CONNECT with port 0 | 4 | `b'CONNECT a:0 HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'CONNECT a:00 HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | two Content-Length lines with the same value | 3 | `b'POST /a HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nContent-Length: 5\r\n\r\n'`, `b'6py#u //%AAW?%d9%Bd HTTP/1.0\r\nHOST: [vfCB7.2yF]  \r\nContent-Length:  876352\r\nContent-Length:  876352\r'` |
| no answer | a request line that is not three parts | 1 | `b''` |
