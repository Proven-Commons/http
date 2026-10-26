#!/usr/bin/env python3
"""Plant each bug below in a copy of the code, and check the tests catch it.

A planted bug is a small change to the code under proof, of a kind a
person could make by mistake. For each one, this script copies the
project into a temporary directory, makes the change there, builds the
command-line tool, and runs the differential tests on a given number of
inputs. The tests catch the bug when they report failures. A change
that alters an answer of the code under proof also breaks the proofs,
since the code no longer meets its statements. This script checks the
tests on their own, so it builds only the tool, not the proofs.

The project itself is never changed. The script writes the results to
tests/PLANTED-BUGS.md, and exits with 1 if a bug is not caught and is
not marked as equivalent. An equivalent change gives the same answer on
every input, so no test can catch it; its entry says why.

Usage: python3 tests/planted_bugs.py [--count N]
"""

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXE = "httphead"  # the lake target of the command-line tool
COUNT = 300_000

TE_ANY_LINES = ("    | t :: ts, [] =>\n"
                "      if 1 ≤ h.minor && Grammar.chunkedList.isMatch (List.intercalate [0x2C] "
                "((t :: ts).map (·.value)))\n")
LIST_ONE = '  seq [star (seq [OWS, litCI ",", OWS]), e, star (seq [OWS, litCI ",", OWS])]'
DEC_OCTET = ('def decOctet : Re :=\n'
             '  any [DIGIT, cat (range 0x31 0x39) DIGIT, cat (litCI "1") (rep 2 DIGIT),\n'
             '    seq [litCI "2", range 0x30 0x34, DIGIT], cat (litCI "25") (range 0x30 0x35)]')
HTTP_PREFIX = ("!(httpColon.isPrefixOf (h.target.map lower) || "
               "httpsColon.isPrefixOf (h.target.map lower))")

# Why the two equivalent changes give the same answer on every input.
BARE_CR = (
    "the code gives `none` for a CR that is not followed by LF, and the change keeps that CR in "
    "the line instead. Every line is then read by parseHead or parseField, and neither accepts a "
    "CR: not in the method (a token), the target (no rule of the target grammar has 0x0D), the "
    "version (exactly `HTTP/` digit `.` digit), a field name (a token) or a field value (trim "
    "removes only SP and HTAB, and isFieldValue allows only field-vchar, SP and HTAB). A line "
    "holding a CR is not empty, so it never ends the head. So parseHead gives `none` in both, "
    "and on every other input the code is the same")
UPPER_NAMES = (
    "on every head that parseHead gives, the only heads the tool frames, it matches the same "
    "fields. `n.map (c - 0x20)` is `HOST` for `host`, which the first test already matches. For "
    "`content-length` and `transfer-encoding` it turns `-` (0x2D) into CR (0x0D), and a field "
    "name is a token, so it never holds a CR. The proof of framing_iff, which covers every "
    "Head, would catch it; the tests cannot")

