# Test results

Written by `tests/run_tests.py`. Rerun it to check these numbers.

- Oracle: Python 3.13.17: the grammar and framing rules of RFC 9112, RFC 9110 and RFC 3986 written in this script, with its IPv6 rule checked against `ipaddress`
- Lean: Lean (version 4.35.0, x86_64-unknown-linux-gnu, commit eb6cafb7290e8bd5f2937522d8d804f58f02bafc, Release)
- Seed: 20261025
- Inputs: 300000
- Mutated: 104801 of the inputs are mutated heads
- By kind: error 9, fixed 118, mutated 104801, valid 195072
- Heads read: 213062 of 299991, and 86929 refused by the grammar
- Framing of the heads read: 65501 with no body, 29379 with a length, 13028 chunked, 105154 rejected
- Targets of the heads read: 111691 origin-form, 41910 absolute-form only, 36502 authority-form only, 12741 that fit both absolute-form and authority-form (such as `a:1`), 10218 asterisk-form; 12148 with an IP literal
- Heads read with the method `CONNECT`: 14222. Accepted: 3724. Against the CONNECT rule, and so rejected: 4220 with a host and port target whose port is not from 1 to 65535, and 3073 with a target of another form. Rejected only by another rule: 3205
- Ports of those `CONNECT` targets that are a host and port: 605 empty, 818 zero, 2797 above 65535, 2224 from 1 to 65535 with leading zeros
- Heads read with `connect` or another case of it, which is a different method: 2968, 1541 accepted, 1427 rejected
- Heads read with Transfer-Encoding: 52757. With an empty list element in the combined value: 25837, 8533 chunked and 17304 rejected. With two or more Transfer-Encoding lines: 16443, 3723 chunked and 12720 rejected
- IPv6 literals with an IPv4 tail that is not four dec-octets, anywhere in the input, so also in a field that is not Host: 4884 inputs: 2024 refused by the grammar, 2859 read and rejected, 1 read and accepted
- IP literals with a zone ID (`%` inside the brackets), anywhere in the input: 10172 inputs: 4304 refused by the grammar, 5866 read and rejected, 2 read and accepted
- IPvFuture with an upper-case `V`, anywhere in the input: 8806 inputs: 2562 refused by the grammar, 2886 read and rejected, 3358 read and accepted
- Host values of the heads read that hold two or more colons and no `[`, such as an IPv6 address with no brackets: 9394, 0 in an accepted head
- IPv6 addresses checked against `ipaddress`, to test the oracle: 20000, of them 1306 with an IPv4 tail that is not four dec-octets; 0 disagreements
- Malformed requests answered `error`: 9 of 9
- Requests ending in CR LF: every seventh, 42857
- Inputs also given to `httphead check` on standard input: 2000, and once with no arguments
- A last line with no LF, sent alone, answered right: yes
- Failures: 0
