# Cross-check with other HTTP parsers

Written by `tests/cross_check.py`, a one-off comparison that is not part of the verified bar. Its docstring says how the heads are sent and judged, and how a difference gets its category. RFC 9112 lets a recipient repair some malformed heads instead of rejecting them, so a difference here is a different choice, not always an error.

- Heads: the first 5991 inputs of the differential tests (seed 20261025, `--count 6000`, less the malformed requests to the tool). Every parser is sent all 5991. A head whose verdicts differ is also sent again with features changed, to find its category.
- This project rejects 3791 of them. It accepts 1372 with no body, 529 with a Content-Length from 1 to 1,000,000, 288 as chunked, and 11 with a Content-Length above 1,000,000.
- Sent after the head: nothing after a head this project rejects; the whole body for a Content-Length up to 1,000,000; `5\r\nhello\r\n0\r\n\r\n` (5 octets of data) for chunked; nothing for a Content-Length above 1,000,000, so those heads are judged on the head alone.
- A parser accepts a head when it reads it and passes the request on, even when it then waits for a body that is never sent.
- In the tables, "accepts" means the other parser accepts a head this project rejects, and "rejects" means it rejects a head this project accepts. The examples show the head as sent, cut at 100 octets.
- Categories: for a head the other parser accepts, the first reason this project rejects it. For a head the other parser rejects, the first feature whose change alone makes that parser accept it, or, after "together:", the features whose changes it needs at once. The script checks that it finds a reason to reject in each head this project rejects and in no other, and that each change keeps a head this project accepts.

## Node v22.22.0 (llhttp)

- Heads sent: 5991
- Same verdict: 4130 (910 both accept, 3220 both reject)
- Different verdict: 1855 (565 it accepts and this project rejects, 1290 it rejects and this project accepts)
- No answer: 6
- Body lengths compared, where both accept: 837. Of those, 630 have no body and 207 a non-zero length (155 by Content-Length, 52 chunked). 837 read the same length and 0 another.
- Not compared, where both accept: 0 with a Content-Length above 1,000,000, and 73 whose answer has no count.

The heads it rejects and this project accepts, by the feature whose change makes it accept them: alone, or together with other changes.

| Feature | Alone | With others |
| --- | --- | --- |
| a method other than the registered ones | 206 | 239 |
| an absolute-form target with no authority | 151 | 123 |
| the authority-form with a method other than CONNECT | 144 | 118 |
| HTTP/1.2 to 1.9 | 101 | 124 |
| a tab after a Content-Length or Transfer-Encoding value | 107 | 106 |
| a Transfer-Encoding list with empty elements | 70 | 76 |
| an http or https target with no host | 98 | 44 |
| a scheme with a digit, "+", "-" or "." | 14 | 8 |
| a Content-Length of 2^63 or more | 8 | 3 |

Where it differs from this project (the two shortest examples):