# (name, file, text to replace, replacement, why it is equivalent or None)
BUGS = [
    # The head
    ("bare LF ends a line", "Http/Head.lean", "    else if c == 0x0A then none\n",
     "    else if c == 0x0A then some ([], rest)\n", None),
    ("bare CR kept in a line", "Http/Head.lean",
     "      | d :: rest' => if d == 0x0A then some ([], rest') else none",
     "      | d :: rest' => if d == 0x0A then some ([], rest') else "
     "(takeLine rest).map fun p => (c :: p.1, p.2)", BARE_CR),
    ("space before colon dropped", "Http/Head.lean", "  let name := line.takeWhile (· != 0x3A)\n",
     "  let name := (line.takeWhile (· != 0x3A)).filter (· != 0x20)\n", None),
    ("trailing whitespace kept", "Http/Head.lean", "  ((v.dropWhile isWs).reverse.dropWhile isWs).reverse",
     "  v.dropWhile isWs", None),
    ("NUL allowed in a value", "Http/Head.lean",
     "def isVchar (c : UInt8) : Bool := (0x21 ≤ c && c ≤ 0x7E) || 0x80 ≤ c",
     "def isVchar (c : UInt8) : Bool := (0x21 ≤ c && c ≤ 0x7E) || 0x80 ≤ c || c == 0", None),
    ("a double quote in a token", "Http/Head.lean", "    0x60, 0x7C, 0x7E].contains c",
     "    0x60, 0x7C, 0x7E, 0x22].contains c", None),
    ("empty lines first not skipped", "Http/Head.lean",
     "  | c :: d :: rest => if c == 0x0D && d == 0x0A then skipEmpty rest else c :: d :: rest",
     "  | c :: d :: rest => c :: d :: rest", None),
    ("minor version digit unchecked", "Http/Head.lean", "        isDigit a && isDigit b then",
     "        isDigit a then", None),
    # Host, version and Content-Length
    ("Host not required in HTTP/1.1", "Http/Framing.lean", " || (1 ≤ h.minor && hosts.length != 1)", "",
     None),
    ("two Host lines accepted", "Http/Framing.lean", " || hosts.length > 1", "", None),
    ("upper-case field names matched twice", "Http/Framing.lean",
     "def Field.isNamed (f : Field) (n : List UInt8) : Bool := f.name.map lower == n",
     "def Field.isNamed (f : Field) (n : List UInt8) : Bool := f.name.map lower == n || "
     "f.name == n.map (fun c => c - 0x20)", UPPER_NAMES),
    ("any major version accepted", "Http/Framing.lean", "  if h.major != 1 ||", "  if", None),
    ("first of several Content-Length taken", "Http/Framing.lean", "    | [], [f] => if",
     "    | [], f :: _ => if", None),
    ("Content-Length and port digits read backwards", "Http/Framing.lean",
     "def decimal (ds : List UInt8) : Nat := ds.foldl (fun n d => 10 * n + (d.toNat - 0x30)) 0",
     "def decimal (ds : List UInt8) : Nat := ds.foldr (fun d n => 10 * n + (d.toNat - 0x30)) 0", None),
    # Transfer-Encoding
    ("Transfer-Encoding overrides Content-Length", "Http/Framing.lean", "    | _, _ => none\n",
     "    | t :: ts, _ =>\n"
     "      if 1 ≤ h.minor && Grammar.chunkedList.isMatch (List.intercalate [0x2C] "
     "((t :: ts).map (·.value)))\n"
     "      then some .chunked else none\n"
     "    | _, _ => none\n", None),
    ("Transfer-Encoding in HTTP/1.0 accepted", "Http/Framing.lean",
     "if 1 ≤ h.minor && Grammar.chunkedList.isMatch", "if Grammar.chunkedList.isMatch", None),
    ("chunked compared case-sensitively", "Http/Grammar.lean", 'def chunkedList : Re := listOne (litCI "chunked")',
     'def chunkedList : Re := listOne (lit "chunked")', None),
    ("list: no empty elements before chunked", "Http/Grammar.lean", LIST_ONE,
     '  seq [e, star (seq [OWS, litCI ",", OWS])]', None),
    ("list: no empty elements after chunked", "Http/Grammar.lean", LIST_ONE,
     '  seq [star (seq [OWS, litCI ",", OWS]), e]', None),
    ("list: at most one empty element before chunked", "Http/Grammar.lean", LIST_ONE,
     '  seq [opt (seq [OWS, litCI ",", OWS]), e, star (seq [OWS, litCI ",", OWS])]', None),
    ("list: a tab is not OWS", "Http/Grammar.lean", "def OWS : Re := star (alt SP HTAB)",
     "def OWS : Re := star SP", None),
    ("Transfer-Encoding only as one field line", "Http/Framing.lean", TE_ANY_LINES,
     "    | [t], [] =>\n      if 1 ≤ h.minor && Grammar.chunkedList.isMatch t.value\n", None),
    ("only the first Transfer-Encoding line read", "Http/Framing.lean", "((t :: ts).map (·.value))",
     "([t].map (·.value))", None),
    ("Transfer-Encoding lines joined with no comma", "Http/Framing.lean", "List.intercalate [0x2C]",
     "List.intercalate []", None),
    # CONNECT
    ("CONNECT rule removed", "Http/Framing.lean", "!h.connectOK || ", "", None),
    ("CONNECT port up to 65536", "Http/Framing.lean", "decimal (portOf h.target) ≤ 65535",
     "decimal (portOf h.target) ≤ 65536", None),
    ("CONNECT port 0 and empty port accepted", "Http/Framing.lean", "1 ≤ decimal (portOf h.target) &&",
     "0 ≤ decimal (portOf h.target) &&", None),
    ("CONNECT port 0 accepted", "Http/Framing.lean", "1 ≤ decimal (portOf h.target) &&",
     "!(portOf h.target).isEmpty &&", None),
    ("CONNECT port limited to five digits", "Http/Framing.lean", "decimal (portOf h.target) ≤ 65535",
     "(portOf h.target).length ≤ 5", None),
    ("CONNECT method compared case-insensitively", "Http/Framing.lean", "  h.method != connectName ||",
     "  h.method.map lower != connectName.map lower ||", None),
    ("CONNECT target form unchecked", "Http/Framing.lean",
     "    (Grammar.authorityForm.isMatch h.target && 1 ≤", "    (1 ≤", None),
    ("CONNECT port read from every digit", "Http/Framing.lean",
     "def portOf (t : List UInt8) : List UInt8 := (t.reverse.takeWhile isDigit).reverse",
     "def portOf (t : List UInt8) : List UInt8 := t.filter isDigit", None),
    # http and https targets
    ("http target rule removed", "Http/Framing.lean", " || !h.httpTargetOK", "", None),
    ("userinfo allowed in an http target", "Http/Grammar.lean", 'litCI "://", hostNonEmpty,',
     'litCI "://", opt (cat userinfo (litCI "@")), hostNonEmpty,', None),
    ("empty host allowed in an http target (reg-name star)", "Http/Grammar.lean",
     "plus (any [unreserved, pctEncoded, subDelims])", "star (any [unreserved, pctEncoded, subDelims])",
     None),
    ("scheme compared case-sensitively in the http target grammar", "Http/Grammar.lean",
     'alt (litCI "http") (litCI "https")', 'alt (lit "http") (lit "https")', None),
    ("scheme compared case-sensitively in the http and https prefix test", "Http/Framing.lean",
     HTTP_PREFIX, "!(httpColon.isPrefixOf h.target || httpsColon.isPrefixOf h.target)", None),
    ("CONNECT not exempt from the http target rule", "Http/Framing.lean",
     "  h.method == connectName ||\n    !(", "  !(", None),
    ("CONNECT exempt from the http target rule in any case", "Http/Framing.lean",
     "  h.method == connectName ||", "  h.method.map lower == connectName.map lower ||", None),
    ("https targets not checked", "Http/Framing.lean",
     " || httpsColon.isPrefixOf (h.target.map lower)", "", None),
    # The target and Host grammar
    ("a percent escape's second digit unchecked", "Http/Grammar.lean",
     'def pctEncoded : Re := seq [litCI "%", HEXDIG, HEXDIG]',
     'def pctEncoded : Re := seq [litCI "%", HEXDIG, range 0x30 0x7A]', None),
    ("256 as an IPv4 octet", "Http/Grammar.lean", 'cat (litCI "25") (range 0x30 0x35)]',
     'cat (litCI "25") (range 0x30 0x36)]', None),
    ("dec-octet 25 then any digit", "Http/Grammar.lean", 'cat (litCI "25") (range 0x30 0x35)]',
     'cat (litCI "25") (range 0x30 0x39)]', None),
    ("dec-octet 2 then any two digits", "Http/Grammar.lean", 'seq [litCI "2", range 0x30 0x34, DIGIT]',
     'seq [litCI "2", range 0x30 0x39, DIGIT]', None),
    ("dec-octet with a leading zero", "Http/Grammar.lean", "cat (range 0x31 0x39) DIGIT", "cat DIGIT DIGIT",
     None),
    ("dec-octet as 1*3DIGIT", "Http/Grammar.lean", DEC_OCTET, "def decOctet : Re := between 1 3 DIGIT",
     None),
    ("IP literal with a zone ID", "Http/Grammar.lean",
     'def IPliteral : Re := seq [litCI "[", alt IPv6address IPvFuture, litCI "]"]',
     'def IPliteral : Re := seq [litCI "[", any [IPv6address, seq [IPv6address, litCI "%25", '
     'plus (alt unreserved pctEncoded)], IPvFuture], litCI "]"]', None),
    ("host may be a bare IPv6 address", "Http/Grammar.lean",
     "def host : Re := any [IPliteral, IPv4address, regName]",
     "def host : Re := any [IPliteral, IPv6address, IPv4address, regName]", None),
    ("IPvFuture v case-sensitive", "Http/Grammar.lean", 'seq [litCI "v", plus HEXDIG',
     "seq [byte 0x76, plus HEXDIG", None),
]


