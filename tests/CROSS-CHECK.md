# Cross-check with other HTTP parsers

Written by `tests/cross_check.py`, a one-off comparison that is not part of the verified bar. Its docstring says how the heads are sent and judged, and how a difference gets its category. RFC 9112 lets a recipient repair some malformed heads instead of rejecting them, so a difference here is a different choice, not always an error.

- Heads: the first 5991 inputs of the differential tests (seed 20261025, `--count 6000`, less the malformed requests to the tool). Every parser is sent all 5991. A head whose verdicts differ is also sent again with features changed, to find its category.
- This project rejects 3971 of them. It accepts 1242 with no body, 516 with a Content-Length from 1 to 1,000,000, 246 as chunked, and 16 with a Content-Length above 1,000,000.
- Sent after the head: nothing after a head this project rejects; the whole body for a Content-Length up to 1,000,000; `5\r\nhello\r\n0\r\n\r\n` (5 octets of data) for chunked; nothing for a Content-Length above 1,000,000, so those heads are judged on the head alone.
- A parser accepts a head when it reads it and passes the request on, even when it then waits for a body that is never sent.
- In the tables, "accepts" means the other parser accepts a head this project rejects, and "rejects" means it rejects a head this project accepts. The examples show the head as sent, cut at 100 octets.
- Categories: for a head the other parser accepts, the first reason this project rejects it. For a head the other parser rejects, the first feature whose change alone makes that parser accept it, or, after "together:", the features whose changes it needs at once. The script checks that it finds a reason to reject in each head this project rejects and in no other, and that each change keeps a head this project accepts.

## Node v22.22.0 (llhttp)

- Heads sent: 5991
- Same verdict: 4246 (903 both accept, 3343 both reject)
- Different verdict: 1740 (623 it accepts and this project rejects, 1117 it rejects and this project accepts)
- No answer: 5
- Body lengths compared, where both accept: 820. Of those, 594 have no body and 226 a non-zero length (173 by Content-Length, 53 chunked). 820 read the same length and 0 another.
- Not compared, where both accept: 1 with a Content-Length above 1,000,000, and 82 whose answer has no count.

The heads it rejects and this project accepts, by the feature whose change makes it accept them: alone, or together with other changes.

| Feature | Alone | With others |
| --- | --- | --- |
| a method other than the registered ones | 228 | 192 |
| the authority-form with a method other than CONNECT | 163 | 124 |
| an absolute-form target with no authority | 135 | 74 |
| a tab after a Content-Length or Transfer-Encoding value | 113 | 95 |
| HTTP/1.2 to 1.9 | 78 | 95 |
| a Transfer-Encoding list with empty elements | 68 | 58 |
| a scheme with a digit, "+", "-" or "." | 10 | 13 |
| a Content-Length of 2^63 or more | 10 | 5 |

Where it differs from this project (the two shortest examples):

