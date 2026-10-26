# Cross-check with other HTTP parsers

Written by `tests/cross_check.py`, a one-off comparison that is not part of the verified bar. RFC 9112 lets a recipient repair some malformed heads instead of rejecting them, so a difference here is a different choice, not always an error.

- Heads: the first 5991 of the differential tests, seed 20261025

## Node v22.22.0 (llhttp)

- Same verdict, accept or reject: 4148; of those accepted with a body count in the answer, 616 read the same body length and 0 another
- Different verdict: 1251
- No answer: 5
- Not sent, since the body would be over 64 KiB: 587

Where it differs from this project, by the first category that fits the head:

| It | Category | Heads | Example |
| --- | --- | --- | --- |
| rejects | a method other than the registered ones | 243 | `b'3I0\| /U:L/0g%bb/1ODD?@m%BD%F1%8b HTTP/1.1\r\n6:  \xe6& o@C]4=sIv*]!9`b\t\r\n6:  \xe6& o@C]4=sIv*]!9`b'`, `b'qgd%% http:/Lg-/?P HTTP/1.1\r\nl$b+S3*:  \xec \xdf>\xff[\tpr\r\nu:  \t \r\nHost: [vf.=KqwR]:0\t\r\n\r\n'` |
| rejects | empty lines before the request line | 190 | `b'\r\n\r\nOST /17&l/0:J%C3/@V:Vb,/c HTTP/1.1\r\nR: JO \r\nHost: %1fy%07E.5~Oi=3H:80 \r\n\r\nGET / HTTP/1'`, `b"\r\n52 9.83.10.255:80 HTTP/1.1\r\nG': e-\tu \r\nhOsT: \t C8EP*-NO.3%65f&.eA!u\t\r\n\r\nGET / HTTP/1.1\r\n"` |
| rejects | an absolute-form target with no authority | 180 | `b'DELETE x: HTTP/1.1\r\n%nsF:KIw}Pt\xd1WRIV\xee:9C\x82-  \r\nhOsT: \t c%Ea.aB~H.v%DE%17\t\r\n\r\n'`, `b'DELETE x: HTTP/1.1\r\nKuZ: \\hT1`ek\|H^  \r\ns:  \t \r\nHOST:[::Ad6E:03:Fd:D4] \r\n#: nwgN`CE  4TD1\xbdm'` |
| rejects | another version: 1.2 to 1.9 | 144 | `b'GET / HTTP/1.2\r\nHost: a\r\n\r\n'`, `b"PATCH x://y9PQ3mW:80/c'kMm?Fd HTTP/1.9\r\nhH7hzs8*: X_~\xf47@\xabN2L%/*Gqe1i?\r\n2Zabwc:\t($  3`G'atg"` |
| rejects | the authority-form with a method other than CONNECT | 121 | `b'GET [::0cC:F7D3:F6]:443 HTTP/1.1\r\nHOST: \t %8D8o \r\n\r\n)'`, `b'OPTIONS Q5B%a1M.dZ%EB:53707 HTTP/1.1\r\nD2M&y#: \t w\xa5*s\xebH6!og\r\nlEdoMZg: E V&i\xa1dF\xec6~Ubu$\x98\xdfl \r\n'` |
| accepts | another version: not HTTP/1.x | 105 | `b'GET / HTTP/2.0\r\nHost: a\r\n\r\n'`, `b'CONNECT /kK%dDl/1?xu HTTP/0.9\r\nO~7ue: \t\r\n8`t\|m.*: \\\t7\tG3/\xeaI \tO?\xc8[)  \r\nhost:\t199.255.99.255'` |
| accepts | two Host lines | 50 | `b'GET / HTTP/1.1\r\nHost: a\r\nHost: a\r\n\r\n'`, `b'GET / HTTP/1.0\r\nHost: a\r\nHost: b\r\n\r\n'` |
| accepts | empty lines before the request line | 43 | `b'\r\nCONNECT /,wmIQZ/%b7.O/_ HTTP/1.1\r\nHost: 0T(_B.q5jw-:65535 \r\n3ZOVuH:\tJBVmF~uS0mg\xb5\xe1\t\r\ntran'`, `b'\r\nCONNECT /v%aC0@T. HTTP/1.0\r\nTransfer-Encoding: xchunked  \r\nhOsT: -%7Eb_%C9.0i  \r\nhost: 1'` |
| accepts | a Host value outside RFC 3986 | 41 | `b'GET / HTTP/1.1\r\nHost: a b\r\n\r\n'`, `b'DELETE /_/Di./@o HTTP/1.1\r\nhOsT: h:p \r\n\r\nGET / HTTP/1.1\r\n\r\n\r\n'` |
| rejects | obs-text in a field value | 41 | `b'HEAD /S:nc%6F/:/ HTTP/1.1\r\nW: \t 49+\\io}t?d@~+Y;3[of \r\nW: \t 49+\\io}t?d@~+Y;3[of \r\nHOST:\t249'`, `b'GET /@/VTki3F/@/N%CbSa=: HTTP/1.1\r\nTRANSFER-ENCODING:\tchunked \t \r\nhOsT:2-- \r\nLHI: Z_i M9[='` |
| accepts | CONNECT with a target other than the authority-form | 37 | `b'CONNECT /%8by!hF/%40)D%bb//bN%bDEDs HTTP/1.1\r\n%p: %\x86+6\xc1j/]17~n+  Z!h+1\t\r\nHOST: 701s_t.m8(H'`, `b"CONNECT /NP/uq+ HTTP/1.1\r\n.H:  ve\xb2\txd\xbc\xb7_'\xc2`P 1JG)  \r\nTransfer-Encoding: chunked \r\nHost: [:"` |
| rejects | other | 10 | `b'DELETE http://99.1.9.255/(ZV.&$/ HTTP/1.0\r\ndDKUTl: +M\t71h9W@m["%K1 \r\nAj:    \r\nHost: tfj*o%'`, `b'GET /A/+a*Y7?X+?y. HTTP/1.1\r\nhOsT:\tZ*bxDE3.IYjT%137)a \t \r\nTRANSFER-ENCODING:\tChunked\t\r\n\r\n\x94'` |
| accepts | other whitespace in the request line | 9 | `b'GET  /a HTTP/1.1\r\nHost: x\r\n\r\n'`, `b'OPTIONS  * HTTP/1.1\r\n-C&: \t ?P/ vO;n/09\t> #\|u\xf8Q \r\nhost:p+zWt.ZuOxjZBo.)DB)%5B_Qm:65810 \r\n\r'` |
| accepts | an absolute-form target with no authority | 8 | `b'CONNECT a+b.c-d:/4Y%1F*/sRt HTTP/1.0\r\nhost:[1:dc8A:a1:D9b::6A1:A:0.250.250.255]:443\t\r\nnnv!'`, `b'CONNECT a+b.c-d:(SK HTTP/1.1\r\nLO$sen:\xd7wA;wO^^CZ\tGn Q\r\neL4_: \t :  \r\nicb$FiI: \t ;% P/WZ \r\nyZ'` |
| accepts | the asterisk-form with a method other than OPTIONS | 7 | `b'PATCH * HTTP/1.1\r\nHOST:CaeIpJk.*%F1:65535\r\n-bUE._: \t \r\nhost:  3.%CB.Ot%E5.zFxUG:27573 \r\naP'`, `b'HEAD * HTTP/1.1\r\nHOST: \t %zz  \r\nOqr:  l \r\n\r\nGET / HTTP/1.1\r\n\r\n'` |
| accepts | a bare LF | 6 | `b'\n\r\nGET / HTTP/1.1\r\nHost: a\r\n\r\n'`, `b"\nPOST /N%cD=:)@ HTTP/1.1\r\nXjz'C:%]\t4\xd9 E2Ys6+FRi @ut \t \r\nBwr0sV:  yiS^bF\t\r\nOHCz8C: \t \xdd)u\t,4"` |
| accepts | a bare CR | 6 | `b'\r\n\r\r\nOPTIONS /x1E3p)//C HTTP/1.1\r\nhost: i~ \r\nV:TKv4\t \r\n\r\n'`, `b'\rPUT * HTTP/2.0\r\nBlHyu63: -_BDDd]9W\x88X-?\t}21\xc6 \t \r\n##D~:\t\t\r\nJntD:  5?rR-D \tW,\x90_\t\r\nHy:\tt~eI\xb4+'` |
| accepts | no Host in HTTP/1.1 | 3 | `b"CONNECT ws://i'5E'Ff.;2spq7T$:0 HTTP/1.1\r\nr: \t k^\t}]K)\tK,Ufo*~  \r\nPu-\|: \t N\xcf&\xac#  \r\n\r\n"`, `b'CONNECT x://[14:ca06:2bBa:F4:6:18:100.10.249.99]:/C/zO/8 HTTP/1.1\r\n$NJ: \t\r\n\r\nhello'` |
| accepts | a target with a bad percent escape | 2 | `b'GET /%zz HTTP/1.1\r\nHost: x\r\n\r\n'`, `b'OPTIONS /t:%<9ea//K%D8XW:j/%faq HTTP/1.1\r\nHost:[7b:B:5DFd:DE4:A:9bE6:68a9:d5d0]:65535 \r\nhO'` |
| accepts | a target with a bad IP literal | 2 | `b'GET http://[1::2::3]/ HTTP/1.1\r\nHost: x\r\n\r\n'`, `b'CONNECT [::CF6A:D:D759:c1:7d:D703:1dB:4]:443 HTTP/1.1\r\nL3:  }q}Y\x9cz  \r\n9: 52\x87}HK@2tU8   \r\nh'` |
| no answer | other whitespace in the request line | 2 | `b''`, `b''` |
| no answer | another version: 1.2 to 1.9 | 2 | `b'POST +b%fa4y6$n.wQ0,qe:90156 HTTP/1.2\r\nHost:9.199.99.9\t\r\nCONTENT-LENGTH:  35615 \t \r\n\r\n'`, `b'DELETE * HTTP/1.2\r\ncontent-length: 53317 \t \r\nhOsT: \t [A9b2:2:c:3343::e5D3:b]  \r\nHkznZVs-: '` |
| accepts | another target outside RFC 3986 | 1 | `b'GET /a#frag HTTP/1.1\r\nHost: x\r\n\r\n'` |
| no answer | empty lines before the request line | 1 | `b'\r\n'` |
| accepts | Transfer-Encoding in HTTP/1.0 | 1 | `b'CONNECT https://_l(M4r(e.$tJ-c HTTP/1.0\r\nhost: Tx.CC,&ksI.P; \r\n*nHI^J:  \t \r\nv*gk-Qv:  n7n8'` |
| rejects | the asterisk-form with a method other than OPTIONS | 1 | `b'DELETE * HTTP/1.1\r\nT: \t ;k \t \r\nEdrdlq:6u(p\xeaX$\xc8 \r\ngxGOa:e^\x81tuE!YakKSPe&+Ns \r\nHOST:  [4:2:4A'` |

## Go go1.24.7 net/http

- Same verdict, accept or reject: 4525; of those accepted with a body count in the answer, 1126 read the same body length and 0 another
- Different verdict: 865
- No answer: 14
- Not sent, since the body would be over 64 KiB: 587

Where it differs from this project, by the first category that fits the head:

| It | Category | Heads | Example |
| --- | --- | --- | --- |
| rejects | empty lines before the request line | 337 | `b'\r\n\r\nGET / HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'\r\n\r\nHEAD /:R$/uT HTTP/1.1\r\nE_r:  K] \r\nQ`XQp:9K3jpH\\bl  \r\nhost:[46:9fda::E:820:07]\r\n2: A>\t '` |
| rejects | the authority-form with a method other than CONNECT | 117 | `b'GET [::0cC:F7D3:F6]:443 HTTP/1.1\r\nHOST: \t %8D8o \r\n\r\n)'`, `b'OPTIONS Q5B%a1M.dZ%EB:53707 HTTP/1.1\r\nD2M&y#: \t w\xa5*s\xebH6!og\r\nlEdoMZg: E V&i\xa1dF\xec6~Ubu$\x98\xdfl \r\n'` |
| accepts | Transfer-Encoding in HTTP/1.0 | 70 | `b'POST /a HTTP/1.0\r\nTransfer-Encoding: chunked\r\n\r\n'`, `b"DELETE /0(n/ HTTP/1.0\r\nbSGn8F: ?9\x96\x94 3-\xe3y0\tE\r\nTransfer-Encoding:\tChunked \r\n37\|i1ZH: u\tpT!l'"` |
| accepts | a bare LF | 62 | `b'POST /a HTTP/1.1\r\nHost: x\nTransfer-Encoding: chunked\r\n\r\n'`, `b'TRACE /(/S HTTP/1.1\nTRANSFER-ENCODING: chunked\t\r\nhost:\tbDC%B0JI2+.ToH.TuL\r\n\r\n'` |
| accepts | a method other than the registered ones | 42 | `b'ML%&O /@Z/w,c8i?Yh/@4 HTTP/1.0\r\nTRANSFER-ENCODING:CHUNKED \t \r\nHost:\tiEX.mPUVR \r\nMCqYbB: k>'`, `b'KyvADje /D%7B;/_urY5l/Ru/8W HTTP/1.1\r\nhost:\t[::F8:EF7:BC5b:2:8F2e:0:9D9A:B3]:0\t\r\nI:jALc  \r'` |
| accepts | an absolute-form target with no authority | 37 | `b"PUT x:/X8:G?v5' HTTP/1.1\r\nhost:\t[cB7:1FE:cb:D12:c3:D743:E1D:a::]:443 \t \r\nsVaKRMJ:\tg\\!7I!Se"`, `b'HEAD http:/pY0h//:mn;/XG: HTTP/1.1\r\nAWN8BU7y: \xe3 fzq"\\81F\xc7. \xed(\t\r\n~:y2 ~\t=D\xca\xf1KKF?!\xbc~ \r\nG\|Gy2'` |
| accepts | a line starting with whitespace (obs-fold) | 36 | `b'POST /a HTTP/1.1\r\nHost: x\r\nX: y\r\n Transfer-Encoding: chunked\r\n\r\n'`, `b"PUT /wf/;/n&I.%Dd/8 HTTP/1.1\r\n%U'ketB:  \t:\x84`\xb1p\r\n folded\r\nY$ryqW%2:\tVc\x92+\tbvP\xa2\xbe!lGk\r\nn: \t Q;"` |
| accepts | a Host value outside RFC 3986 | 31 | `b'DELETE /_/Di./@o HTTP/1.1\r\nhOsT: h:p \r\n\r\nGET / HTTP/1.1\r\n\r\n\r\n'`, `b'POST /=S~ER/@jo:;m/r%E3l HTTP/1.1\r\nhost:  [::eE:72F:Fd:619:d:6:AB4D:EF56] \r\n\r\n0\r\n\r\n'` |
| rejects | a method other than the registered ones | 29 | `b'M 7b%9C%FaQn!:443 HTTP/1.1\r\nL*: H~^ \t \r\nHOST: cE7oK  \r\nTransfer-Encoding: \t CHUNKED \r\n\|NuO'`, `b'.`\|IzB [9b:4eD:1bCb:b9F:94:4:bdBA:DB]:0 HTTP/1.0\r\nHxe!c: #\x81\xc0\r\nK8#MXl1A:   \r\nHost: O(3Cyn+.'` |
| accepts | CONNECT with a target other than the authority-form | 21 | `b'CONNECT /%8by!hF/%40)D%bb//bN%bDEDs HTTP/1.1\r\n%p: %\x86+6\xc1j/]17~n+  Z!h+1\t\r\nHOST: 701s_t.m8(H'`, `b"CONNECT /n@RE&'?un@:%C6EIY HTTP/1.1\r\nContent-Length:\t007 \r\ngMIK: \t  \t \r\nHOST:G.(\r\nL+wTK^UW"` |
| rejects | another version: 1.2 to 1.9 | 16 | `b'PUT cFLw.,hVFMR+%43.wFj,LG:80 HTTP/1.9\r\nd6:WtUf= v$cG\|\xc1_   \r\ny#jgs: } bGRvmZog\xf0PNO\xc1\xd5 \r\nL:\t'`, `b'OPTIONS yM7X9M.dD_bp4w6.!!Dwd5:443 HTTP/1.2\r\nhost:\tO%89da6gR.+_,Hcb:8080 \t \r\nZ:  \r\n\r\n\x0e'` |
| accepts | another version: 1.2 to 1.9 | 14 | `b'CONNECT /@/: HTTP/1.2\r\nCONTENT-LENGTH:0 \r\nhOsT:  118.99.99.130:65535 \r\ntransfer-encoding: '`, `b'OPTIONS x:/9/%beXI HTTP/1.9\r\nA~: [r,H\t \r\nhost:h:p \r\ncontentH-length: \t 0\r\ncfKto&OQ:\t  \r\n\r\n'` |
| accepts | Transfer-Encoding with Content-Length | 13 | `b'POST /a HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nTransfer-Encoding: chunked\r\n\r\n'`, `b'POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nContent-Length: 5\r\n\r\n'` |
| accepts | the asterisk-form with a method other than OPTIONS | 9 | `b'PUT * HTTP/1.1\r\n%SVM: \xcf\t\r\nhost: \t [17bb:8::15f:2:1:F7d9:95Ce:0BA]:443\r\n9LenBlL: dlH9\xd9 yA \r'`, `b'PUT * HTTP/1.0\r\nmO3:\tzx _ \t1\x84\x96Y{bW\tG\t)\| \t \r\nR851: M\t\r\nHzIi:  Z@^\t*N\r\nHOST:\t199.250.235.255'` |
| accepts | two Content-Length lines with the same value | 5 | `b'POST /a HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nContent-Length: 5\r\n\r\nhello'`, `b"PATCH //(B@l HTTP/1.1\r\nC'Ejz: *;& IivC\tV \t \r\nHost:  200.68.9.10  \r\nCONTENT-LENGTH: 884659\t"` |
| accepts | a target with a bad IP literal | 5 | `b'GET http://[1::2::3]/ HTTP/1.1\r\nHost: x\r\n\r\n'`, `b'Nil a+b.c-d://[bD6:D277:0caC:9f:7B8::a:5:b]:65535/7@7/mZ HTTP/1.1\r\nsQXMmA: 4? \r\nmEZpg:    '` |
| rejects | obs-text in a field value | 5 | `b'PATCH x://X6%26.A:89895?~e%73@B0 HTTP/1.1\r\nHlLyJ:\t my\r\nhost: \t =%b0H~.aA0.tn+4%3dP \t \r\nf%r'`, `b'DELETE x://A36rG.%64Iz.U*kj$A%c1:11224/b0 HTTP/1.1\r\nAk\|zS.2:\t\xef \\r))7 b[\tCh\xf0q,\t\r\ntWf:  G \xfd`'` |
| no answer | empty lines before the request line | 5 | `b'\r\n\r\nPUT /X!%84%9e&K?%EBq%63Qx/ HTTP/1.0\r\nHost:10.250.9.0:77238 \r\nCONTENT-LENGTH: \t 21042  '`, `b'\r\nOPTIONS 0.100.249.249:8080 HTTP/1.1\r\nq*yeU: kE @`\x9c\t\r\nCONTENT-LENGTH: 11176\t\r\nRVxZ^:  c-\xbb'` |
| accepts | a target with octets above 0x7F | 4 | `b"OPTIONS /ROcG+G/\x94/T'Zp8/)%92%693Pq HTTP/1.1\r\ncontent-length: \t 75256 \r\nhost: s\r\n\r\n"`, `b'HEAD a+b.c-d:\xdd//E)%0bo%d4x%02/SN%C2/Iql HTTP/1.1\r\nHOST:\tX&Ef \r\n%J\|Z`g:  \r\nCONTENT-LENGTH:\t'` |
| rejects | an absolute-form target with no authority | 4 | `b"CONNECT a+b.c-d:RZt%1A HTTP/1.1\r\nHOST:6H%C1Nyg%B6N.0.EJXY \r\nHl1z0U: C@hXE'\\\r\nl_:   \r\nK3:\t\t"`, `b"CONNECT x:L90?%C7jHk HTTP/1.1\r\nv'cgMa&:  qt,SJ\xc1kHd \t \r\nHost:  ;.9h2ack%c2.4sp%70= \t \r\n7**m"` |
| no answer | the authority-form with a method other than CONNECT | 4 | `b'DELETE R.izqpkHl6.t*:0 HTTP/1.0\r\ncontent-length: 16071\t\r\nio~v^H6:\tS;qu\|-&\xcbBa3s \t \r\nhost:\t%'`, `b'TRACE &%fbrM%45eT-: HTTP/1.1\r\na8yLw0: %-;\xd1\x8bJ\xf3raD\\\\VFkU_\tNL \r\nCONTENT-LENGTH: 17253\r\n7%&: \xc7'` |
| accepts | no Host in HTTP/1.1 | 3 | `b"CONNECT ws://i'5E'Ff.;2spq7T$:0 HTTP/1.1\r\nr: \t k^\t}]K)\tK,Ufo*~  \r\nPu-\|: \t N\xcf&\xac#  \r\n\r\n"`, `b'CONNECT x://[14:ca06:2bBa:F4:6:18:100.10.249.99]:/C/zO/8 HTTP/1.1\r\n$NJ: \t\r\n\r\nhello'` |
| rejects | other | 3 | `b'PUT https://%60yX%cC/@$@ HTTP/1.1\r\ntransfer-encoding:chunked\r\n^qXoR:  %R8q\t\t\r\nhost:  199.1'`, `b'HEAD x://uq%ce%6Ck/g$ HTTP/1.1\r\nj7J+C8:\t_q=s  \r\nhost: [fC25:43:10a4:e:e7:042:1.249.10.100]'` |
| no answer | other whitespace in the request line | 2 | `b''`, `b''` |
| accepts | another target outside RFC 3986 | 1 | `b'GET /a#frag HTTP/1.1\r\nHost: x\r\n\r\n'` |
| no answer | an absolute-form target with no authority | 1 | `b"CONNECT https:M+%CB HTTP/1.1\r\ncontent-length: 13126  \r\nRBi:0\xdc  \r\nqyp4b:  QC E \x8e    Q:'eP\xc9%"` |
| no answer | a method other than the registered ones | 1 | `b'nuK+f rV)Ky%64.F;t%26nS:443 HTTP/1.1\r\ncontent-length: 26044 \t \r\nHOST:99.0.9.99 \r\nAHT_fu8u:'` |
| no answer | another version: 1.2 to 1.9 | 1 | `b'POST +b%fa4y6$n.wQ0,qe:90156 HTTP/1.2\r\nHost:9.199.99.9\t\r\nCONTENT-LENGTH:  35615 \t \r\n\r\n'` |
| rejects | an empty Host | 1 | `b"GET http://7K6%9d%2ck0N.tU.%2B%Edc%4E/y%C6i/.h%7C'/?8 HTTP/1.0\r\nhost:   \r\n\r\n0\r\n\r\n"` |

## h11 0.16.0

- Same verdict, accept or reject: 4669; of those accepted with a body count in the answer, 1414 read the same body length and 0 another
- Different verdict: 733
- No answer: 2
- Not sent, since the body would be over 64 KiB: 587

Where it differs from this project, by the first category that fits the head:

| It | Category | Heads | Example |
| --- | --- | --- | --- |
| rejects | empty lines before the request line | 342 | `b'\r\n\r\nGET / HTTP/1.1\r\nHost: a\r\n\r\n'`, `b'\r\n\r\nHEAD /:R$/uT HTTP/1.1\r\nE_r:  K] \r\nQ`XQp:9K3jpH\\bl  \r\nhost:[46:9fda::E:820:07]\r\n2: A>\t '` |
| accepts | another version: not HTTP/1.x | 136 | `b'GET / HTTP/2.0\r\nHost: a\r\n\r\n'`, `b'PATCH [E::Bd:Aa]:80 HTTP/0.9\r\ntVih`6: +\xd8\r\nSy+f:\tl1&)7Hc \r\nDHBYJ:  \r\nFNgn~0\|:& \r\nHost:=YY%8'` |
| accepts | a line starting with whitespace (obs-fold) | 61 | `b'POST /a HTTP/1.1\r\nHost: x\r\nX: y\r\n Transfer-Encoding: chunked\r\n\r\n'`, `b'CONNECT 5.3M~0f!~m.4sEkOc%E2:77798 HTTP/2.0\r\nlv:  1 \t \r\n\tfolded\r\nrk:\t#^\xd5U \r\nsTY9dQ~:  ]?+ '` |
| accepts | a bare LF | 53 | `b'HEAD 6_TvYO.4:71170 HTTP/1.1\r\n$Azno`: \t n\xd4#Dbi:w)AfL0 \r\nhost:  1.255.0.99 \r\n0uJaO:\t\x9cjv`d@\xcb'`, `b'GET [51:CAA7::bc7]:80 HTTP/2.0\n~:"y\xdd+\xd0^\xc0~.0*5yC pd6\r\nN7L%\'$4\': \tlR]Q  \r\no0cBAa: \t ArN\t\r\nHO'` |
| accepts | a Host value outside RFC 3986 | 42 | `b'GET / HTTP/1.1\r\nHost: a b\r\n\r\n'`, `b'DELETE /_/Di./@o HTTP/1.1\r\nhOsT: h:p \r\n\r\nGET / HTTP/1.1\r\n\r\n\r\n'` |
| accepts | another version: 1.2 to 1.9 | 29 | `b'TRACE //y?F HTTP/1.2\r\nEHD8ns6:p7QJ\x8d8dg;nJ\|b%22%\\   \r\n\r\n'`, `b'Rz /%a3kn@:/$C;I?zvOtPpJ HTTP/1.2\r\ncpa5:  O\xb9uyl \r\nhOsT: x? \r\n+S1Z#p: \t nk2m ~ \t \r\n\r\nhello'` |
| accepts | an absolute-form target with no authority | 19 | `b"PUT x:/X8:G?v5' HTTP/1.1\r\nhost:\t[cB7:1FE:cb:D12:c3:D743:E1D:a::]:443 \t \r\nsVaKRMJ:\tg\\!7I!Se"`, `b'HEAD http:; HTTP/1.1\r\narBlLbeq:\tdl\x8b<,/\xdcxg7. \t \r\nk*GSWCx: ce<BEf  \r\n8sEn-:\t-\xa80ibw\xe9Q{\xc40p/4\xbc\r'` |
| accepts | a method other than the registered ones | 13 | `b'KyvADje /D%7B;/_urY5l/Ru/8W HTTP/1.1\r\nhost:\t[::F8:EF7:BC5b:2:8F2e:0:9D9A:B3]:0\t\r\nI:jALc  \r'`, `b"u\|z /:@z HTTP/1.1\r\n4z.K60rs: \t //^~L \r\nIr: \x84~z\xf5=RACMmhK\tm  \t \r\nsM`: FFW\xcdKSx\r\n8:  eQ \tAGN' "` |
| accepts | a target with a bad IP literal | 11 | `b'GET http://[1::2::3]/ HTTP/1.1\r\nHost: x\r\n\r\n'`, `b"DELETE [2a8C:4E74:f:94dd:d4e::F:3d:E5f]:0 HTTP/1.1\r\n*^':  DH.A vxD6lQRD)k E&Z\t\r\nHost: [B2:"` |
| accepts | the authority-form with a method other than CONNECT | 8 | `b'POST [vf.b]: HTTP/1.0\r\nhOsT: [::1 \t \r\n\r\n'`, `b'OPTIONS [vCA.Zs]:443 HTTP/1.1\r\nHOST:a b \t \r\n\r\n0\r\n\r\n'` |
| accepts | a control octet in a field line | 6 | `b"DELETE /QR%b1$/4c3/:k%aAAo/er9'B; HTTP/1.1\r\nHost: [vaDFF.(_] \t \r\nzCLQ8Dx:\xc3%kHrZ:p  \r\n9t~9N"`, `b'PATCH https:/x+V//~;8%B7K/2P%5Dd@f HTTP/1.0\r\n\|A-WqG*:\x13X,\| \r\nHost: \t (LHDNSz.S:443\r\n\r\n'` |
| accepts | CONNECT with a target other than the authority-form | 5 | `b'CONNECT /%8by!hF/%40)D%bb//bN%bDEDs HTTP/1.1\r\n%p: %\x86+6\xc1j/]17~n+  Z!h+1\t\r\nHOST: 701s_t.m8(H'`, `b'CONNECT ///~0CF+/ HTTP/1.1\r\nl_:\t\xa1L@S\x97bBa]\xc1\x89 9u3  \r\nhOsT: x?\r\n\r\n'` |
| accepts | the asterisk-form with a method other than OPTIONS | 4 | `b'HEAD * HTTP/1.1\r\nHOST: \t %zz  \r\nOqr:  l \r\n\r\nGET / HTTP/1.1\r\n\r\n'`, `b'CONNECT * HTTP/1.1\r\nn&5O:\tB4J\r\nhost:[0:CC:cF8:BBeE:8d3:8:928:Eb::]  \r\n1Ca_:\tngd{?[\xbe\tU\tQ-\|\x86'` |
| accepts | another target outside RFC 3986 | 3 | `b'GET /a#frag HTTP/1.1\r\nHost: x\r\n\r\n'`, `b"rsQp x://:c%04%a2/poe.@U HTTP/1.1\r\nOy\|wVQb:  \r\nRDTs*:  P\t\r\n8xQku$: \t tZJ^'}z5\xac\t[K z}3 \r\nhO"` |
| no answer | other whitespace in the request line | 2 | `b''`, `b''` |
| accepts | a target with a bad percent escape | 1 | `b'GET /%zz HTTP/1.1\r\nHost: x\r\n\r\n'` |