def failures(out):
    m = re.search(r"(\d+) failures?", out)
    return int(m.group(1)) if m else None


def run(count):
    rows = []
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp) / "project"
        shutil.copytree(ROOT, work, ignore=shutil.ignore_patterns(".git"))
        for name, rel, old, new, equivalent in BUGS:
            path = work / rel
            original = (ROOT / rel).read_text()
            if original.count(old) != 1:
                sys.exit(f"{name}: the text to replace is not in {rel} exactly once")
            path.write_text(original.replace(old, new))
            build = subprocess.run(["lake", "build", EXE], cwd=work, capture_output=True, text=True)
            if build.returncode != 0:
                path.write_text(original)
                sys.exit(f"{name}: the tool does not build with this change\n{build.stdout[-2000:]}")
            test = subprocess.run([sys.executable, "tests/run_tests.py", "--count", str(count)],
                                  cwd=work, capture_output=True, text=True)
            path.write_text(original)
            n = failures(test.stdout + test.stderr)
            if n is None:
                sys.exit(f"{name}: the tests gave no failure count\n{(test.stdout + test.stderr)[-2000:]}")
            rows.append((name, rel, old, new, equivalent, n))
            print(f"{name}: {n} failures", flush=True)
    return rows


def write(rows, count):
    lines = [
        "# Planted bugs",
        "",
        "Written by `python3 tests/planted_bugs.py`. Each row is one small change to the",
        f"code, made in a copy. The tests ran on {count:,} inputs from their recorded seed",
        "against the changed tool. A bug is caught when they report failures.",
        "",
        "| Bug | File | Failures |",
        "|-----|------|----------|",
    ]
    for name, rel, _, _, equivalent, n in rows:
        cell = str(n) if n else ("0, equivalent: " + equivalent if equivalent else "0, NOT CAUGHT")
        lines.append(f"| {name} | `{rel}` | {cell} |")
    lines += ["", "## The changes", ""]
    for name, rel, old, new, _, _ in rows:
        lines += [f"**{name}** in `{rel}`:", "", "```", "- " + old.replace("\n", "\n- "),
                  "+ " + new.replace("\n", "\n+ "), "```", ""]
    (ROOT / "tests" / "PLANTED-BUGS.md").write_text("\n".join(lines))


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--count", type=int, default=COUNT)
    args = ap.parse_args()
    rows = run(args.count)
    write(rows, args.count)
    missed = [r[0] for r in rows if not r[5] and not r[4]]
    caught = sum(1 for r in rows if r[5])
    print(f"{caught} of {len(rows)} planted bugs caught; results in tests/PLANTED-BUGS.md")
    if missed:
        sys.exit("not caught: " + ", ".join(missed))


if __name__ == "__main__":
    main()
