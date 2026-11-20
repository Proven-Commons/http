# Test results

Written by `tests/run_tests.py`. Rerun it to check these numbers.

- Oracle: Python 3.13.17: the grammar and framing rules of RFC 9112, RFC 9110 and RFC 3986 written in this script, with its IPv6 rule checked against `ipaddress`
- Lean: Lean (version 4.35.0, x86_64-unknown-linux-gnu, commit eb6cafb7290e8bd5f2937522d8d804f58f02bafc, Release)
- Seed: 20261025
- Inputs: 300000
- Mutated: 104805 of the inputs are mutated heads
- By kind: error 9, fixed 203, mutated 104805, valid 194983
- Heads read: 211606 of 299991, and 88385 refused by the grammar
- Framing of the heads read: 53665 with no body, 23554 with a length, 10533 chunked, 123854 rejected
- Targets of the heads read: 111186 origin-form, 43301 absolute-form only, 35868 authority-form only, 10984 that fit both absolute-form and authority-form (such as `a:1`), 10267 asterisk-form; 13647 with an IP literal
- Heads read with the method `CONNECT`: 14134. Accepted: 1797. Against the CONNECT rule, and so rejected: 1043 with a host and port target whose host is empty, such as `:443`, 3899 with a host and port target whose host is not empty and whose port is not from 1 to 65535, and 2535 with a target of another form. Rejected only by another rule: 4860
- Ports of those `CONNECT` targets that are a host and port: 611 empty, 886 zero, 2816 above 65535, 2336 from 1 to 65535 with leading zeros
- Heads read with `connect` or another case of it, which is a different method: 3018, 1095 accepted, 1923 rejected
- Heads read with a target whose scheme is http or https, in any case, and a method other than `CONNECT`: 21234, 10371 of them with upper case in the scheme. Accepted: 6125. Against the rule of RFC 9110 section 4.2, and so rejected: 3085 with no `//` and so no authority, 2532 with an empty host, 2204 with userinfo. Rejected only by another rule: 7288
- Heads read with `CONNECT` and a target that starts with `http:` or `https:`, in any case: 1821. Of them, 1386 are a host and port, such as `http:80`, which names the host http or https, 239 of them accepted; and 435 are of another form, such as `http://a:80/`, 0 of them accepted
- Heads read with a target of another scheme that fits absolute-form, and a method other than `CONNECT`, which that rule does not cover: 29327, 22111 absolute-form only and 7216 that also fit authority-form, such as `x:443`; 11658 of them with a scheme that starts with `http`, such as `httpx`; 13340 accepted
- Heads read with Transfer-Encoding: 52655. With an empty list element in the combined value: 25747, 6902 chunked and 18845 rejected. With two or more Transfer-Encoding lines: 16435, 3027 chunked and 13408 rejected
- IPv6 literals with an IPv4 tail that is not four dec-octets, anywhere in the input, so also in a field that is not Host: 4837 inputs: 2175 refused by the grammar, 2661 read and rejected, 1 read and accepted
- IP literals with a zone ID (`%` inside the brackets), anywhere in the input: 10181 inputs: 4561 refused by the grammar, 5619 read and rejected, 1 read and accepted
- IPvFuture with an upper-case `V`, anywhere in the input: 7732 inputs: 2407 refused by the grammar, 3109 read and rejected, 2216 read and accepted
- IPvFuture with no hex digit or nothing after the dot, such as `[v.a]` or `[v1.]`, which RFC 3986 does not allow, anywhere in the input: 3597 inputs: 1628 refused by the grammar, 1968 read and rejected, 1 read and accepted
- Host values of the heads read: 212691. Empty: 8107, 4114 of them in an accepted head. With an empty host before a colon, such as `:80` or `:`: 11523, 0 of them in an accepted head
- Host values of the heads read that hold two or more colons and no `[`, such as an IPv6 address with no brackets: 9031, 0 in an accepted head
- IPv6 addresses checked against `ipaddress`, to test the oracle: 20000, of them 1306 with an IPv4 tail that is not four dec-octets; 0 disagreements
- Malformed requests answered `error`: 9 of 9
- Requests ending in CR LF: every seventh, 42857
- Inputs also given to `httphead check` on standard input: 2000, and once with no arguments
- Long inputs, each given to `httphead check` on standard input and to `httphead serve`, each run within the time in brackets: a request line of 16 MB (400 s); a field value of 16 MB with a NUL at the end (150 s); a Content-Length of 1,000,000 digits, 1234567890 repeated (30 s); a CONNECT port of 1,000,000 nines (30 s); a CONNECT port of 1,000,000 zeros, then 443 (30 s); a Transfer-Encoding value with 64 KB of spaces after a comma (10 s). Runs answered right in time: 12 of 12
- A last line with no LF, sent alone, answered right: yes
- Failures: 0