| It | Category | Heads | Examples |
| --- | --- | --- | --- |
| rejects | a method other than the registered ones | 228 | `b'Connect / HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'p+Qv` * HTTP/1.1\r\nhost:  [::]\t\r\n\r\n'` |
| rejects | the authority-form with a method other than CONNECT | 163 | `b'OPTIONS [v4E.rKTO]:0 HTTP/1.1\r\nhOsT: \r\n\r\n'`, `b'OPTIONS ,.d.yK2+eOb:0 HTTP/1.1\r\nhost: M0Q\t\r\n\r\n'` |
| rejects | an absolute-form target with no authority | 135 | `b'GET htt:a HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'GET http.s:/ HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | a Host value with a bad IP literal | 122 | `b'GET / HTTP/1.1\r\nHost: ::1\r\n\r\n'`, `b'GET / HTTP/1.1\r\nHost: fe80::1\r\n\r\n'` |
| accepts | a major version other than 1 | 117 | `b'GET / HTTP/2.0\r\nHost: a\r\n\r\n'`, `b'PUT /MT-i(*?V/mG? HTTP/2.0\r\n\r\n'` |
| rejects | a tab after a Content-Length or Transfer-Encoding value | 113 | `b"HEAD /,@%dFKA' HTTP/1.0\r\nhost: [Vc.v] \t \r\nCONTENT-LENGTH: 345367 \t \r\n\r\n"`, `b'PATCH /Qm/;/q/is%EA HTTP/1.1\r\nhOsT: h \t \r\nCONTENT-LENGTH: 702742 \t \r\n\r\n'` |
| accepts | two Host lines | 83 | `b'GET / HTTP/1.0\r\nHost: a\r\nHost: b\r\n\r\n'`, `b'GET / HTTP/1.1\r\nHost: a\r\nHost: a\r\n\r\n'` |
| rejects | HTTP/1.2 to 1.9 | 78 | `b'GET / HTTP/1.2\r\nHost: a\r\n\r\n'`, `b'HEAD /RUXBl HTTP/1.2\r\nhost: [::]:80  \r\n\r\n'` |
| rejects | a Transfer-Encoding list with empty elements | 68 | `b'POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked,\r\n\r\n'`, `b'POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: ,chunked,\r\n\r\n'` |
| rejects | together: the authority-form with a method other than CONNECT; a method other than the registered ones | 60 | `b'wvCMV.5 a(ENN:80 HTTP/1.1\r\nhOsT: t:65535  \r\n\r\n'`, `b'9 %C3G88.E)bwI*G(.B:80 HTTP/1.1\r\nhOsT: ):0 \r\n\r\n'` |
| accepts | another Host value outside RFC 3986 | 42 | `b'GET / HTTP/1.1\r\nHost: a b\r\n\r\n'`, `b'TRACE /m/O8G%06/:Ms?mr2e HTTP/1.1\r\nHOST: %zz\r\n\r\n'` |
| accepts | CONNECT whose target is not a host and port | 35 | `b'CONNECT * HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'CONNECT / HTTP/1.1\r\nHost: a\r\n\r\n'` |
| rejects | together: a method other than the registered ones; a tab after a Content-Length or Transfer-Encoding value | 33 | `b'!$w^u8Y /ioiRO HTTP/1.1\r\nContent-Length: \t 148637 \t \r\nHost:!O(vL\t\r\n\r\n'`, `b'3 /ZA HTTP/1.1\r\ncontent-length: \t 28723\t\r\nHost:\tKJ2aB%b3H: \t \r\n47:0I)B7 \r\n\r\n'` |
| accepts | CONNECT with a port above 65535 | 31 | `b'CONNECT a:65536 HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'CONNECT a:65616 HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | Transfer-Encoding in HTTP/1.0 | 30 | `b'POST /a HTTP/1.0\r\nTransfer-Encoding: chunked\r\n\r\n'`, `b'PUT * HTTP/1.0\r\nTransfer-Encoding:   , \t chUnked\r\nHost:[fa8::06:bca:C5:799]  \r\n\r\n'` |
| accepts | an http or https target with userinfo | 30 | `b'GET http://@a/ HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'GET http://u@/ HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | an http or https target with no host | 28 | `b'GET http:// HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'GET https:// HTTP/1.1\r\nHost: a\r\n\r\n'` |
| rejects | together: a method other than the registered ones; an absolute-form target with no authority | 26 | `b'connect a: HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'connect oU:13096 HTTP/1.1\r\nHOST:WYk5K.Hx \r\n\r\n'` |
| rejects | together: HTTP/1.2 to 1.9; a method other than the registered ones | 25 | `b'9fNJ /J@!/? HTTP/1.9\r\nHost: \t Q.NL,HML:8080 \r\n\r\n'`, `b'CjrA /@/O@W/v)9xfi HTTP/1.9\r\nHost: G_.6%2CP&vOMg  \r\n\r\n'` |
| accepts | a target with a bad IP literal | 21 | `b'GET http://[1::2::3]/ HTTP/1.1\r\nHost: x\r\n\r\n'`, `b'CONNECT [fe80::1%25eth0]:80 HTTP/1.1\r\nHost: a\r\n\r\n'` |
| rejects | together: an absolute-form target with no authority; a tab after a Content-Length or Transfer-Encoding value | 19 | `b'\r\nOPTIONS htt:8:U HTTP/1.1\r\nhOsT: [v0.Y:,]\r\nContent-Length:203433\t\r\n\r\n'`, `b'OPTIONS a+b.c-d:/VF(.YY HTTP/1.1\r\ncontent-length:391873\t\r\nhOsT:  SxN%15.S)Dj:443\r\n\r\n'` |
| accepts | other whitespace in the request line | 15 | `b'GET  /a HTTP/1.1\r\nHost: x\r\n\r\n'`, `b'PATCH  /%ad2 HTTP/1.1\r\nhOsT:  YfTKRC:65535\t\r\n\r\n'` |
| rejects | together: HTTP/1.2 to 1.9; an absolute-form target with no authority | 15 | `b'OPTIONS x:!z%9C HTTP/1.9\r\nhost: SsiU.%fC.v$;:85655  \r\n\r\n'`, `b'PATCH WS:/wA%A4%AbXd//;G%21 HTTP/1.2\r\nHOST: 0.10.100.199\t\r\n\r\n'` |
| rejects | together: a method other than the registered ones; a Transfer-Encoding list with empty elements | 15 | `b'\r\n\r\nj /=nLs@/%47?Fu HTTP/1.1\r\nHost:[vFA.v&nb]\r\ntransfer-encoding:\t ,   ,\t \t ,  ChUNKed ,  \t ,  \r\nsW:'`, `b'\r\n\r\nIAk httpx://%f6)k:@u.Hs:0/A09K-//&xz/&!a%47c5 HTTP/1.1\r\nhOsT: \t 10.99.199.249\r\nTransfer-Encoding'` |
| rejects | together: the authority-form with a method other than CONNECT; a Transfer-Encoding list with empty elements | 15 | `b'\r\nGET y%D3moB.fOL1:8080 HTTP/1.1\r\nTransfer-Encoding:\t, chunked \t \r\nHA:\t\tJRvr! \r\nHOST: 199.100.199.10'`, `b'\r\nOPTIONS %e3$E%DC.KbkK.x:80 HTTP/1.1\r\n`&Alh: \xda \r\nhost:  [2Af9:23:934:F:d7d:7eaD:1b:0B10] \r\nTRANSFER'` |
| rejects | together: the authority-form with a method other than CONNECT; a tab after a Content-Length or Transfer-Encoding value | 15 | `b"PUT %Ccd('3II.D-:443 HTTP/1.1\r\nhOsT: %aE3Mm%49.FED:0  \r\ncontent-length: 819795 \t \r\n\r\n"`, `b'\r\nPATCH 195.99.250.9:65535 HTTP/1.0\r\nhost:\t99.199.249.199\t\r\ncontent-length:\t159570 \t \r\n\r\n'` |
| rejects | together: HTTP/1.2 to 1.9; the authority-form with a method other than CONNECT | 14 | `b'TRACE [::A:BE8]: HTTP/1.2\r\nHOST: [cA:3:ED9:a:932:F:6e:E98]:\r\n\r\n'`, `b'GET [9CB7:E8eD:add:0C0::11e0]:0 HTTP/1.2\r\nHOST:  [V9545.33] \t \r\n\r\n'` |
| rejects | together: HTTP/1.2 to 1.9; a tab after a Content-Length or Transfer-Encoding value | 13 | `b'PUT HTtPS://%a1:40382 HTTP/1.2\r\ncontent-length:  114915 \t \r\nhost:[::]\r\n\r\n'`, `b'PATCH /$0Vc%29//X/:e?4 HTTP/1.9\r\nhOsT:  %f2FYa.%0C0g  \r\ncontent-length:\t973470 \t \r\n\r\n'` |
| accepts | CONNECT with port 0 | 12 | `b'CONNECT a:0 HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'CONNECT a:00 HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | a bare LF | 12 | `b'\n\r\nGET / HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'\n\r\nOPTIONS /8%43Wmkc/Z%33B HTTP/1.1\r\nHOST: fG93YS \t \r\n\r\n'` |
| rejects | a Content-Length of 2^63 or more | 10 | `b'GET * HTTP/1.1\r\nCONTENT-LENGTH:\t18446744073709551616  \r\nhOsT:\t[v0.R] \r\n\r\n'`, `b'DELETE /W,/D8gX@/?B/ HTTP/1.0\r\nhOsT:L.XM\r\nCONTENT-LENGTH: 18446744073709551616  \r\n\r\n'` |
| rejects | a scheme with a digit, "+", "-" or "." | 10 | `b'TRACE a+b.c-d://JpR-c%d6:95702 HTTP/1.1\r\nhOsT:A!0(r2.n) \r\n\r\n'`, `b'\r\nHEAD https+x://,u.R5LzJi%e4 HTTP/1.1\r\nHEht: \t q3:W\tP\t\r\nHost: 199.0.32.200 \r\n\r\n'` |
| rejects | together: HTTP/1.2 to 1.9; a Transfer-Encoding list with empty elements | 10 | `b'DELETE /O~B%c1/dKo%AB4/k! HTTP/1.9\r\nTRANSFER-ENCODING:,chunked\t\r\nhOsT: L9L.h.48CrV \r\n\r\n'`, `b'PUT /O%D6/%00%61yd?R1$ HTTP/1.9\r\nhost:\tj*Lr*.3-OGMF\t\r\nTransfer-Encoding: chunked\t,  \r\n\r\n'` |
| accepts | CONNECT with an empty port | 7 | `b'CONNECT a: HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'CONNECT http: HTTP/1.1\r\nHost: a\r\n\r\n'` |
| rejects | together: the authority-form with a method other than CONNECT; a method other than the registered ones; a tab after a Content-Length or Transfer-Encoding value | 7 | `b'5a3x-oKN [VE.U0b]:443 HTTP/1.1\r\nhost::80\r\ncontent-length: \t 799121\t\r\n\r\n'`, `b'aL 199.10.1.199:80 HTTP/1.1\r\nHost:200.0.250.196 \r\nCONTENT-LENGTH:\t736918\t\r\n\r\n'` |
| accepts | a target with a bad percent escape | 6 | `b'GET /%4g HTTP/1.1\r\nHost: x\r\n\r\n'`, `b'GET /%zz HTTP/1.1\r\nHost: x\r\n\r\n'` |
| rejects | together: an absolute-form target with no authority; a Transfer-Encoding list with empty elements | 6 | `b"HEAD http.s:%AALv?%6d'D/%bD HTTP/1.1\r\nhost:[a773::C2E:C3]:65535 \t \r\nTRANSFER-ENCODING:chunked, \t \r\n\r"`, `b"HEAD x:&Ru' HTTP/1.1\r\n8lUky:\tbsz>ZNv`\r\nd*Y4: z&\xbblGW0S \r\nhOsT:1.10.99.9  \r\ntransfer-encoding:chunked,"` |
| accepts | a bare CR | 5 | `b'\r\r\nPATCH /T/ HTTP/1.0\r\nHost: q6:0  \r\nW:  <K+\xd4+iyjnl"\xdc \r\n_CK:o \t \r\n68uNgp1l: A95ZbS> \t \r\n~JjU^Yr7:  b'`, `b"\rDELETE HTTP://[9fA9:6dac:2:C:Aa:E04:0c74:F3]:80/U&)GM/r%4aD HTTP/2.0\r\n'SiK:\t \t \r\nhOsT: \t !1s8 \r\nVKp"` |
| accepts | no Host, in HTTP/1.1 to 1.9 | 5 | `b'CONNECT [7c:bBa:0043:40b4:565:D36D:B61c:0Ca]:5240 HTTP/1.1\r\n\r\n'`, `b'CONNECT [4C::9:e3d6:1CB0:62]:37642 HTTP/1.1\r\naTBg: \\( \r\nCONTENT-LENGTH:193114 \r\n\r\n'` |
| rejects | together: HTTP/1.2 to 1.9; the authority-form with a method other than CONNECT; a method other than the registered ones | 5 | `b'Lis n7IVR=..%92+*AE.+A3Wn;M:65535 HTTP/1.2\r\nNsk:\tO FM/V`\t2\t\r\n0H$: \t\t \t \r\nHost:\t250.249.100.255\t\r\n\r\n'`, `b'XY6N u%F22eY.kK%dDlc%47:65535 HTTP/1.9\r\nO~7ue: \t\r\n8`t\|m.*: \\\t7\tG3/\xeaI \tO?\xc8[)  \r\nHost:\t[V8.z0] \t \r\n\r\n'` |
| rejects | together: a method other than the registered ones; a scheme with a digit, "+", "-" or "." | 5 | `b'`&hdT http.s://g:60322/8-f/l?q%56: HTTP/1.1\r\nhost: \t [v9CAF.drA]:8080\t\r\n\r\n'`, `b'y-yk http.s://[7AE2::D2]:38737/.:d/7EW0/%7e0%b0:V: HTTP/1.1\r\nhost:\t100.248.255.200 \r\ncontent-length:'` |
| rejects | together: the authority-form with a method other than CONNECT; a method other than the registered ones; a Transfer-Encoding list with empty elements | 5 | `b'B*0%3Al jri3SE4.%D49A;.vSV-: HTTP/1.1\r\nTRANSFER-ENCODING:   \t , \t  ,\t ,  chunkEd ,  \t \r\nhost:10.99.1'`, `b'connect w.Kyt5%53.3!Sgfhj*:4294967376 HTTP/1.1\r\nhOsT:\t[::3d9]:52843\t\r\nAB_4: \t /i\x96 \t \r\nj: L %Y\tAABn@o'` |
| accepts | a Transfer-Encoding with no coding | 4 | `b'POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding:\r\n\r\n'`, `b'PUT /91/%EC=0)*9/lr5 HTTP/1.1\r\noLpY&~NQ: VBYS]F_\t\r\nTRANSFER-ENCODING: \t  \t \r\nHOST: 99.156.200.9 \r\n\r\n'` |
| accepts | another target outside RFC 3986 | 4 | `b'GET /a#frag HTTP/1.1\r\nHost: x\r\n\r\n'`, `b'CONNECT ::1:80 HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | chunked twice, over two or more lines | 4 | `b'GET /4a/wqG1%4dC/37%d3/zX? HTTP/1.1\r\nIVLI~C: \r\nHOST:   \r\nTRANSFER-ENCODING: CHUNKED\t\r\n*XC:\tI a \t \r\nT'`, `b'HEAD /NmW!UQ HTTP/1.1\r\nhOsT: 200.10.255.9:8080\t\r\ntransfer-encoding: CHUNKED\t\r\n$ckO_: \t HW,\xd8\\D=Q \t \r\n'` |
| accepts | a Transfer-Encoding with another coding before chunked | 3 | `b'POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: gzip, chunked\r\n\r\n'`, `b'PUT /8cv/8Vg/3,UccM??Iz HTTP/1.1\r\ntransfer-encoding:identity \t , \t cHuNKeD \r\nhost:\tfe80::1 \t \r\n\r\n'` |
| accepts | chunked twice | 3 | `b'\r\n\r\nPUT * HTTP/1.1\r\nhost: cFA7:::80\r\nhost: cFA7:::80\r\nTRANSFER-ENCODING: \t ,   ,\t  , chunked\t,, chun'`, `b"HEAD http://a: HTTP/1.1\r\nUwqxK3\|:R\xfb}\xfc'L\t E@ \r\nnngW:\tb \r\ntransfer-encoding:\t, \t  , chunkeD\t,\t, chunke"` |
| no answer | a request line that is not three parts | 3 | `b''` |
| rejects | together: a scheme with a digit, "+", "-" or "."; a tab after a Content-Length or Transfer-Encoding value | 3 | `b'OPTIONS http.s://C%AeMkR/RZ%cb%e6h7 HTTP/1.1\r\ncontent-length:19729\t\r\nhWe:\t>JyYDil/& t&G =\r\nHost: 2l3'`, `b'PATCH https+x://:(@H.!%2er.t:92666/n;6?O-LV& HTTP/1.1\r\nhost: \t [E06:D:bf:82:F84:c393:b8:edA]\r\nOgJ:\t '` |
| rejects | together: HTTP/1.2 to 1.9; a Content-Length of 2^63 or more | 2 | `b"GET /=Nu%e9//IC:u*?X'pWm%E8SY HTTP/1.9\r\nhost: [D:C:ED::] \t \r\ncontent-length:  18446744073709551616\t\r"`, `b'OPTIONS /,hNz?8~, HTTP/1.9\r\nsPF+V:\tBm\x9a 3+5PdF\x83  \t \r\nCONTENT-LENGTH:18446744073709551616\t\r\nHost:ZJN4\r'` |
| rejects | together: HTTP/1.2 to 1.9; a method other than the registered ones; a tab after a Content-Length or Transfer-Encoding value | 2 | `b'SQBrlAX /X(W;!F?azE0 HTTP/1.2\r\n&u~5ssN:\t@1PMD#A\\n  \r\nhost:mW.pUk..mbWHt.JoY \t \r\nhb:  )\tI)  \r\nCONTENT'`, `b'H * HTTP/1.2\r\nR^T%: *Bp\xd5k\\S\x97\|8hST \r\nr\|HOZCn-: \t m x$ s?E:\xdc0R  \r\nhOsT:pC.!A=zZ9%cck.%d8a2fG:0 \r\n6:>Dh'` |
| rejects | together: HTTP/1.2 to 1.9; a scheme with a digit, "+", "-" or "." | 2 | `b'POST https+x://:,(@[F5dD:Df:8C73:DeB:DC:fA:a:10] HTTP/1.9\r\nW: \x82  s  \r\nwfc:  -v \tJ3\xca:.\t_\t \r\n_SXFD:  5'`, `b'OPTIONS a+b.c-d://[v9.G]/Fy5eS/U./8y@/Xy!+?%33WU HTTP/1.9\r\ncontent-length: 248636 \r\nhost:H_T%dD.;IWe'` |
| rejects | together: HTTP/1.2 to 1.9; an absolute-form target with no authority; a Transfer-Encoding list with empty elements | 2 | `b'DELETE x:~cCa HTTP/1.2\r\nhOsT:\ta~3a-g.p8.RS3W:94211  \r\nTRANSFER-ENCODING: \t  , chUNked\t\r\nulA~DkT:  io'`, `b"PATCH x: HTTP/1.9\r\nhost: pXg5'.b%1B3.yyv \t \r\nTransfer-Encoding: \t   ,\tcHUnked  ,   , \t\r\nTransfer-Enc"` |
| rejects | together: a method other than the registered ones; an absolute-form target with no authority; a Transfer-Encoding list with empty elements | 2 | `b'Q+8HD x:/7CM)?i7QY?Szj HTTP/1.1\r\ntransfer-encoding:\tchunked \t , \t   ,\t \t ,   \t \r\nHost:  [::]: \r\nOMUf'`, `b"tjF$F1 WS:/L/%34RT3Y HTTP/1.1\r\nTRANSFER-ENCODING: chunKed ,  , \t   \r\nHost: E,'%B0*SRh.d)2'%55B\t\r\nn00"` |
| rejects | together: a scheme with a digit, "+", "-" or "."; a Transfer-Encoding list with empty elements | 2 | `b'OPTIONS https+x://s.a%FdQX2%Dbgq/ih:m- HTTP/1.1\r\ntransfer-encoding: \t,  cHUnKeD \t \r\nTransfer-Encodin'`, `b'\r\n\r\nOPTIONS http.s://[84A7:a:A36::B:10.200.99.100]:80/t/rv26 HTTP/1.1\r\n^dxbY: @e-z \t*FCG W=nX=~XYh \r'` |
| accepts | a Transfer-Encoding whose last coding is not chunked | 1 | `b'CONNECT )%De.xqon.k:15839 HTTP/1.1\r\nHost:+df$iDv.L%1b4C7=.FzwsTE \t \r\n^mj: &(A\tlR.cA? \r\ntransfer-enco'` |
| accepts | a Transfer-Encoding whose last coding is not chunked, over two or more lines | 1 | `b'CONNECT HTTP:65535 HTTP/1.1\r\ntransfer-encoding:hunked \t \r\nng7:\tSI\xd89 \\z \xed\| \r\nHost:  \r\ntransfer-encodi'` |
| accepts | a Transfer-Encoding with another coding before chunked, over two or more lines | 1 | `b'POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: gzip\r\nTransfer-Encoding: chunked\r\n\r\n'` |
| accepts | a request line that is not three parts | 1 | `b'PUT /X/%4d@)AmF/%B8/HTTP/1.1\r\nHost: \t [v84E5.alb] \r\n\r\n'` |
| no answer | a bare CR | 1 | `b'\r\r\n\r\n'` |
| no answer | empty lines before the request line | 1 | `b'\r\n'` |
| rejects | together: HTTP/1.2 to 1.9; a method other than the registered ones; a Transfer-Encoding list with empty elements | 1 | `b'\r\n\r\n1It.!%.N ///V1c HTTP/1.9\r\nTransfer-Encoding: \r\nHOST: yKZcsc.y_o*vp.4N2E%4a%25 \r\nTRANSFER-ENCODIN'` |
| rejects | together: HTTP/1.2 to 1.9; a method other than the registered ones; a scheme with a digit, "+", "-" or "." | 1 | `b'NFV2lN http.s://G7lhG.bIyy.qo%Fbz-ZE/RyZN/AfQv?w HTTP/1.2\r\nygl:UOw\\ B\xaa \t \r\nu3J: /n]\xc4P\t\xfe*\r\nhost: m&cD'` |
| rejects | together: HTTP/1.2 to 1.9; a method other than the registered ones; an absolute-form target with no authority | 1 | `b'K*H#87N http.s:HCrr HTTP/1.9\r\nNg:2jlUP7S\r\nHOST:\t%Cd*6z%38(:0\t\r\n\r\n'` |
| rejects | together: HTTP/1.2 to 1.9; the authority-form with a method other than CONNECT; a method other than the registered ones; a tab after a Content-Length or Transfer-Encoding value | 1 | `b'cqqAt+ %c0wUi.%b7c,Xj.kj7Mj2iu:443 HTTP/1.2\r\nhost:100.10.1.250 \t \r\ncontent-length:  338980 \t \r\n\r\n'` |
| rejects | together: HTTP/1.2 to 1.9; the authority-form with a method other than CONNECT; a tab after a Content-Length or Transfer-Encoding value | 1 | `b'PATCH [vd.9]:93661 HTTP/1.2\r\nContent-Length: 923212\t\r\nHOST: [V8F.UZRd]\r\n\r\n'` |
| rejects | together: a method other than the registered ones; an absolute-form target with no authority; a Content-Length of 2^63 or more | 1 | `b'*sFKoG* ws: HTTP/1.0\r\nHost: [aCF:d:ae3:F::E]\r\nxYF:\t0\xef\xd8{\xbfW\tK FC1\x9dIl= \r\nd\'Q9ZZcU:\t*@\xeeV ^W8"zTIHv  \t \r\n'` |
| rejects | together: a method other than the registered ones; an absolute-form target with no authority; a tab after a Content-Length or Transfer-Encoding value | 1 | `b'O&M*1 htt:)GE%9eA?a0%b5R1soR HTTP/1.1\r\nhost: zI&BR5.3I%B3:65535\t\r\nTransfer-Encoding: CHUNKED \t \r\n\r\n'` |
| rejects | together: an absolute-form target with no authority; a Content-Length of 2^63 or more | 1 | `b"OPTIONS httpx: HTTP/1.1\r\nContent-Length:18446744073709551616 \r\nHost: \t _u9mc'5.lKf%99vt.U%EA;Q \t \r\n\r"` |
| rejects | together: the authority-form with a method other than CONNECT; a method other than the registered ones; a Content-Length of 2^63 or more | 1 | `b'Ql xbK.Sq~9D3:0 HTTP/1.0\r\naUjO&:  <\xe5\tt3\xd0} a*o \xbe\r\n9:DK Ti\xba  \r\nhOsT:\t0XZ%A0.o:65535\r\nCONTENT-LENGTH:18'` |

## Go go1.24.7 net/http

- Heads sent: 5991
- Same verdict: 4654 (1282 both accept, 3372 both reject)
- Different verdict: 1334 (596 it accepts and this project rejects, 738 it rejects and this project accepts)
- No answer: 3
- Body lengths compared, where both accept: 1281. Of those, 862 have no body and 419 a non-zero length (359 by Content-Length, 60 chunked). 1281 read the same length and 0 another.
- Not compared, where both accept: 1 with a Content-Length above 1,000,000, and 0 whose answer has no count.

The heads it rejects and this project accepts, by the feature whose change makes it accept them: alone, or together with other changes.

| Feature | Alone | With others |
| --- | --- | --- |
| empty lines before the request line | 263 | 83 |
| the authority-form with a method other than CONNECT | 216 | 72 |
| a Transfer-Encoding list with empty elements | 115 | 50 |
| a percent escape of an ASCII octet in the host of the target | 28 | 6 |
| a Content-Length of 2^63 or more | 10 | 5 |

Where it differs from this project (the two shortest examples):

| It | Category | Heads | Examples |
| --- | --- | --- | --- |
| rejects | empty lines before the request line | 263 | `b'\r\n\r\nGET / HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'\r\n\r\nPUT x: HTTP/1.1\r\nHost: eu-F\r\n\r\n'` |
| rejects | the authority-form with a method other than CONNECT | 216 | `b'OPTIONS [v4E.rKTO]:0 HTTP/1.1\r\nhOsT: \r\n\r\n'`, `b'OPTIONS ,.d.yK2+eOb:0 HTTP/1.1\r\nhost: M0Q\t\r\n\r\n'` |
| accepts | a Host value with a bad IP literal | 154 | `b'GET / HTTP/1.1\r\nHost: ::1\r\n\r\n'`, `b'GET / HTTP/1.1\r\nHost: fe80::1\r\n\r\n'` |
| rejects | a Transfer-Encoding list with empty elements | 115 | `b'POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked,\r\n\r\n'`, `b'POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: , chunked\r\n\r\n'` |
| accepts | Transfer-Encoding in HTTP/1.0 | 99 | `b'POST /a HTTP/1.0\r\nTransfer-Encoding: chunked\r\n\r\n'`, `b'POST /a HTTP/1.0\r\nTransfer-Encoding: chunked,\r\n\r\n'` |
| accepts | an http or https target with no host | 72 | `b'GET http: HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'GET HTTP:/ HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | a bare LF | 59 | `b'PATCH https:@tR HTTP/1.1\nhOsT:  C.+cH:8080 \r\n\r\n'`, `b'POST /a HTTP/1.1\r\nHost: x\nTransfer-Encoding: chunked\r\n\r\n'` |
| rejects | together: empty lines before the request line; the authority-form with a method other than CONNECT | 48 | `b'\r\nPATCH [vD.T_2]:0 HTTP/1.1\r\nHost:\t!%25%Ca5hg:443\t\r\n\r\n'`, `b"\r\n\r\nGET 8X8)F%ce.%9FPnV-.~'%d1=Y4+c:6523 HTTP/1.1\r\nHOST: \t\r\n\r\n"` |
| accepts | a folded line (obs-fold) | 36 | `b'POST /a HTTP/1.1\r\nHost: x\r\nX: y\r\n Transfer-Encoding: chunked\r\n\r\n'`, `b'PATCH /p6(? HTTP/1.2\r\nWzdQd#:\t\r\n\tfolded\r\nhost:\t%7Eyh$Z  \r\ncontent-length: 910516 \t \r\n\r\n'` |
| accepts | CONNECT whose target is not a host and port | 30 | `b'CONNECT * HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'CONNECT / HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | an http or https target with userinfo | 28 | `b'GET http://@a/ HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'GET http://u@/ HTTP/1.1\r\nHost: a\r\n\r\n'` |
| rejects | a percent escape of an ASCII octet in the host of the target | 28 | `b'GET http://%41%42/ HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'lC+vi http://P%5a HTTP/1.9\r\nhost: i4x%f8.R=SFP= \t \r\n\r\n'` |
| accepts | CONNECT with a port above 65535 | 26 | `b'CONNECT a:65536 HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'CONNECT a:65616 HTTP/1.1\r\nHost: a\r\n\r\n'` |
| rejects | together: empty lines before the request line; a Transfer-Encoding list with empty elements | 25 | `b'\r\nTRACE /%f4Qc/V/%22GA HTTP/1.9\r\nTransfer-Encoding: ChuNKed , \t,  \r\nhOsT:  1.9.10.0250 \r\n\r\n'`, `b'\r\n\r\nj /=nLs@/%47?Fu HTTP/1.1\r\nHost:[vFA.v&nb]\r\ntransfer-encoding:\t ,   ,\t \t ,  ChUNKed ,  \t ,  \r\nsW:'` |
| accepts | a target with a bad IP literal | 23 | `b'GET http://[1::2::3]/ HTTP/1.1\r\nHost: x\r\n\r\n'`, `b'CONNECT [fe80::1%25eth0]:80 HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | another Host value outside RFC 3986 | 22 | `b'TRACE /m/O8G%06/:Ms?mr2e HTTP/1.1\r\nHOST: %zz\r\n\r\n'`, `b'TRACE /q//%8f HTTP/1.1\r\nhOsT: h:p \t \r\nBiZ_9ZR: \xfc \r\n\r\n'` |
| rejects | together: the authority-form with a method other than CONNECT; a Transfer-Encoding list with empty elements | 19 | `b'GET :10667 HTTP/1.9\r\nCRiVcO0: \t <7H\xbf  \r\nXH:   \r\ntransfer-encoding: , ,  cHunked \r\nhost:99.1.199.1 \r\n'`, `b'E6&_pN 7buBY=%58s:80 HTTP/1.1\r\nw5vpn&U*: \t A;\xec_g\r\ntransfer-encoding:\t,  chunkEd \r\nhost:  250.99.0.20'` |
| accepts | Transfer-Encoding with Content-Length | 12 | `b'POST /a HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nTransfer-Encoding: chunked\r\n\r\n'`, `b'POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nContent-Length: 5\r\n\r\n'` |
| rejects | a Content-Length of 2^63 or more | 10 | `b'GET * HTTP/1.1\r\nCONTENT-LENGTH:\t18446744073709551616  \r\nhOsT:\t[v0.R] \r\n\r\n'`, `b'DELETE /W,/D8gX@/?B/ HTTP/1.0\r\nhOsT:L.XM\r\nCONTENT-LENGTH: 18446744073709551616  \r\n\r\n'` |
| accepts | CONNECT with port 0 | 8 | `b'CONNECT a:0 HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'CONNECT a:00 HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | CONNECT with an empty port | 7 | `b'CONNECT a: HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'CONNECT http: HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | a target with octets above 0x7F | 6 | `b'CONNECT /\xe9%049Y?qP! HTTP/1.1\r\nhost: [::Ed6:5:b34:e:a:b%25x~y] \t \r\n\r\n'`, `b"HEAD //%Ea%1CK\xd2L~/bN/,, HTTP/1.2\r\nHost:  Qsh.y7&  \r\n4\|EF:\t \xf2'\xab.'e\tN\t\r\n\r\n"` |
| accepts | another target outside RFC 3986 | 5 | `b'GET /a#frag HTTP/1.1\r\nHost: x\r\n\r\n'`, `b'CONNECT ::1:80 HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | two Content-Length lines with the same value | 5 | `b'POST /a HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nContent-Length: 5\r\n\r\n'`, `b'GET WS: HTTP/1.1\r\nhOsT: \t [7B94:E3:752:5b:d::200.255.255.199] \r\nCONTENT-LENGTH:\t912511 \r\nCONTENT-LEN'` |
| accepts | no Host, in HTTP/1.1 to 1.9 | 4 | `b'CONNECT [7c:bBa:0043:40b4:565:D36D:B61c:0Ca]:5240 HTTP/1.1\r\n\r\n'`, `b'CONNECT [4C::9:e3d6:1CB0:62]:37642 HTTP/1.1\r\naTBg: \\( \r\nCONTENT-LENGTH:193114 \r\n\r\n'` |
| rejects | together: empty lines before the request line; the authority-form with a method other than CONNECT; a Transfer-Encoding list with empty elements | 4 | `b'\r\nGET y%D3moB.fOL1:8080 HTTP/1.1\r\nTransfer-Encoding:\t, chunked \t \r\nHA:\t\tJRvr! \r\nHOST: 199.100.199.10'`, `b'\r\nOPTIONS %e3$E%DC.KbkK.x:80 HTTP/1.1\r\n`&Alh: \xda \r\nhost:  [2Af9:23:934:F:d7d:7eaD:1b:0B10] \r\nTRANSFER'` |
| no answer | a request line that is not three parts | 3 | `b''` |
| rejects | together: empty lines before the request line; a Content-Length of 2^63 or more | 3 | `b'\r\nPOST /q/)%7ch7I7?4%7C3rn HTTP/1.1\r\nhOsT:9.0.0.1 \t \r\ncontent-length: 18446744073709551616 \t \r\nFv: *'`, `b"\r\nHEAD /w/Y$6/_m HTTP/1.0\r\nhost: '+%646%4b%7A.,&s%F8.PUy*)  \r\na-Z8bx&8:  i?AZau   \r\nI~*J85d: h Uy \t "` |
| rejects | together: empty lines before the request line; a percent escape of an ASCII octet in the host of the target | 3 | `b"\r\nCONNECT %B3%7ET:20987 HTTP/1.1\r\nhost: \t %Fe.B:0  \r\n9Do025f': @ 2b  \r\n\r\n"`, `b'\r\n\r\nbwsWe#m https://3)(Q%76P.%0B%D8;9-X:13194 HTTP/1.0\r\nHost: [1e::BEf7:E:7:CDf:3] \t \r\n\r\n'` |
| rejects | together: a percent escape of an ASCII octet in the host of the target; a Transfer-Encoding list with empty elements | 2 | `b'PATCH http://b.VM%5ApS9.d%d6%31.%E5d.DW%B7(:8080 HTTP/1.1\r\nwH+:g[E\ts6\xb5br[ ](7D"G \t \r\nTransfer-Encodi'`, `b"PATCH https://%20c2f!(U'.P.kN/:9;R/@is/~0V+?sjI%D7U?b%0E HTTP/1.1\r\nTRANSFER-ENCODING: , chunked \r\nho"` |
| rejects | together: a percent escape of an ASCII octet in the host of the target; a Content-Length of 2^63 or more | 1 | `b'PUT HTtPS://Us%72eG.ciN%8CXg?Gi%2FH HTTP/1.0\r\nhQ6vv5F:g1)\t\r\nCONTENT-LENGTH: 18446744073709551616 \r\nR'` |
| rejects | together: the authority-form with a method other than CONNECT; a Content-Length of 2^63 or more | 1 | `b'Ql xbK.Sq~9D3:0 HTTP/1.0\r\naUjO&:  <\xe5\tt3\xd0} a*o \xbe\r\n9:DK Ti\xba  \r\nhOsT:\t0XZ%A0.o:65535\r\nCONTENT-LENGTH:18'` |

