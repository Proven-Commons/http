# Test results

Written by `tests/run_tests.py`. Rerun it to check these numbers.

- Oracle: Python 3.13.17: the grammar and framing rules of RFC 9112, RFC 9110 and RFC 3986 written in this script, with its IPv6 rule checked against `ipaddress`
- Lean: Lean (version 4.35.0, x86_64-unknown-linux-gnu, commit eb6cafb7290e8bd5f2937522d8d804f58f02bafc, Release)
- Seed: 20261025
- Inputs: 300000
- Mutated: 105111 of the inputs are mutated heads
- By kind: error 9, fixed 173, mutated 105111, valid 194707
- Heads read: 212242 of 299991, and 87749 refused by the grammar
- Framing of the heads read: 62625 with no body, 28154 with a length, 12474 chunked, 108989 rejected
- Targets of the heads read: 111035 origin-form, 43718 absolute-form only, 36185 authority-form only, 11023 that fit both absolute-form and authority-form (such as `a:1`), 10281 asterisk-form; 14730 with an IP literal
- Heads read with the method `CONNECT`: 14326. Accepted: 3911. Against the CONNECT rule, and so rejected: 4391 with a host and port target whose port is not from 1 to 65535, and 2581 with a target of another form. Rejected only by another rule: 3443
- Ports of those `CONNECT` targets that are a host and port: 625 empty, 880 zero, 2886 above 65535, 2369 from 1 to 65535 with leading zeros
- Heads read with `connect` or another case of it, which is a different method: 3020, 1359 accepted, 1661 rejected
- Heads read with a target whose scheme is http or https, in any case, and a method other than `CONNECT`: 21185, 10345 of them with upper case in the scheme. Accepted: 7079. Against the rule of RFC 9110 section 4.2, and so rejected: 2964 with no `//` and so no authority, 2506 with an empty host, 2231 with userinfo. Rejected only by another rule: 6405
- Heads read with `CONNECT` and a target that starts with `http:` or `https:`, in any case, which names the host http or https: 1833, 456 accepted
- Heads read with an absolute-form target of another scheme, which that rule does not cover: 23276, 9747 of them with a scheme that starts with `http`, such as `httpx`; 11582 accepted
- Heads read with Transfer-Encoding: 52812. With an empty list element in the combined value: 25905, 8155 chunked and 17750 rejected. With two or more Transfer-Encoding lines: 16588, 3630 chunked and 12958 rejected
- IPv6 literals with an IPv4 tail that is not four dec-octets, anywhere in the input, so also in a field that is not Host: 5125 inputs: 2248 refused by the grammar, 2876 read and rejected, 1 read and accepted
- IP literals with a zone ID (`%` inside the brackets), anywhere in the input: 10655 inputs: 4688 refused by the grammar, 5964 read and rejected, 3 read and accepted
- IPvFuture with an upper-case `V`, anywhere in the input: 9197 inputs: 2659 refused by the grammar, 3198 read and rejected, 3340 read and accepted
- Host values of the heads read that hold two or more colons and no `[`, such as an IPv6 address with no brackets: 9253, 0 in an accepted head
- IPv6 addresses checked against `ipaddress`, to test the oracle: 20000, of them 1306 with an IPv4 tail that is not four dec-octets; 0 disagreements
- Malformed requests answered `error`: 9 of 9
- Requests ending in CR LF: every seventh, 42857
- Inputs also given to `httphead check` on standard input: 2000, and once with no arguments
- A last line with no LF, sent alone, answered right: yes
- Failures: 0
