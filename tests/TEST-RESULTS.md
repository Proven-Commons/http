# Test results

Written by `tests/run_tests.py`. Rerun it to check these numbers.

- Oracle: Python 3.13.17: the grammar and framing rules of RFC 9112, RFC 9110 and RFC 3986 written in this script, with its IPv6 rule checked against `ipaddress`
- Lean: Lean (version 4.35.0, x86_64-unknown-linux-gnu, commit eb6cafb7290e8bd5f2937522d8d804f58f02bafc, Release)
- Seed: 20261025
- Inputs: 300000
- Mutated: 104750 of the inputs are mutated heads
- By kind: error 9, fixed 53, mutated 104750, valid 195188
- Heads read: 216739 of 299991, and 83252 refused by the grammar
- Targets of the heads read: 119545 origin-form, 56392 absolute-form, 29809 authority-form (or both: `a:1` fits both), 10993 asterisk-form; 10647 with an IP literal
- Framing of the heads read: 74228 with no body, 33203 with a length, 13478 chunked, 95830 rejected
- IPv6 addresses checked against `ipaddress`, to test the oracle: 20000, 0 disagreements
- Malformed requests answered `error`: 9 of 9
- Requests ending in CR LF: every seventh, 42857
- Inputs also given to `httphead check` on standard input: 2000, and once with no arguments
- A last line with no LF, sent alone, answered right: yes
- Failures: 0