## h11 0.16.0

- Heads sent: 5991
- Same verdict: 4561 (1538 both accept, 3023 both reject)
- Different verdict: 1427 (945 it accepts and this project rejects, 482 it rejects and this project accepts)
- No answer: 3
- Body lengths compared, where both accept: 1525. Of those, 1032 have no body and 493 a non-zero length (426 by Content-Length, 67 chunked). 1525 read the same length and 0 another.
- Not compared, where both accept: 13 with a Content-Length above 1,000,000, and 0 whose answer has no count.

The heads it rejects and this project accepts, by the feature whose change makes it accept them: alone, or together with other changes.

| Feature | Alone | With others |
| --- | --- | --- |
| empty lines before the request line | 317 | 29 |
| a Transfer-Encoding list with empty elements | 136 | 29 |

Where it differs from this project (the two shortest examples):

| It | Category | Heads | Examples |
| --- | --- | --- | --- |
| rejects | empty lines before the request line | 317 | `b'\r\n\r\nGET / HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'\r\n\r\nPUT x: HTTP/1.1\r\nHost: eu-F\r\n\r\n'` |
| accepts | a Host value with a bad IP literal | 195 | `b'GET / HTTP/1.1\r\nHost: ::1\r\n\r\n'`, `b'GET / HTTP/1.1\r\nHost: fe80::1\r\n\r\n'` |
| accepts | a major version other than 1 | 191 | `b'fe * HTTP/0.9\r\nHOST:e\t\r\n\r\n'`, `b'GET / HTTP/2.0\r\nHost: a\r\n\r\n'` |
| rejects | a Transfer-Encoding list with empty elements | 136 | `b'POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked,\r\n\r\n'`, `b'POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: , chunked\r\n\r\n'` |
| accepts | a bare LF | 79 | `b'_ha&h^r ::2B86:410:0 HTTP/1.0\n\r\n'`, `b'PATCH https:@tR HTTP/1.1\nhOsT:  C.+cH:8080 \r\n\r\n'` |
| accepts | an http or https target with no host | 78 | `b'GET http: HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'GET HTTP:/ HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | a folded line (obs-fold) | 65 | `b'DELETE /%Ffb)%A5rN/_:M* HTTP/1.0\r\nhOsT: [::1F9]\r\n\tfolded\r\n\r\n'`, `b'#4WZd /-gg?U HTTP/1.1\r\nhOsT: GE-ku.Q=N6eg.CN:443  \r\n\tfolded\r\n\r\n'` |
| accepts | another Host value outside RFC 3986 | 63 | `b'GET / HTTP/1.1\r\nHost: a b\r\n\r\n'`, `b'PATCH x:y!??J9*O9 HTTP/1.1\r\nHOST:\tx/y \r\nT:  \r\n\r\n'` |
| accepts | a target with a bad IP literal | 42 | `b'GET http://[1::2::3]/ HTTP/1.1\r\nHost: x\r\n\r\n'`, `b'CONNECT [fe80::1%25eth0]:80 HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | a Content-Length list of equal values | 34 | `b'POST /a HTTP/1.1\r\nHost: x\r\nContent-Length: 5, 5\r\n\r\n'`, `b'TRACE /:/R/:QH?H HTTP/1.9\r\nhost: [V09.Vjf]\t\r\ncontent-length: \t 5, 5\t\r\n\r\n'` |
| accepts | an http or https target with userinfo | 31 | `b'GET http://@a/ HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'GET http://u@/ HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | CONNECT whose target is not a host and port | 30 | `b'CONNECT * HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'CONNECT / HTTP/1.1\r\nHost: a\r\n\r\n'` |
| rejects | together: empty lines before the request line; a Transfer-Encoding list with empty elements | 29 | `b'\r\nTRACE /%f4Qc/V/%22GA HTTP/1.9\r\nTransfer-Encoding: ChuNKed , \t,  \r\nhOsT:  1.9.10.0250 \r\n\r\n'`, `b'\r\n\r\nj /=nLs@/%47?Fu HTTP/1.1\r\nHost:[vFA.v&nb]\r\ntransfer-encoding:\t ,   ,\t \t ,  ChUNKed ,  \t ,  \r\nsW:'` |
| accepts | CONNECT with a port above 65535 | 28 | `b'CONNECT a:65536 HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'CONNECT a:65616 HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | Transfer-Encoding in HTTP/1.0 | 20 | `b'POST /a HTTP/1.0\r\nTransfer-Encoding: chunked\r\n\r\n'`, `b'TRACE 200.255.9.199:65535 HTTP/1.0\r\nhOsT: \t @x \r\ntransfer-encoding:\tChunked\t\r\n\r\n'` |
| accepts | Transfer-Encoding with Content-Length | 19 | `b'POST /a HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nTransfer-Encoding: chunked\r\n\r\n'`, `b'POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nContent-Length: 5\r\n\r\n'` |
| accepts | another target outside RFC 3986 | 13 | `b'GET /a#frag HTTP/1.1\r\nHost: x\r\n\r\n'`, `b'CONNECT ::1:80 HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | a target with a bad percent escape | 12 | `b'GET /%4g HTTP/1.1\r\nHost: x\r\n\r\n'`, `b'GET /%zz HTTP/1.1\r\nHost: x\r\n\r\n'` |
| accepts | no Host, in HTTP/1.1 to 1.9 | 12 | `b'GET * HTTP/1.9\r\nt:  z\x8aJgZy\xbdE \r\n\r\n'`, `b'POST /P%BA/nX/?0? HTTP/1.2\r\nX:\twIS@ I Dd \t\r\n\r\n'` |
| accepts | another control octet in a field line | 11 | `b'POST /6/%E1m( HTTP/1.1\r\nHOST: \t x/y\r\nKr+!HVQT:  \r\n^^AdVr: \t b4J\xf7=5rF>q \r\no:  \x8eg"l^\x14v\xc8Y"\tn\r\n\r\n'`, `b"qf cF.pOLTlh.RAHD4E: HTTP/1.1\r\np#:  \r\n'dwTHP9: \t  \r\nXKz: \t >EL:v:Cby'lZu\r\nhOsT:\x12QQ%cdR*L.2!$p\t\r\n\r\n"` |
| accepts | CONNECT with port 0 | 8 | `b'CONNECT a:0 HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'CONNECT a:00 HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | CONNECT with an empty port | 7 | `b'CONNECT a: HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'CONNECT http: HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | two Content-Length lines with the same value | 7 | `b'POST /a HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nContent-Length: 5\r\n\r\n'`, `b'GET WS: HTTP/1.1\r\nhOsT: \t [7B94:E3:752:5b:d::200.255.255.199] \r\nCONTENT-LENGTH:\t912511 \r\nCONTENT-LEN'` |
| no answer | a request line that is not three parts | 3 | `b''` |