| It | Category | Heads | Examples |
| --- | --- | --- | --- |
| rejects | a method other than the registered ones | 206 | `b'Connect / HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'f$RlX9q * HTTP/1.1\r\nhOsT:\tGYW \r\n\r\n'` |
| rejects | an absolute-form target with no authority | 151 | `b'DELETE x: HTTP/1.1\r\nhOsT:241.9.0.10  \r\n\r\n'`, `b'PUT x:/.J?h HTTP/1.1\r\nHost:2V.fVh&e0i \r\n\r\n'` |
| rejects | the authority-form with a method other than CONNECT | 144 | `b'\r\nPATCH )oHQyK:80 HTTP/1.1\r\nHOST: y5.s \t \r\n\r\n'`, `b'OPTIONS ,.d.yK2+eOb:0 HTTP/1.1\r\nhost: M0Q\t\r\n\r\n'` |
| accepts | a major version other than 1 | 137 | `b'GET / HTTP/2.0\r\nHost: a\r\n\r\n'`, `b'TRACE /y+:p HTTP/0.9\r\nHost: \t (pd.\r\n\r\n'` |
| accepts | a Host value with a bad IP literal | 117 | `b'GET / HTTP/1.1\r\nHost: ::1\r\n\r\n'`, `b'GET / HTTP/1.1\r\nHost: fe80::1\r\n\r\n'` |
| rejects | a tab after a Content-Length or Transfer-Encoding value | 107 | `b'PUT / HTTP/1.0\r\nCONTENT-LENGTH:845637 \t \r\nHost:pLZaduxH.t.kai4D \t \r\n\r\n'`, `b"HEAD /,@%dFKA' HTTP/1.0\r\nhost: [Vc.v] \t \r\nCONTENT-LENGTH: 345367 \t \r\n\r\n"` |
| rejects | HTTP/1.2 to 1.9 | 101 | `b'GET / HTTP/1.2\r\nHost: a\r\n\r\n'`, `b"PATCH //@a/ddx0 HTTP/1.2\r\nHost: \t %78.54' \r\n\r\n"` |
| rejects | an http or https target with no host | 98 | `b'GET http: HTTP/1.1\r\nHost:\tgl~Q:0\r\n\r\n'`, `b'DELETE https:3) HTTP/1.1\r\nHOST:  \r\n\r\n'` |
| accepts | two Host lines | 71 | `b'GET / HTTP/1.0\r\nHost: a\r\nHost: b\r\n\r\n'`, `b'GET / HTTP/1.1\r\nHost: a\r\nHost: a\r\n\r\n'` |
| rejects | a Transfer-Encoding list with empty elements | 70 | `b'POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked,\r\n\r\n'`, `b'POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: ,chunked,\r\n\r\n'` |
| rejects | together: the authority-form with a method other than CONNECT; a method other than the registered ones | 56 | `b'cQpFN aEUaw*%023: HTTP/1.1\r\nhost: [VBDeC.+] \t \r\n\r\n'`, `b"'c. UkdA46.$23b.sqz_~UHD:443 HTTP/1.1\r\nhOsT:\tmPLbM0z  \r\n\r\n"` |
| rejects | together: a method other than the registered ones; an absolute-form target with no authority | 50 | `b'connect a: HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'n a+b.c-d: HTTP/1.0\r\n34:  &\xd0? \r\n\r\n'` |
| accepts | CONNECT whose target is not a host and port | 47 | `b'CONNECT * HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'CONNECT / HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | CONNECT with a port above 65535 | 39 | `b'CONNECT a:65536 HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'CONNECT a:65616 HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | another Host value outside RFC 3986 | 37 | `b'GET / HTTP/1.1\r\nHost: a b\r\n\r\n'`, `b'TRACE * HTTP/1.1\r\nhost: \t a b\t\r\n\r\n'` |
| rejects | together: HTTP/1.2 to 1.9; a method other than the registered ones | 32 | `b"\r\nHseu~xC /HM~%6b/XO HTTP/1.9\r\nhost: %2b'4x%bE: \r\n\r\n"`, `b"&s+a' /Bx/T/xc%aB0 HTTP/1.2\r\nhOsT: \t 10.1.199.255 \r\n\r\n"` |
| rejects | together: a method other than the registered ones; a tab after a Content-Length or Transfer-Encoding value | 28 | `b'Rpz3% /AtS?l6z6)! HTTP/1.1\r\ncontent-length:  536603 \t \r\nhost:~V\r\n\r\n'`, `b'!$w^u8Y /ioiRO HTTP/1.1\r\nContent-Length: \t 148637 \t \r\nHost:!O(vL\t\r\n\r\n'` |
| rejects | together: an absolute-form target with no authority; a tab after a Content-Length or Transfer-Encoding value | 28 | `b'HEAD x:@eJ@?BcO$BZ@ HTTP/1.1\r\nHost: \t !l \t \r\nContent-Length: 838170\t\r\n\r\n'`, `b'TRACE ws:4%D2 HTTP/1.1\r\nHOST: Yeo.L%DB\r\ntransfer-encoding:chunked \t \r\n\r\n'` |
| accepts | Transfer-Encoding in HTTP/1.0 | 27 | `b'POST /a HTTP/1.0\r\nTransfer-Encoding: chunked\r\n\r\n'`, `b"POST /9:u HTTP/1.0\r\n'g+C: 1 \r\nhost: [Vb6a.,x4]\t\r\nTRANSFER-ENCODING: \r\n\r\n"` |
| accepts | other whitespace in the request line | 18 | `b'GET  /a HTTP/1.1\r\nHost: x\r\n\r\n'`, `b'DELETE  //9v513?2%b30 HTTP/1.1\r\nHost:v\t\r\n\r\n'` |
| rejects | together: the authority-form with a method other than CONNECT; a tab after a Content-Length or Transfer-Encoding value | 18 | `b"PUT %Ccd('3II.D-:443 HTTP/1.1\r\nhOsT: %aE3Mm%49.FED:0  \r\ncontent-length: 819795 \t \r\n\r\n"`, `b'\r\nPATCH 195.99.250.9:65535 HTTP/1.0\r\nhost:\t99.199.249.199\t\r\ncontent-length:\t159570 \t \r\n\r\n'` |
| rejects | together: HTTP/1.2 to 1.9; the authority-form with a method other than CONNECT | 17 | `b"DELETE tf=Qum.aJ'E.k3.: HTTP/1.2\r\nhOsT:\t255.10.100.99  \r\n\r\n"`, `b'DELETE [Ac6::cb1B:9f:570C:34e:e1:D]: HTTP/1.2\r\nhost:  BYrnc4i.~oCc(WS3\r\n\r\n'` |
| rejects | a scheme with a digit, "+", "-" or "." | 14 | `b"PATCH a+b.c-d://%B4'b@Fi.Tk2vEX.i9L:? HTTP/1.1\r\nHOST: hB$Aas.+Ro:80\t\r\n\r\n"`, `b'HEAD a+b.c-d://+B@199.250.199.200/SZ:j/?Ng HTTP/1.1\r\nHOST: \t y!U.,U&:31876  \r\n\r\n'` |
| rejects | together: a method other than the registered ones; an http or https target with no host | 14 | `b'BqUC https:?6x HTTP/1.1\r\nhost: eqlh.%deJD5t.f \t \r\n\r\n'`, `b'lqiqJg http:t%bAiU HTTP/1.1\r\nHOST:  : \r\nEpUr:*xt\r\n\r\n'` |
| rejects | together: an absolute-form target with no authority; a Transfer-Encoding list with empty elements | 14 | `b'\r\n\r\nHEAD x:7%14w%4e HTTP/1.1\r\n\|: \t y \r\nTRANSFER-ENCODING:  ,chunked \t \r\nHOST: \t 250.199.9.10  \r\n\r\n'`, `b'PATCH x:/l%dd HTTP/1.1\r\nHost: [v1Ad.j]  \r\ntransfer-encoding:  , chunkEd\t,\t, , \t\r\nK6$d: \t hI:~[\\\xc2h\xe6 \r'` |
| accepts | CONNECT with port 0 | 13 | `b'CONNECT a:0 HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'CONNECT a:00 HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | a target with a bad IP literal | 12 | `b'GET http://[1::2::3]/ HTTP/1.1\r\nHost: x\r\n\r\n'`, `b'CONNECT [fe80::1%25eth0]:80 HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | another target outside RFC 3986 | 12 | `b'GET /a#frag HTTP/1.1\r\nHost: x\r\n\r\n'`, `b'CONNECT ::1:80 HTTP/1.1\r\nHost: a\r\n\r\n'` |
| rejects | together: HTTP/1.2 to 1.9; an absolute-form target with no authority | 12 | `b'\r\nOPTIONS ws:/Ka@%B90/h_1/ HTTP/1.9\r\nhOsT:\t250.100.0.250:\r\n\r\n'`, `b'TRACE x:/%7E,nro HTTP/1.2\r\n4ajK5Q: \t \xe8Z9wb*VJ=\tmN^  \r\nhOsT: \t :80 \t \r\n\r\n'` |
| rejects | together: a method other than the registered ones; a Transfer-Encoding list with empty elements | 11 | `b'Kd //?uN HTTP/1.1\r\nhost:0.9.255.1  \r\nTransfer-Encoding: chunKED \t ,   \t ,    \r\nrNxb:  &\xeb2@m $<\xd4\| >b '`, `b'\r\n\r\nj /=nLs@/%47?Fu HTTP/1.1\r\nHost:[vFA.v&nb]\r\ntransfer-encoding:\t ,   ,\t \t ,  ChUNKed ,  \t ,  \r\nsW:'` |
| rejects | together: HTTP/1.2 to 1.9; a Transfer-Encoding list with empty elements | 10 | `b'DELETE /O~B%c1/dKo%AB4/k! HTTP/1.9\r\nTRANSFER-ENCODING:,chunked\t\r\nhOsT: L9L.h.48CrV \r\n\r\n'`, `b"PUT /e HTTP/1.2\r\nk`'FJape:\t BN7d\t\xed4 \r\ntransfer-encoding: \t ,chunked \t \r\nhOsT:  [VBa.EB.kX] \t \r\n\r\n"` |
| rejects | together: the authority-form with a method other than CONNECT; a Transfer-Encoding list with empty elements | 10 | `b'HEAD [4C12:dC9E:23:d9C:4:cc2:9a8:1]: HTTP/1.1\r\nHOST:\tYx.2%70z_v\t\r\n-w:\t\xc2\xa67W\t\r\ntransfer-encoding: \t , '`, `b"\r\nDELETE :0 HTTP/1.1\r\nhost:  +6R.%Cd.%6fIQ%B66 \r\nUBv*X's3: \t 2 \r\nuu2:\td  \r\nTransfer-Encoding:chunked"` |
| rejects | together: HTTP/1.2 to 1.9; an http or https target with no host | 9 | `b'POST http:f HTTP/1.2\r\nHost:vIhUT.%c2FY:0\t\r\n\r\n'`, `b'\r\nPOST https:?qt=*Ghj HTTP/1.2\r\nhost: U*v.MaAj8P\t\r\n\r\n'` |
| rejects | a Content-Length of 2^63 or more | 8 | `b"\r\n\r\nPOST /,ul*!m/'c_C:1 HTTP/1.1\r\ncontent-length:18446744073709551616 \r\nHOST:&XbMcKn.SJ7DOS' \t \r\n\r\n"`, `b'\r\nGET * HTTP/1.0\r\nContent-Length:  18446744073709551616 \r\nHost: [F867:011:d5aF:D:D82E:1:250.199.0.0]'` |
| rejects | together: HTTP/1.2 to 1.9; a tab after a Content-Length or Transfer-Encoding value | 8 | `b'\r\nHEAD //:%30Q-/)%DB/ HTTP/1.9\r\nHost: \t GLtJ \r\nCONTENT-LENGTH:230362\t\r\n\r\n'`, `b"\r\n\r\nDELETE /ak'f HTTP/1.2\r\nhost:  [fa44::55:48:caA:c:0E:1] \r\ncontent-length: \t 860082 \t \r\n\r\n"` |
| rejects | together: an http or https target with no host; a Transfer-Encoding list with empty elements | 7 | `b'POST https: HTTP/1.1\r\nhOsT: NTbxa&%41: \t \r\nTransfer-Encoding:  \t ,  , chunKed \t \r\n!m7xF:\tse>q\xceZ9\t\t\r\n'`, `b'PUT https:%04JI. HTTP/1.1\r\n8_Y108Er:\t ~_z\xa5=9\x83\t  \r\ntransfer-encoding: \t cHuNkEd\t,\t,\t\r\nhOsT: gnOr.BvZI'` |
| rejects | together: an http or https target with no host; a tab after a Content-Length or Transfer-Encoding value | 7 | `b'GET https:wh HTTP/1.0\r\nL2Cvjh!: \t \r\nHost: \t [::62:249.9.199.199] \t \r\nCONTENT-LENGTH: \t 52486\t\r\n\r\n'`, `b'\r\n\r\nDELETE https:nJ:T HTTP/1.1\r\nhost: \t 0Cz%23P3C1.%2DP1Oi;.BmRk:80\r\ncontent-length: 630101 \t \r\n\r\n'` |
| rejects | together: HTTP/1.2 to 1.9; a method other than the registered ones; a Transfer-Encoding list with empty elements | 6 | `b'+Q\| / HTTP/1.2\r\ntransfer-encoding:   \t \r\nTransfer-Encoding:, , \r\ntransfer-encoding: Chunked  \r\ntrans'`, `b"\r\n6 /b6j@=%bF/%B5/ShaGle?y;oKlu1 HTTP/1.2\r\n4H: z(+p =06'gp\xe2`10 \r\nHOST: [BF:C5Dd:8c:A:d85E:54c:63:ae4"` |
| accepts | CONNECT with an empty port | 5 | `b'CONNECT a: HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'CONNECT a: HTTP/1.1\r\nb6k:  "Z\ta>[dgT G 6?R\xde \r\nhost: \t jG2 \r\n\r\n'` |
| accepts | a Transfer-Encoding with another coding before chunked | 5 | `b'POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: gzip, chunked\r\n\r\n'`, `b"POST /0Kif:?yMyG' HTTP/1.1\r\nE8aPq9i:  Zb\\}\\2lb/iHws*\tFZ6 \r\nFgX*1RCK:J7\xbaDwIg@S,7Fq \r\ntransfer-encodin"` |
| accepts | a bare LF | 5 | `b'\n\r\nGET / HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'\nPOST /rrlr/fC HTTP/0.9\r\nhost: \t 131.199.1.1 \r\nY4GR:  Bp+\to=`. Q\x907! \r\nPFp9Fc1Q: +_oW+p \r\n\r\n'` |
| accepts | a target with a bad percent escape | 5 | `b'GET /%4g HTTP/1.1\r\nHost: x\r\n\r\n'`, `b'GET /%zz HTTP/1.1\r\nHost: x\r\n\r\n'` |
| rejects | together: HTTP/1.2 to 1.9; a method other than the registered ones; an absolute-form target with no authority | 5 | `b"KC6YG D0f:5A3:92a:977::EB07:8080 HTTP/1.9\r\n8pT:\tY~h\|_u;\xa0{s    \r\nhOsT: \t T1w.rKO'5mG\t\r\n\r\n"`, `b'x6TFP_X x:+?3 HTTP/1.9\r\n7:  \tl`2\xa3"i) \r\nGqOua:  \xd6R\xea*/VN+R\tue\t\xc9 \r\nHOST: ;cj6wm.QaXFrQ:65535 \r\njOU*Z:  '` |
| rejects | together: the authority-form with a method other than CONNECT; a method other than the registered ones; a Transfer-Encoding list with empty elements | 5 | `b'I TL9C$+%Af(:80 HTTP/1.1\r\nw: <ZM \r\nHost:  tK%5eU).0(1D0.zO%6dn \r\nTRANSFER-ENCODING: , ,chunked, ,\t\r\n'`, `b"lWl%c ;y.T:65535 HTTP/1.1\r\ntransfer-encoding: \t, \t \r\ntransfer-encoding: chunked\r\nhost: x&.'RGKJ1 \r\nt"` |
| no answer | a request line that is not three parts | 4 | `b''` |
| rejects | together: a method other than the registered ones; an absolute-form target with no authority; a tab after a Content-Length or Transfer-Encoding value | 4 | `b'\r\n\r\nb x: HTTP/1.1\r\nContent-Length: \t 0 \t \r\nhOsT: \t 255.9.99.250:443 \r\n\r\n'`, `b'connect JT:65616 HTTP/1.1\r\nhOsT:\t;FH%cF%08H:8080  \r\nContent-Length: \t 504745\t\r\nm$_+:\tJ@~[K*1gKnn  \r\n'` |
| rejects | together: a method other than the registered ones; an http or https target with no host; a Transfer-Encoding list with empty elements | 4 | `b'L2 https:p)@9p?;xu3E HTTP/1.1\r\nhost:\t[62d5:Da:2:d80:f1e:Af:Ad:Be0D] \r\nTransfer-Encoding: \t,\t ,\t,ChUn'`, `b'92g2%-q http:/Ber/ HTTP/1.1\r\ntransfer-encoding: \t,\t\r\ntransfer-encoding: CHunked \r\ntransfer-encoding:'` |
| accepts | a Transfer-Encoding with another coding before chunked, over two or more lines | 3 | `b'POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: gzip\r\nTransfer-Encoding: chunked\r\n\r\n'`, `b'CONNECT Z.F.7K;5Ta=s:20041 HTTP/1.1\r\nHost:\t100.10.0.99: \r\nTRANSFER-ENCODING:  chunked chunked \r\n9:j,'` |
| accepts | a Transfer-Encoding with no coding | 3 | `b'POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding:\r\n\r\n'`, `b"CONNECT :80 HTTP/1.1\r\nmIZ'NoYQ: p<\x8e \r\ntransfer-encoding:  , \r\nVWr:\t#J.@jf\xcbr  $-q#\x8b X\xea5_ \r\nw%_`QUz:]i"` |
| accepts | no Host, in HTTP/1.1 to 1.9 | 3 | `b'CONNECT [7c:bBa:0043:40b4:565:D36D:B61c:0Ca]:5240 HTTP/1.1\r\n\r\n'`, `b'CONNECT xmF%15yMdW:65535 HTTP/1.1\r\nl%:\x9f#\xf3Ax"/\x835JZ=\x890(\t\t\r\n*Ty:\t "bbH\xe2Ps \r\n\r\n'` |
| rejects | together: HTTP/1.2 to 1.9; a method other than the registered ones; an http or https target with no host | 3 | `b"cL.8zs#P http:+C?%9615jH HTTP/1.2\r\nhost:  IS0SBkZ'.Tm.,:0 \t \r\n\r\n"`, `b'!BiwDLqB https:Tx HTTP/1.9\r\nHOST: [::8e:eC:d8c4:afF]:65535 \r\n3i76: \t = \r\nbr: \t Zo\|\x8aDR 245-c\\ \x8dWUc\xb0B\t'` |
| rejects | together: HTTP/1.2 to 1.9; a scheme with a digit, "+", "-" or "." | 3 | `b"HEAD a+b.c-d://:dE@ HTTP/1.9\r\npk:  ywJ\x91[[?\xea*^#  \r\nTI30xu':  F9b^y8\xd1#)z\r\nSaVag5: f?A \t \r\nhOsT:\t[FFD::"`, `b'OPTIONS a+b.c-d://B(:443/y5/e?%33WU HTTP/1.9\r\ncontent-length: 248636 \r\nhost:H_T%dD.;IWeM.dwnx1d!%9e:'` |
| rejects | together: HTTP/1.2 to 1.9; an absolute-form target with no authority; a tab after a Content-Length or Transfer-Encoding value | 3 | `b'\r\nPUT ws:q HTTP/1.9\r\nCONTENT-LENGTH:303352 \t \r\nhost: [b:6b7f:2::]:0\t\r\n\r\n'`, `b'POST AE3:DD::8:443 HTTP/1.9\r\nS^Oam:  yE)Y \r\nContent-Length: 886115 \t \r\nHost:d6ydrp.XK.7:51147\r\n\r\n'` |
| rejects | together: HTTP/1.2 to 1.9; the authority-form with a method other than CONNECT; a method other than the registered ones | 3 | `b'$kgNREP0 DM%b1UhP:8080 HTTP/1.2\r\nhOsT: 6%2D;V0Cd.T;7m+W4.p,8x~uS%8e:\t\r\n\r\n'`, `b"l :443 HTTP/1.9\r\nrDt:\tgzZ!v:Lf[\x8d=\xcb8W\t\r\nHOST: ,f:80\r\n&gKw: WWMl\xd1o*'szw:  \r\nv-:  V:+o\x9b\xa0Ya \t \r\n\r\n"` |
| rejects | together: HTTP/1.2 to 1.9; the authority-form with a method other than CONNECT; a method other than the registered ones; a tab after a Content-Length or Transfer-Encoding value | 3 | `b'cqqAt+ %c0wUi.%b7c,Xj.kj7Mj2iu:443 HTTP/1.2\r\nhost:100.10.1.250 \t \r\ncontent-length:  338980 \t \r\n\r\n'`, `b'Connect %68Ey;(kN!.%0FU4:443 HTTP/1.2\r\nhost:7gcg%ef.NRC8M\t\r\n_Wq_:  \xad2)T\xb6wnjQf\xa7\xb6&V/-\xee  \r\ntransfer-enc'` |
| rejects | together: a method other than the registered ones; an absolute-form target with no authority; a Transfer-Encoding list with empty elements | 3 | `b"'^x2pX ws:u:: HTTP/1.1\r\nTRANSFER-ENCODING:   \t , cHunked ,\t,\t \r\nz0L: \t  \r\nR2: ;7\xcbb;zV`F v.<L\x861tnL \t "`, `b'xJFLCJq a+b.c-d: HTTP/1.1\r\nTRANSFER-ENCODING:\t \t \r\nJO: \xd8 [\xa2=@\t\xcb](sV-b%  \r\ntransfer-encoding:\tChunked'` |
| rejects | together: the authority-form with a method other than CONNECT; a method other than the registered ones; a tab after a Content-Length or Transfer-Encoding value | 3 | `b'B.m`$ [1df1:Feb2:cD3:FF:cD::]:8392 HTTP/1.0\r\nContent-Length:\t0 \t \r\n\r\n'`, `b'aL 199.10.1.199:80 HTTP/1.1\r\nHost:200.0.250.196 \r\nCONTENT-LENGTH:\t736918\t\r\n\r\n'` |
| accepts | a bare CR | 2 | `b'\r\n\rHEAD /%F6!m/M:?&xg HTTP/1.0\r\nCONTENT-LENGTH: 501240 \r\n7t$S+D:  ^ YZ)Z\t\r\n-: \t w3\t\r\nH2:   \r\n\r\n'`, `b"\r\r\nDELETE * HTTP/1.1\r\nBe_ab:\t.\r\nG&:  \r\nFBl\|Ys: \t 8/ 1\xe0e~ \r\nCONTENT-LENGTH: \t 0 \r\nhOsT:\t'uy%a45-9:808"` |
| no answer | empty lines before the request line | 2 | `b'\r\n'` |
| rejects | together: HTTP/1.2 to 1.9; a method other than the registered ones; an absolute-form target with no authority; a Transfer-Encoding list with empty elements | 2 | `b'S6GRU!TL a+b.c-d: HTTP/1.2\r\nhOsT: \t em4b.j;J_k.q:80  \r\n-sL:  i\xf8GMYZ\tKe\t\r\ntransfer-encoding:  , ,    '`, `b"Nk1- a+b.c-d:mx?s= HTTP/1.9\r\naAC: \t \t\r\nY'ro*: \t a\xa4j$.AB \t \r\nhost: \t [6CE:9A:04AE:3:A5:9CB:77.10.250."` |
| rejects | together: a method other than the registered ones; a scheme with a digit, "+", "-" or "." | 2 | `b'y-yk a+b.c-d://[7AE2::D2]:38737/.:d/7EW0/%7e0%b0:V: HTTP/1.1\r\nhost:\t100.248.255.200 \r\ncontent-length'`, `b'aKEBlT a+b.c-d://)Dmc0/%Fa:%7bJ%F8/q HTTP/1.1\r\nHmI:\tnk8i\x9c\xef  \r\nhOsT:  LU+%ec%ce\r\nBluMTKS:\t\t\r\n._bW4R: '` |
| accepts | a Transfer-Encoding whose last coding is not chunked | 1 | `b'CONNECT [vE.Q)]:00000000000000000000032110 HTTP/1.1\r\ntransfer-encoding: chunked chunked \r\no: \t \r\nemy'` |
| accepts | a Transfer-Encoding with no coding, over two or more lines | 1 | `b'TRACE /-C18/v?iZ_L HTTP/1.1\r\nTRANSFER-ENCODING:  \t \r\n$: %_  \r\nPJ:\|  \r\nHost:M.c.9&X%CF&d \t \r\ntransfer'` |
| accepts | a request line that is not three parts | 1 | `b'\r\n\r\nGET /-/%15Rg0?-UUsX%43.&HTTP/1.1\r\nHOST: 250.249.9.0 \r\nE#wn5.6: \t ~Xq%Jy:D<\t2/"&\r\n\r\n'` |
| accepts | chunked twice, over two or more lines | 1 | `b'PATCH https://249.199.10.0:80/!=t1d/ HTTP/1.1\r\nd32Dmxs: \t \xac\t\r\nTRANSFER-ENCODING:chunked\t\r\ntransfer-e'` |
| rejects | together: HTTP/1.2 to 1.9; a Content-Length of 2^63 or more | 1 | `b"GET /=Nu%e9//IC:u*?X'pWm%E8SY HTTP/1.9\r\nhost: [D:C:ED::] \t \r\ncontent-length:  18446744073709551616\t\r"` |
| rejects | together: HTTP/1.2 to 1.9; a method other than the registered ones; a tab after a Content-Length or Transfer-Encoding value | 1 | `b'\r\n&%$ //!H/p_ HTTP/1.2\r\nCONTENT-LENGTH:  450377 \t \r\nhost: 99.175.99.250\r\n\r\n'` |
| rejects | together: HTTP/1.2 to 1.9; a method other than the registered ones; an absolute-form target with no authority; a tab after a Content-Length or Transfer-Encoding value | 1 | `b'#A2Q~v\|J a+b.c-d: HTTP/1.2\r\nContent-Length:  805224 \t \r\nhOsT: fhg!.=S2.%09V,_) \t \r\nD6: \t 2>v( \r\nN: \xe7'` |
| rejects | together: HTTP/1.2 to 1.9; a scheme with a digit, "+", "-" or "."; a tab after a Content-Length or Transfer-Encoding value | 1 | `b"HEAD a+b.c-d://200.255.9.9:/1%09/:3:T HTTP/1.9\r\nuw&xD:\t\t'r{x \t \r\nbO:  4h0g#r}5_ \r\nHOST:\t[C87::Ec]\t\r\n"` |
| rejects | together: HTTP/1.2 to 1.9; an absolute-form target with no authority; a Content-Length of 2^63 or more | 1 | `b'OPTIONS a+b.c-d:c?QvJ%b5*_ HTTP/1.9\r\nCej.vBv8:\t\xd2N:A-;=$\x9e\\4  \r\nContent-Length:\t18446744073709551616\t\r'` |
| rejects | together: HTTP/1.2 to 1.9; the authority-form with a method other than CONNECT; a Transfer-Encoding list with empty elements | 1 | `b'PATCH xE.!Cqr.1(%94Z:8080 HTTP/1.9\r\nHost:\tjVy).naTuk%fa \r\nTRANSFER-ENCODING: chUnkEd \t , \r\n*WvTsa:\t '` |
| rejects | together: HTTP/1.2 to 1.9; the authority-form with a method other than CONNECT; a method other than the registered ones; a Transfer-Encoding list with empty elements | 1 | `b'6#Lyao .~SsiU.%fC:8080 HTTP/1.9\r\nq6~5:\tU\xc3"HUT\t\t\r\nK-BK: ^+AZVs 6~Sks, \r\ntransfer-encoding: \t ,chUnked'` |
| rejects | together: HTTP/1.2 to 1.9; the authority-form with a method other than CONNECT; a tab after a Content-Length or Transfer-Encoding value | 1 | `b'OPTIONS %D8d:47692 HTTP/1.2\r\nG: \t  \t \r\n^WgZw.b:\t-& \r\nHOST:  zY4%5EnsB.D.%e4nawb \r\nX6:~ \r\nQRW8fiS3: \xbc'` |
| rejects | together: a method other than the registered ones; a Content-Length of 2^63 or more | 1 | `b'+l&*z!Cz //lfj2?n6iW HTTP/1.1\r\nfPPT7+P^: TRM"\xf92C\' \t \r\nSV: z L\xd3_\r\nCONTENT-LENGTH: 1844674407370955161'` |
| rejects | together: a method other than the registered ones; a scheme with a digit, "+", "-" or "."; a Transfer-Encoding list with empty elements | 1 | `b"1zC3 a+b.c-d://!;w@255.199.9.255:80/3I?HZj.6 HTTP/1.1\r\n_fT7aDrG: ;N$\xd8\xf7rD=ds\xc72\xde'wT \t \r\nTransfer-Encod"` |
| rejects | together: a scheme with a digit, "+", "-" or "."; a Transfer-Encoding list with empty elements | 1 | `b'\r\n\r\nPUT a+b.c-d://9:65535/; HTTP/1.1\r\ntransfer-encoding:  ,  chuNkEd \r\n0!K`EK!:  1x\xc0[hyXOIJ5tw\xa3NIs0\\'` |

## Go go1.24.7 net/http

- Heads sent: 5991
- Same verdict: 4722 (1414 both accept, 3308 both reject)
- Different verdict: 1265 (479 it accepts and this project rejects, 786 it rejects and this project accepts)
- No answer: 4
- Body lengths compared, where both accept: 1414. Of those, 967 have no body and 447 a non-zero length (374 by Content-Length, 73 chunked). 1414 read the same length and 0 another.
- Not compared, where both accept: 0 with a Content-Length above 1,000,000, and 0 whose answer has no count.

The heads it rejects and this project accepts, by the feature whose change makes it accept them: alone, or together with other changes.

| Feature | Alone | With others |
| --- | --- | --- |
| empty lines before the request line | 325 | 90 |
| the authority-form with a method other than CONNECT | 192 | 70 |
| a Transfer-Encoding list with empty elements | 135 | 54 |
| a percent escape of an ASCII octet in the host of the target | 17 | 6 |
| a Content-Length of 2^63 or more | 7 | 4 |

Where it differs from this project (the two shortest examples):

| It | Category | Heads | Examples |
| --- | --- | --- | --- |
| rejects | empty lines before the request line | 325 | `b'\r\n\r\nGET / HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'\r\n\r\nOPTIONS * HTTP/1.1\r\nHost:;1i.B.i4G\r\n\r\n'` |
| rejects | the authority-form with a method other than CONNECT | 192 | `b'OPTIONS ,.d.yK2+eOb:0 HTTP/1.1\r\nhost: M0Q\t\r\n\r\n'`, `b'OPTIONS [4A::42db]:443 HTTP/1.1\r\nhost: -WXK: \r\n\r\n'` |
| accepts | a Host value with a bad IP literal | 171 | `b'GET / HTTP/1.1\r\nHost: ::1\r\n\r\n'`, `b'GET / HTTP/1.1\r\nHost: fe80::1\r\n\r\n'` |
| rejects | a Transfer-Encoding list with empty elements | 135 | `b'POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked,\r\n\r\n'`, `b'POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: , chunked\r\n\r\n'` |
| accepts | Transfer-Encoding in HTTP/1.0 | 94 | `b'POST /a HTTP/1.0\r\nTransfer-Encoding: chunked\r\n\r\n'`, `b'POST /a HTTP/1.0\r\nTransfer-Encoding: chunked,\r\n\r\n'` |
| accepts | a bare LF | 53 | `b'POST /a HTTP/1.1\r\nHost: x\nTransfer-Encoding: chunked\r\n\r\n'`, `b'GET /o1$)%ec!//,~RD2U HTTP/1.1\nHost: \t %CCC.ZI.$.fxBw2(:  \r\n\r\n'` |
| rejects | together: empty lines before the request line; the authority-form with a method other than CONNECT | 48 | `b'\r\nPATCH )oHQyK:80 HTTP/1.1\r\nHOST: y5.s \t \r\n\r\n'`, `b'\r\nGET 9.9.255.250:0 HTTP/1.1\r\nhost:0.1.10.9\r\n\r\n'` |
| accepts | CONNECT whose target is not a host and port | 32 | `b'CONNECT * HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'CONNECT / HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | a folded line (obs-fold) | 31 | `b'POST /a HTTP/1.1\r\nHost: x\r\nX: y\r\n Transfer-Encoding: chunked\r\n\r\n'`, `b'PUT a+b.c-d:/j+* HTTP/1.1\r\nhOsT:  \r\n folded\r\ncontent-length: 72693 \t \r\n\r\n'` |
| rejects | together: empty lines before the request line; a Transfer-Encoding list with empty elements | 30 | `b'\r\n\r\nHEAD x:7%14w%4e HTTP/1.1\r\n\|: \t y \r\nTRANSFER-ENCODING:  ,chunked \t \r\nHOST: \t 250.199.9.10  \r\n\r\n'`, `b'\r\n\r\nj /=nLs@/%47?Fu HTTP/1.1\r\nHost:[vFA.v&nb]\r\ntransfer-encoding:\t ,   ,\t \t ,  ChUNKed ,  \t ,  \r\nsW:'` |
| accepts | CONNECT with a port above 65535 | 29 | `b'CONNECT a:65536 HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'CONNECT a:65616 HTTP/1.1\r\nHost: a\r\n\r\n'` |
| rejects | together: the authority-form with a method other than CONNECT; a Transfer-Encoding list with empty elements | 18 | `b'GET :10667 HTTP/1.9\r\nCRiVcO0: \t <7H\xbf  \r\nXH:   \r\ntransfer-encoding: , ,  cHunked \r\nhost:99.1.199.1 \r\n'`, `b'PATCH xE.!Cqr.1(%94Z:8080 HTTP/1.9\r\nHost:\tjVy).naTuk%fa \r\nTRANSFER-ENCODING: chUnkEd \t , \r\n*WvTsa:\t '` |
| rejects | a percent escape of an ASCII octet in the host of the target | 17 | `b'DELETE ws://Rl8c,9.u5(d%6C/2/xi2Y/~Cq_%Bc@/ HTTP/1.1\r\nhost:  eYb.o:0\t\r\n\r\n'`, `b'rs_!UKd! https://YD;hx.mH$NJ%19~U.snp0:8080 HTTP/1.0\r\nVZ$.e: Un\xec_\xaa\x81;1\\, \r\nhost: 0.4Lm.ukMG%E6f\r\n\r\n'` |
| accepts | another Host value outside RFC 3986 | 16 | `b'AWAT&Z https:/RfJK/o/v5 HTTP/1.0\r\nI7qIaQ&:\t5[iyA \r\nHost: h:p\r\n\r\n'`, `b'OPTIONS D:eEDd:04A:b9:BBa6:02:0Ad:da:80 HTTP/1.1\r\nHOST: h:p \r\n\r\n'` |
| accepts | Transfer-Encoding with Content-Length | 14 | `b'POST /a HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nTransfer-Encoding: chunked\r\n\r\n'`, `b'POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nContent-Length: 5\r\n\r\n'` |
| accepts | a target with a bad IP literal | 12 | `b'GET http://[1::2::3]/ HTTP/1.1\r\nHost: x\r\n\r\n'`, `b'CONNECT [fe80::1%25eth0]:80 HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | CONNECT with port 0 | 8 | `b'CONNECT a:0 HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'CONNECT a:00 HTTP/1.1\r\nHost: a\r\n\r\n'` |
| rejects | a Content-Length of 2^63 or more | 7 | `b"GET /=Nu%e9//IC:u*?X'pWm%E8SY HTTP/1.9\r\nhost: [D:C:ED::] \t \r\ncontent-length:  18446744073709551616\t\r"`, `b'POST /2 HTTP/1.1\r\nCONTENT-LENGTH:\t18446744073709551616  \r\nU5GT~pV:  z\r\nuq_zY1jl:$Y\xe8 \r\nPFuiWhS2:\t \t \r'` |
| accepts | another target outside RFC 3986 | 6 | `b'GET /a#frag HTTP/1.1\r\nHost: x\r\n\r\n'`, `b'CONNECT ::1:80 HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | a target with octets above 0x7F | 4 | `b"HEAD //%Ea%1CK\xd2L~/bN/,, HTTP/1.2\r\nHost:  Qsh.y7&  \r\n4\|EF:\t \xf2'\xab.'e\tN\t\r\n\r\n"`, `b'~* /tO/\xde HTTP/1.9\r\n3#_`NHKN: \t {\xba}!~Zh;^Fi\x85^\r\nhost:[::0EB2:0a:038] \t \r\n3:!?>{O+Q\r\n\r\n'` |
| accepts | two Content-Length lines with the same value | 4 | `b'POST /a HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nContent-Length: 5\r\n\r\n'`, `b'DELETE /)/C HTTP/1.1\r\nhOsT:\t[vAB.sb] \r\nContent-Length: \t 55864 \r\nContent-Length: \t 55864 \r\n\r\n'` |
| no answer | a request line that is not three parts | 4 | `b''` |
| rejects | together: empty lines before the request line; a Content-Length of 2^63 or more | 4 | `b"\r\n\r\nPOST /,ul*!m/'c_C:1 HTTP/1.1\r\ncontent-length:18446744073709551616 \r\nHOST:&XbMcKn.SJ7DOS' \t \r\n\r\n"`, `b'\r\nGET * HTTP/1.0\r\nContent-Length:  18446744073709551616 \r\nHost: [F867:011:d5aF:D:D82E:1:250.199.0.0]'` |
| rejects | together: empty lines before the request line; a percent escape of an ASCII octet in the host of the target | 4 | `b"\r\nCONNECT %B3%7ET:20987 HTTP/1.1\r\nhost: \t %Fe.B:0  \r\n9Do025f': @ 2b  \r\n\r\n"`, `b"\r\n\r\nPUT https://%0BQ.2C/%b4)6$fZ/8D/,y/'T%Da%D5@ HTTP/1.1\r\nHOST: \t JiG:443 \t \r\n\r\n"` |
| rejects | together: empty lines before the request line; the authority-form with a method other than CONNECT; a Transfer-Encoding list with empty elements | 4 | `b"\r\nDELETE :0 HTTP/1.1\r\nhost:  +6R.%Cd.%6fIQ%B66 \r\nUBv*X's3: \t 2 \r\nuu2:\td  \r\nTransfer-Encoding:chunked"`, `b"\r\n\r\nConnect %5b%47k=.*at.Ibb).:443 HTTP/1.1\r\nhost:  2G.==XB'w..uk%ebNEz6N:80\r\nTransfer-Encoding:\t, \t"` |
| accepts | CONNECT with an empty port | 3 | `b'CONNECT a: HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'CONNECT a: HTTP/1.1\r\nb6k:  "Z\ta>[dgT G 6?R\xde \r\nhost: \t jG2 \r\n\r\n'` |
| accepts | no Host, in HTTP/1.1 to 1.9 | 2 | `b'CONNECT [7c:bBa:0043:40b4:565:D36D:B61c:0Ca]:5240 HTTP/1.1\r\n\r\n'`, `b'CONNECT [4C::9:e3d6:1CB0:62]:37642 HTTP/1.1\r\naTBg: \\( \r\nCONTENT-LENGTH:193114 \r\n\r\n'` |
| rejects | together: a percent escape of an ASCII octet in the host of the target; a Transfer-Encoding list with empty elements | 2 | `b'GET http://%7DDLl1.mTe.;jSon%7a:65535/!/(KZ/8/HV$j_7 HTTP/1.1\r\nHOST: R+q9.=%be.%bc72M~T7Z\t\r\nIZ5: \xae;l'`, `b'PUT gB+%7bgo.6F5:65535 HTTP/1.1\r\nTransfer-Encoding:  ,  \r\nTRANSFER-ENCODING: Chunked  \r\nTRANSFER-ENC'` |

## h11 0.16.0

- Heads sent: 5991
- Same verdict: 4560 (1630 both accept, 2930 both reject)
- Different verdict: 1427 (857 it accepts and this project rejects, 570 it rejects and this project accepts)
- No answer: 4
- Body lengths compared, where both accept: 1623. Of those, 1104 have no body and 519 a non-zero length (437 by Content-Length, 82 chunked). 1623 read the same length and 0 another.
- Not compared, where both accept: 7 with a Content-Length above 1,000,000, and 0 whose answer has no count.

The heads it rejects and this project accepts, by the feature whose change makes it accept them: alone, or together with other changes.

| Feature | Alone | With others |
| --- | --- | --- |
| empty lines before the request line | 381 | 34 |
| a Transfer-Encoding list with empty elements | 155 | 34 |

Where it differs from this project (the two shortest examples):

| It | Category | Heads | Examples |
| --- | --- | --- | --- |
| rejects | empty lines before the request line | 381 | `b'\r\n\r\nGET / HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'\r\n\r\nOPTIONS * HTTP/1.1\r\nHost:;1i.B.i4G\r\n\r\n'` |
| accepts | a major version other than 1 | 224 | `b'GET / HTTP/2.0\r\nHost: a\r\n\r\n'`, `b'TRACE /y+:p HTTP/0.9\r\nHost: \t (pd.\r\n\r\n'` |
| accepts | a Host value with a bad IP literal | 209 | `b'GET / HTTP/1.1\r\nHost: ::1\r\n\r\n'`, `b'GET / HTTP/1.1\r\nHost: fe80::1\r\n\r\n'` |
| rejects | a Transfer-Encoding list with empty elements | 155 | `b'POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked,\r\n\r\n'`, `b'POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: , chunked\r\n\r\n'` |
| accepts | a bare LF | 75 | `b'OPTIONS /%6c%72m/j@/KNzsj HTTP/1.2\n\r\n'`, `b'POST /a HTTP/1.1\r\nHost: x\nTransfer-Encoding: chunked\r\n\r\n'` |
| accepts | another Host value outside RFC 3986 | 65 | `b'GET / HTTP/1.1\r\nHost: a b\r\n\r\n'`, `b'.Y*gv / HTTP/1.1\r\nhost:\t@x\t\r\n\r\n'` |
| accepts | a folded line (obs-fold) | 51 | `b'DELETE /%Ffb)%A5rN/_:M* HTTP/1.0\r\nhOsT: [::1F9]\r\n\tfolded\r\n\r\n'`, `b'PATCH /v/~/0/@vb%AcV?1fs/ HTTP/1.1\r\nHost: \t =o7ms \r\n\tfolded\r\n\r\n'` |
| accepts | CONNECT whose target is not a host and port | 38 | `b'CONNECT * HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'CONNECT / HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | CONNECT with a port above 65535 | 35 | `b'CONNECT a:65536 HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'CONNECT a:65616 HTTP/1.1\r\nHost: a\r\n\r\n'` |
| rejects | together: empty lines before the request line; a Transfer-Encoding list with empty elements | 34 | `b'\r\n\r\nHEAD x:7%14w%4e HTTP/1.1\r\n\|: \t y \r\nTRANSFER-ENCODING:  ,chunked \t \r\nHOST: \t 250.199.9.10  \r\n\r\n'`, `b'\r\n\r\nj /=nLs@/%47?Fu HTTP/1.1\r\nHost:[vFA.v&nb]\r\ntransfer-encoding:\t ,   ,\t \t ,  ChUNKed ,  \t ,  \r\nsW:'` |
| accepts | a target with a bad IP literal | 29 | `b'GET http://[1::2::3]/ HTTP/1.1\r\nHost: x\r\n\r\n'`, `b'CONNECT [fe80::1%25eth0]:80 HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | a Content-Length list of equal values | 26 | `b'POST /a HTTP/1.1\r\nHost: x\r\nContent-Length: 5, 5\r\n\r\n'`, `b'HEAD m=U%a6J:8080 HTTP/1.2\r\nContent-Length: 5,5  \r\n\r\n'` |
| accepts | Transfer-Encoding in HTTP/1.0 | 24 | `b'POST /a HTTP/1.0\r\nTransfer-Encoding: chunked\r\n\r\n'`, `b'OPTIONS /!@/9/FR HTTP/1.0\r\nA:\t}98&!_\t?\|F \t \r\nCm: \t  \r\nTRANSFER-ENCODING: Chunked \r\n\r\n'` |
| accepts | another target outside RFC 3986 | 20 | `b'GET /a#frag HTTP/1.1\r\nHost: x\r\n\r\n'`, `b'CONNECT ::1:80 HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | Transfer-Encoding with Content-Length | 13 | `b'POST /a HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nTransfer-Encoding: chunked\r\n\r\n'`, `b'POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nContent-Length: 5\r\n\r\n'` |
| accepts | a target with a bad percent escape | 12 | `b'GET /%4g HTTP/1.1\r\nHost: x\r\n\r\n'`, `b'GET /%zz HTTP/1.1\r\nHost: x\r\n\r\n'` |
| accepts | no Host, in HTTP/1.1 to 1.9 | 11 | `b'TRACE * HTTP/1.9\r\n\r\n'`, `b'DELETE 5u.%7B.0ts3~di:0 HTTP/1.9\r\nQVH:\t \r\n\r\n'` |
| accepts | CONNECT with port 0 | 8 | `b'CONNECT a:0 HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'CONNECT a:00 HTTP/1.1\r\nHost: a\r\n\r\n'` |
| accepts | another control octet in a field line | 7 | `b'GET /;8Q HTTP/1.9\r\nhOsT:  D\x02Ji%faw-.KjBOjQN \r\n4R: $\\CN  \r\nGGk3qYH:\tTkD.\x81+\t\r\n\r\n'`, `b'HEAD / HTTP/2.0\r\ncontent-length:\t830563 \t \r\nHOST:  [d::2cf:71A:cEA4:199.255.200.199] \t\x08 \r\n\r\n'` |
| accepts | two Content-Length lines with the same value | 6 | `b'POST /a HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nContent-Length: 5\r\n\r\n'`, `b'DELETE /)/C HTTP/1.1\r\nhOsT:\t[vAB.sb] \r\nContent-Length: \t 55864 \r\nContent-Length: \t 55864 \r\n\r\n'` |
| accepts | CONNECT with an empty port | 4 | `b'CONNECT a: HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'CONNECT a: HTTP/1.1\r\nb6k:  "Z\ta>[dgT G 6?R\xde \r\nhost: \t jG2 \r\n\r\n'` |
| no answer | a request line that is not three parts | 4 | `b''` |
