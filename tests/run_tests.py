#!/usr/bin/env python3
"""Differential tests: the Lean request head parser against a copy of
the rules written here in Python.

The oracle is the grammar and the rules of RFC 9112, RFC 9110 and
RFC 3986, written in this script from the RFCs, separately from the Lean
code and the Lean spec: regular expressions for the request line, the
field lines and the request target, then the framing rules of RFC 9112
section 6.3 and the Host rule of section 3.2, with the choices the Lean
spec makes (see SPEC.md). The IPv6 rule of RFC 3986 is also checked
against Python's `ipaddress`, as a test of the oracle itself.

Inputs come from a recorded seed:

- valid heads: methods, targets in all four forms (paths with
  percent-escapes and queries, URIs with user info, registered names,
  IPv4, IPv6 in all its compressed forms, IPvFuture and ports, host and
  port, and `*`), versions, fields with values of visible characters,
  obs-text and inner whitespace, and Host, Content-Length and
  Transfer-Encoding fields in many forms, some valid and some not;
- empty lines before the request line, and octets after the head;
- mutations of valid heads: an octet replaced, deleted or inserted, a
  bare CR, a bare LF, a NUL, whitespace before a colon, a folded line, a
  line starting with whitespace, a tab or two spaces in the request
  line, a line repeated, the head cut short;
- fixed cases: the examples of RFC 9112 and the classic shapes of
  request smuggling, and malformed requests to the tool.

It builds the executable first, writes tests/TEST-RESULTS.md, and exits
non-zero if any input disagrees.
"""

import argparse
import ipaddress
import itertools
import platform
import random
import re
import subprocess
import sys
import threading
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXE = ROOT / ".lake" / "build" / "bin" / "httphead"
RESULTS = ROOT / "tests" / "TEST-RESULTS.md"
TIMEOUT = 1800
BUILD_TIMEOUT = 3600

# RFC 5234, Appendix B.1
DIGIT = rb"[0-9]"
HEXDIG = rb"[0-9A-Fa-f]"

# RFC 3986, Appendix A
UNRESERVED = rb"[A-Za-z0-9\-._~]"
PCT = rb"%[0-9A-Fa-f]{2}"
SUB_DELIMS = rb"[!$&'()*+,;=]"
PCHAR = rb"(?:" + UNRESERVED + rb"|" + PCT + rb"|" + SUB_DELIMS + rb"|[:@])"
SEGMENT = PCHAR + rb"*"
SEGMENT_NZ = PCHAR + rb"+"
QUERY = rb"(?:" + PCHAR + rb"|[/?])*"
SCHEME = rb"[A-Za-z][A-Za-z0-9+\-.]*"
USERINFO = rb"(?:" + UNRESERVED + rb"|" + PCT + rb"|" + SUB_DELIMS + rb"|:)*"
H16 = HEXDIG + rb"{1,4}"
DEC_OCTET = rb"(?:25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9][0-9]|[0-9])"
IPV4 = DEC_OCTET + rb"\." + DEC_OCTET + rb"\." + DEC_OCTET + rb"\." + DEC_OCTET
LS32 = rb"(?:" + H16 + rb":" + H16 + rb"|" + IPV4 + rb")"
H16C = H16 + rb":"


def _upto(n, r):
    return rb"(?:" + r + rb"){0," + str(n).encode() + rb"}"


def _times(n, r):
    return rb"(?:" + r + rb"){" + str(n).encode() + rb"}"


IPV6 = rb"(?:" + rb"|".join([
    _times(6, H16C) + LS32,
    rb"::" + _times(5, H16C) + LS32,
    rb"(?:" + H16 + rb")?::" + _times(4, H16C) + LS32,
    rb"(?:" + _upto(1, H16C) + H16 + rb")?::" + _times(3, H16C) + LS32,
    rb"(?:" + _upto(2, H16C) + H16 + rb")?::" + _times(2, H16C) + LS32,
    rb"(?:" + _upto(3, H16C) + H16 + rb")?::" + H16C + LS32,
    rb"(?:" + _upto(4, H16C) + H16 + rb")?::" + LS32,
    rb"(?:" + _upto(5, H16C) + H16 + rb")?::" + H16,
    rb"(?:" + _upto(6, H16C) + H16 + rb")?::",
]) + rb")"
IPVFUTURE = rb"[vV]" + HEXDIG + rb"+\.(?:" + UNRESERVED + rb"|" + SUB_DELIMS + rb"|:)+"
IP_LITERAL = rb"\[(?:" + IPV6 + rb"|" + IPVFUTURE + rb")\]"
REG_NAME = rb"(?:" + UNRESERVED + rb"|" + PCT + rb"|" + SUB_DELIMS + rb")*"
HOST = rb"(?:" + IP_LITERAL + rb"|" + IPV4 + rb"|" + REG_NAME + rb")"
PORT = DIGIT + rb"*"
AUTHORITY = rb"(?:" + USERINFO + rb"@)?" + HOST + rb"(?::" + PORT + rb")?"
PATH_ABEMPTY = rb"(?:/" + SEGMENT + rb")*"
PATH_ABSOLUTE = rb"/(?:" + SEGMENT_NZ + PATH_ABEMPTY + rb")?"
PATH_ROOTLESS = SEGMENT_NZ + PATH_ABEMPTY
HIER_PART = (rb"(?://" + AUTHORITY + PATH_ABEMPTY + rb"|" + PATH_ABSOLUTE + rb"|" + PATH_ROOTLESS
             + rb"|)")
ABSOLUTE_URI = SCHEME + rb":" + HIER_PART + rb"(?:\?" + QUERY + rb")?"

# RFC 9110, sections 4.1, 5.5, 5.6.2, 7.2
TCHAR = rb"[!#$%&'*+\-.^_`|~0-9A-Za-z]"
TOKEN = TCHAR + rb"+"
VCHAR_OR_OBS = rb"[\x21-\x7e\x80-\xff]"
FIELD_VALUE = rb"(?:" + VCHAR_OR_OBS + rb"(?:[ \t\x21-\x7e\x80-\xff]*" + VCHAR_OR_OBS + rb")?)?"
ABSOLUTE_PATH = rb"(?:/" + SEGMENT + rb")+"
HOST_FIELD = re.compile(HOST + rb"(?::" + PORT + rb")?")

# RFC 9112, sections 3.2.1 to 3.2.4
ORIGIN_FORM = ABSOLUTE_PATH + rb"(?:\?" + QUERY + rb")?"
AUTHORITY_FORM = HOST + rb":" + PORT
REQUEST_TARGET = rb"(?:" + ORIGIN_FORM + rb"|" + ABSOLUTE_URI + rb"|" + AUTHORITY_FORM + rb"|\*)"

# RFC 9112, sections 3 and 5: the request line and a field line.
REQUEST_LINE = re.compile(rb"(" + TOKEN + rb") (" + REQUEST_TARGET + rb") HTTP/([0-9])\.([0-9])")
FIELD_LINE = re.compile(rb"(" + TOKEN + rb"):[ \t]*(" + FIELD_VALUE + rb")[ \t]*")
IPV6_RE = re.compile(IPV6)
TARGET_RE = re.compile(REQUEST_TARGET)


def reference(bs):
    """(method, target, major, minor, fields, rest) for the head at the
    start of `bs`, or None when there is none."""
    i = 0
    while bs[i:i + 2] == b"\r\n":
        i += 2
    # The head ends at the first empty line; no line in it may hold a CR
    # or LF of its own.
    end = bs.find(b"\r\n\r\n", i)
    if end < 0:
        return None
    lines = bs[i:end].split(b"\r\n")
    if any(b"\r" in l or b"\n" in l for l in lines):
        return None
    m = REQUEST_LINE.fullmatch(lines[0])
    if not m:
        return None
    fields = []
    for line in lines[1:]:
        f = FIELD_LINE.fullmatch(line)
        if not f:
            return None
        fields.append((f.group(1), f.group(2)))
    return m.group(1), m.group(2), int(m.group(3)), int(m.group(4)), fields, bs[end + 4:]


def framing(head):
    """How a server frames the body after the head, or None when it must
    reject it: RFC 9112 sections 3.2 and 6.3, with the choices of SPEC.md."""
    _, _, major, minor, fields, _ = head
    if major != 1:
        return None

    def named(n):
        return [v for k, v in fields if k.lower() == n]

    hosts = named(b"host")
    if len(hosts) > 1 or (minor >= 1 and len(hosts) != 1):
        return None
    if any(not HOST_FIELD.fullmatch(v) for v in hosts):
        return None
    te, cl = named(b"transfer-encoding"), named(b"content-length")
    if te and cl:
        return None
    if te:
        if minor < 1 or len(te) != 1 or te[0].lower() != b"chunked":
            return None
        return "chunked"
    if cl:
        if len(cl) != 1 or not re.fullmatch(rb"[0-9]+", cl[0]):
            return None
        return f"length {int(cl[0])}"
    return "length 0"


def printed(head):
    method, target, major, minor, fields, _ = head
    out = method + b" " + target + b" HTTP/" + str(major).encode() + b"." + str(minor).encode() + b"\r\n"
    for k, v in fields:
        out += k + b": " + v + b"\r\n"
    return out + b"\r\n"


def answer(bs):
    head = reference(bs)
    if head is None:
        return "REJECT"
    fr = framing(head)
    return f"OK\t{printed(head).hex()}\t{head[5].hex()}\t{fr or 'reject'}"


# Generators

METHODS = [b"GET", b"POST", b"PUT", b"DELETE", b"HEAD", b"OPTIONS", b"CONNECT", b"PATCH", b"TRACE"]
TCHARS = b"!#$%&'*+-.^_`|~0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
UNRES = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
SUBS = b"!$&'()*+,;="


def pick(rng, s):
    return bytes([rng.choice(s)])


def token(rng, n=None):
    return b"".join(pick(rng, TCHARS) for _ in range(n or rng.randint(1, 8)))


def pct(rng):
    hexd = b"0123456789ABCDEFabcdef"
    return b"%" + pick(rng, hexd) + pick(rng, hexd)


def pchars(rng, n, extra=b":@"):
    out = b""
    for _ in range(n):
        r = rng.random()
        if r < 0.7:
            out += pick(rng, UNRES)
        elif r < 0.8:
            out += pct(rng)
        elif r < 0.92:
            out += pick(rng, SUBS)
        else:
            out += pick(rng, extra or UNRES)
    return out


def path(rng):
    return b"".join(b"/" + pchars(rng, rng.randint(0, 6)) for _ in range(rng.randint(1, 4)))


def query(rng):
    return pchars(rng, rng.randint(0, 8), b":@/?")


def ipv4(rng):
    def octet():
        return str(rng.choice([0, 1, 9, 10, 99, 100, 199, 200, 249, 250, 255, rng.randint(0, 255)])).encode()
    return b".".join(octet() for _ in range(4))


def h16(rng):
    return b"".join(pick(rng, b"0123456789abcdefABCDEF") for _ in range(rng.randint(1, 4)))


def ipv6(rng):
    """An IPv6 address, plain or compressed with "::", sometimes with an
    IPv4 tail, and sometimes with one group too many for "::"."""
    v4 = rng.random() < 0.2
    width = 6 if v4 else 8
    if rng.random() < 0.3:
        s = b":".join(h16(rng) for _ in range(width))
        if v4:
            s += b":"
    else:
        k = rng.randint(0, width)
        a = rng.randint(0, k)
        s = b":".join(h16(rng) for _ in range(a)) + b"::" + b":".join(h16(rng) for _ in range(k - a))
        if v4 and not s.endswith(b":"):
            s += b":"
    return s + ipv4(rng) if v4 else s


def host(rng):
    r = rng.random()
    if r < 0.5:
        return b".".join(pchars(rng, rng.randint(1, 8), b"") for _ in range(rng.randint(1, 3)))
    if r < 0.7:
        return ipv4(rng)
    if r < 0.9:
        return b"[" + ipv6(rng) + b"]"
    if r < 0.95:
        tail = b"".join(pick(rng, UNRES + SUBS + b":") for _ in range(rng.randint(1, 5)))
        return b"[v" + h16(rng) + b"." + (tail if rng.random() < 0.8 else pchars(rng, 3)) + b"]"
    return b""


def port(rng):
    return str(rng.choice([80, 443, 8080, 0, 65535, rng.randint(0, 99999)])).encode() if rng.random() < 0.9 else b""


def target(rng):
    r = rng.random()
    if r < 0.55:
        return path(rng) + (b"?" + query(rng) if rng.random() < 0.4 else b"")
    if r < 0.8:
        scheme = rng.choice([b"http", b"https", b"ws", b"a+b.c-d", b"x"])
        auth = b""
        if rng.random() < 0.15:
            auth += pchars(rng, rng.randint(0, 5), b":") + b"@"
        auth += host(rng)
        if rng.random() < 0.5:
            auth += b":" + port(rng)
        hp = rng.choice([b"//" + auth + (path(rng) if rng.random() < 0.6 else b""),
                         path(rng), pchars(rng, rng.randint(1, 5)), b""])
        return scheme + b":" + hp + (b"?" + query(rng) if rng.random() < 0.3 else b"")
    if r < 0.95:
        return host(rng) + b":" + port(rng)
    return b"*"


def value(rng):
    r = rng.random()
    if r < 0.1:
        return b""
    out = b""
    for _ in range(rng.randint(1, 20)):
        x = rng.random()
        if x < 0.8:
            out += bytes([rng.randint(0x21, 0x7E)])
        elif x < 0.9:
            out += bytes([rng.randint(0x80, 0xFF)])
        else:
            out += rng.choice([b" ", b"\t"])
    return out


def ows(rng):
    return rng.choice([b"", b" ", b" ", b"\t", b"  ", b" \t "])


def host_value(rng):
    r = rng.random()
    if r < 0.95:
        h = host(rng)
        return h + (b":" + port(rng) if rng.random() < 0.3 else b"")
    return rng.choice([b"a b", b"x/y", b"[::1", b"h:p", b"@x", b"%zz", b"x?"])


CL_VALUES = [b"0", b"5", b"007", b"18446744073709551616", b"+5", b"-1", b"5, 5", b"5,5", b"0x5",
             b"5 5", b" ", b"", b"1e3"]
TE_VALUES = [b"chunked", b"Chunked", b"CHUNKED", b"gzip, chunked", b"chunked, identity", b"xchunked",
             b"chunked;q=1", b"identity", b"chunked,", b",chunked", b"chunk", b"chunked chunked"]
NAMES_CASED = {b"host": [b"Host", b"host", b"HOST", b"hOsT"],
               b"content-length": [b"Content-Length", b"content-length", b"CONTENT-LENGTH"],
               b"transfer-encoding": [b"Transfer-Encoding", b"transfer-encoding", b"TRANSFER-ENCODING"]}


def valid_head(rng):
    """A head that fits the grammar, which the framing may still reject."""
    method = rng.choice(METHODS) if rng.random() < 0.8 else token(rng)
    major, minor = rng.choice([(1, 1)] * 14 + [(1, 0)] * 4 + [(1, 2), (2, 0), (0, 9), (1, 9)])
    line = method + b" " + target(rng) + b" HTTP/" + str(major).encode() + b"." + str(minor).encode()
    fields = []
    nhost = rng.choice([1] * 16 + [0, 2])
    for _ in range(nhost):
        fields.append((rng.choice(NAMES_CASED[b"host"]), host_value(rng)))
    x = rng.random()
    if x < 0.3:
        for _ in range(rng.choice([1] * 6 + [2])):
            fields.append((rng.choice(NAMES_CASED[b"content-length"]),
                           rng.choice(CL_VALUES) if rng.random() < 0.25 else str(rng.randint(0, 10 ** 6)).encode()))
    elif x < 0.5:
        for _ in range(rng.choice([1] * 6 + [2])):
            fields.append((rng.choice(NAMES_CASED[b"transfer-encoding"]),
                           rng.choice(TE_VALUES) if rng.random() < 0.5 else rng.choice(TE_VALUES[:3])))
    elif x < 0.55:
        fields.append((rng.choice(NAMES_CASED[b"transfer-encoding"]), rng.choice(TE_VALUES)))
        fields.append((rng.choice(NAMES_CASED[b"content-length"]), rng.choice(CL_VALUES)))
    for _ in range(rng.randint(0, 5)):
        fields.append((token(rng), value(rng)))
    rng.shuffle(fields)
    out = b"\r\n" * rng.choice([0] * 9 + [1, 2])
    out += line + b"\r\n"
    for k, v in fields:
        out += k + b":" + ows(rng) + v + ows(rng) + b"\r\n"
    out += b"\r\n"
    if rng.random() < 0.3:
        out += rng.choice([b"hello", b"0\r\n\r\n", b"GET / HTTP/1.1\r\n\r\n", bytes([rng.randint(0, 255)])])
    return out


def mutate(rng, bs):
    """One change of a kind that request smuggling and loose parsers turn
    on."""
    kind = rng.randrange(13)
    i = rng.randrange(len(bs) + 1)
    if kind == 0:
        return bs[:i] + bytes([rng.randrange(256)]) + bs[i + 1:]
    if kind == 1:
        return bs[:i] + bs[i + 1:]
    if kind == 2:
        return bs[:i] + bytes([rng.randrange(256)]) + bs[i:]
    if kind == 3:
        return bs[:i] + b"\r" + bs[i:]
    if kind == 4:
        return bs[:i] + b"\n" + bs[i:]
    if kind == 5:
        return bs[:i] + b"\x00" + bs[i:]
    if kind == 6:
        j = bs.find(b":")
        return bs[:j] + rng.choice([b" ", b"\t"]) + bs[j:] if j > 0 else bs + b" "
    if kind == 7:
        j = bs.find(b"\r\n")
        k = bs.find(b"\r\n", j + 2)
        return bs[:k] + b"\r\n" + rng.choice([b" ", b"\t"]) + b"folded" + bs[k:] if k > 0 else bs
    if kind == 8:
        j = bs.find(b"\r\n")
        return bs[:j + 2] + rng.choice([b" ", b"\t"]) + bs[j + 2:] if j >= 0 else bs
    if kind == 9:
        j = bs.find(b" ")
        return bs[:j] + rng.choice([b"\t", b"  ", b"\x0b", b"\x0c"]) + bs[j + 1:] if j >= 0 else bs
    if kind == 10:
        lines = bs.split(b"\r\n")
        if len(lines) > 2:
            k = rng.randrange(1, len(lines) - 1)
            lines.insert(k, lines[k])
        return b"\r\n".join(lines)
    if kind == 11:
        return bs[:i]
    return bs.replace(b"\r\n", b"\n", 1) if rng.random() < 0.5 else bs.replace(b"\r\n", b"\r", 1)


FIXED = [
    # RFC 9112, sections 3.2.1 to 3.2.4, and RFC 9110, section 7.2
    b"GET /where?q=now HTTP/1.1\r\nHost: www.example.org\r\n\r\n",
    b"GET http://www.example.org/pub/WWW/TheProject.html HTTP/1.1\r\nHost: www.example.org\r\n\r\n",
    b"CONNECT www.example.com:80 HTTP/1.1\r\nHost: www.example.com\r\n\r\n",
    b"OPTIONS * HTTP/1.1\r\nHost: www.example.org:8001\r\n\r\n",
    b"OPTIONS http://www.example.org:8001 HTTP/1.1\r\nHost: www.example.org:8001\r\n\r\n",
    b"GET /pub/WWW/ HTTP/1.1\r\nHost: www.example.org\r\n\r\n",
    # RFC 9112, section 6.1
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: gzip, chunked\r\n\r\n",
    # Smuggling shapes
    b"POST /a HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nContent-Length: 6\r\n\r\nhello",
    b"POST /a HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nContent-Length: 5\r\n\r\nhello",
    b"POST /a HTTP/1.1\r\nHost: x\r\nContent-Length: 5, 5\r\n\r\nhello",
    b"POST /a HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nTransfer-Encoding: chunked\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nContent-Length: 5\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: xchunked\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding:  chunked\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding:\tchunked\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked, identity\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nTransfer-Encoding: x\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding : chunked\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\r\nX: y\r\n Transfer-Encoding: chunked\r\n\r\n",
    b"POST /a HTTP/1.1\r\n Host: x\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\nTransfer-Encoding: chunked\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\rTransfer-Encoding: chunked\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\x00\r\n\r\n",
    b"POST /a HTTP/1.0\r\nTransfer-Encoding: chunked\r\n\r\n",
    b"POST /a HTTP/1.0\r\nContent-Length: 3\r\n\r\nabc",
    b"GET /a HTTP/1.1\r\nHost: x\r\nContent-Length: +5\r\n\r\n",
    b"GET\t/a HTTP/1.1\r\nHost: x\r\n\r\n",
    b"GET  /a HTTP/1.1\r\nHost: x\r\n\r\n",
    b"GET /a HTTP/1.1 \r\nHost: x\r\n\r\n",
    b"GET /a\x0bHTTP/1.1\r\nHost: x\r\n\r\n",
    b"GET /a#frag HTTP/1.1\r\nHost: x\r\n\r\n",
    b"GET /a b HTTP/1.1\r\nHost: x\r\n\r\n",
    b"GET /%zz HTTP/1.1\r\nHost: x\r\n\r\n",
    b"GET http://[::1]:80/ HTTP/1.1\r\nHost: [::1]:80\r\n\r\n",
    b"GET http://[::ffff:192.0.2.1]/ HTTP/1.1\r\nHost: [::ffff:192.0.2.1]\r\n\r\n",
    b"GET http://[1::2::3]/ HTTP/1.1\r\nHost: x\r\n\r\n",
    b"GET http://[vF.a:b]/ HTTP/1.1\r\nHost: x\r\n\r\n",
    # The Host rule
    b"GET / HTTP/1.1\r\n\r\n",
    b"GET / HTTP/1.1\r\nHost: a\r\nHost: a\r\n\r\n",
    b"GET / HTTP/1.1\r\nHost:\r\n\r\n",
    b"GET / HTTP/1.1\r\nHost: a b\r\n\r\n",
    b"GET / HTTP/1.0\r\n\r\n",
    b"GET / HTTP/1.0\r\nHost: a\r\nHost: b\r\n\r\n",
    # Versions
    b"GET / HTTP/2.0\r\nHost: a\r\n\r\n",
    b"GET / HTTP/1.2\r\nHost: a\r\n\r\n",
    b"GET / http/1.1\r\nHost: a\r\n\r\n",
    b"GET / HTTP/1.10\r\nHost: a\r\n\r\n",
    b"GET / HTTP/1\r\nHost: a\r\n\r\n",
    # Empty lines first, and a head cut short
    b"\r\n\r\nGET / HTTP/1.1\r\nHost: a\r\n\r\n",
    b"\n\r\nGET / HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET / HTTP/1.1\r\nHost: a\r\n",
    b"",
    b"\r\n",
]

MALFORMED = [
    ("frob 30", "unknown operation"),
    ("HEAD 30", "operations are lower case"),
    ("head", "no argument"),
    ("head 3", "an odd number of hex digits"),
    ("head 3G", "not a hex digit"),
    ("head 3A", "hex digits are lower case"),
    ("head 30 30", "two arguments"),
    (" head 30", "a leading space"),
    ("head  30", "two spaces"),
]


def cases(seed, count):
    """(label, request, expected answer, mutated) for each input."""
    rng = random.Random(seed)
    fixed = [("error", req, "error", False) for req, _ in MALFORMED]
    fixed += [("fixed", f"head {bs.hex()}", answer(bs), False) for bs in FIXED]
    made = 0
    for item in fixed[:count]:
        yield item
        made += 1
    while made < count:
        bs = valid_head(rng)
        mutated = rng.random() < 0.35
        if mutated:
            new = mutate(rng, bs)
            if new == bs:
                continue
            bs = new
        yield ("mutated" if mutated else "valid", f"head {bs.hex()}", answer(bs), mutated)
        made += 1


def check_ipv6_oracle(seed, n=20000):
    """The RFC 3986 IPv6 rule as written here against `ipaddress`, on
    generated addresses and on mutations of them. Returns the count and
    the disagreements."""
    rng = random.Random(seed + 1)
    bad = []
    for _ in range(n):
        a = ipv6(rng)
        if rng.random() < 0.4:
            a = mutate_text(rng, a)
        ours = IPV6_RE.fullmatch(a) is not None
        try:
            ipaddress.IPv6Address(a.decode("latin-1"))
            theirs = b"%" not in a
        except ValueError:
            theirs = False
        if ours != theirs:
            bad.append(a)
    return n, bad


def mutate_text(rng, s):
    i = rng.randrange(len(s) + 1)
    k = rng.randrange(4)
    if k == 0:
        return s[:i] + pick(rng, b"0123456789abcdef:.g") + s[i + 1:]
    if k == 1:
        return s[:i] + s[i + 1:]
    if k == 2:
        return s[:i] + pick(rng, b"0123456789abcdef:.") + s[i:]
    return s + b":" + h16(rng)


def run_tool(data, timeout=TIMEOUT):
    """The tool's answer lines for `data`, and a note on how the run
    failed, or None. No right answer is longer than its request plus 64
    bytes, so a tool that writes more than that is stopped."""
    raw = data.encode("utf-8")
    limit = 2 * len(raw) + 64 * (data.count("\n") + 1)
    try:
        proc = subprocess.Popen([str(EXE), "serve"], stdin=subprocess.PIPE,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except OSError as e:
        return [], f"could not run {EXE.relative_to(ROOT)}: {e.strerror or e}"
    out, err = bytearray(), bytearray()

    def feed():
        try:
            proc.stdin.write(raw)
            proc.stdin.close()
        except (BrokenPipeError, ValueError):
            pass

    def drain(stream, buf, cap):
        while chunk := stream.read1(1 << 16):
            buf += chunk
            if len(buf) > cap:
                proc.kill()
                return

    threads = [threading.Thread(target=feed),
               threading.Thread(target=drain, args=(proc.stdout, out, limit)),
               threading.Thread(target=drain, args=(proc.stderr, err, 1 << 20))]
    for t in threads:
        t.start()
    problem = None
    try:
        proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        proc.kill()
        problem = f"no end after {timeout} seconds"
    for t in threads:
        t.join()
    proc.wait()
    if len(out) > limit:
        problem = problem or f"more than {limit} bytes of output, stopped"
    elif proc.returncode != 0 and not problem:
        tail = " / ".join(err.decode("utf-8", "backslashreplace").splitlines()[-3:])
        problem = f"exit status {proc.returncode}: {tail}"
    text = bytes(out).decode("utf-8", "backslashreplace")
    if text and not text.endswith("\n"):
        problem = problem or "the last answer has no LF"
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    return lines, problem


def escape(bs):
    return "".join(chr(b) if 0x20 <= b < 0x7F and b != 0x5C else f"\\x{b:02x}" for b in bs)


def check_mode(items, limit=2000):
    """Runs `check` mode on the first `limit` inputs, each sent alone on
    standard input. Each must print the head, a line for each field and
    the framing, or `invalid`, and exit 0 only for a framed request."""
    problems = []
    done = 0
    for label, req, _, _ in items:
        if label == "error" or done >= limit:
            continue
        bs = bytes.fromhex(req.split(" ")[1])
        head = reference(bs)
        if head is None:
            want, code_want = ["invalid"], 1
        else:
            method, target, major, minor, fields, _ = head
            want = [f"{escape(method)} {escape(target)} HTTP/{major}.{minor}"]
            want += [f"{escape(k)}: {escape(v)}" for k, v in fields]
            fr = framing(head)
            want.append(fr or "reject")
            code_want = 0 if fr else 1
        run = subprocess.run([str(EXE), "check"], input=bs, capture_output=True, timeout=300)
        got = run.stdout.decode("utf-8", "backslashreplace").split("\n")[:-1]
        if got != want or run.returncode != code_want:
            problems.append((f"check < {bs[:80]!r}", f"{want} exit {code_want}",
                             f"{got} exit {run.returncode}"))
        done += 1
    run = subprocess.run([str(EXE)], capture_output=True, timeout=300)
    if run.returncode != 2:
        problems.append(("no arguments", "usage and exit 2", f"exit {run.returncode}"))
    return done, problems


def oracle():
    return (f"Python {platform.python_version()}: the grammar and framing rules of RFC 9112, "
            f"RFC 9110 and RFC 3986 written in this script, with its IPv6 rule checked "
            f"against `ipaddress`")


def lean_version():
    try:
        out = subprocess.run(["lake", "env", "lean", "--version"], cwd=ROOT,
                             capture_output=True, text=True, errors="backslashreplace",
                             timeout=300)
        first = out.stdout.strip().splitlines()[:1]
        return first[0] if first else "unknown"
    except (OSError, subprocess.TimeoutExpired):
        return "unknown"


def count(text):
    n = int(text)
    if n < 1:
        raise argparse.ArgumentTypeError("the count must be at least 1")
    return n


def write(lines):
    RESULTS.write_text("\n".join(lines), encoding="utf-8")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=20261025)
    ap.add_argument("--count", type=count, default=300_000)
    args = ap.parse_args()

    # Always build, so the tests never run an executable older than the code.
    try:
        build = subprocess.run(["lake", "build", "httphead"], cwd=ROOT, capture_output=True,
                               text=True, errors="backslashreplace", timeout=BUILD_TIMEOUT)
        built, log = build.returncode == 0, build.stdout + build.stderr
    except (OSError, subprocess.TimeoutExpired) as e:
        built, log = False, str(e)
    if not built:
        write(["# Test results", "", f"- Oracle: {oracle()}", f"- Seed: {args.seed}",
               "- Inputs: 0", "- Failures: 1 (`lake build httphead` failed)", ""])
        sys.exit("lake build httphead failed:\n" + log)

    ipv6_count, ipv6_bad = check_ipv6_oracle(args.seed)
    failures = [(f"IPv6 rule on {a!r}", "the same verdict as ipaddress", "a different one")
                for a in ipv6_bad]

    items = list(cases(args.seed, args.count))
    # Every seventh request ends in CR LF, which the tool must take as LF.
    out, problem = run_tool("".join(req + ("\r\n" if i % 7 == 6 else "\n")
                                    for i, (_, req, _, _) in enumerate(items)))
    if problem:
        failures.append(("(whole run)", "a clean run", problem))
    for item, got in itertools.zip_longest(items, out):
        if item is None:
            failures.append(("(no request)", "nothing", got))
        elif got != item[2]:
            failures.append((item[1], item[2], "(no answer)" if got is None else got))

    checked, check_problems = check_mode(items)
    failures += check_problems

    got, problem = run_tool(f"head {FIXED[0].hex()}", timeout=60)
    eof_right = got == [answer(FIXED[0])] and not problem
    if not eof_right:
        failures.append(("a last line with no LF", answer(FIXED[0]), f"{got} {problem or ''}"))

    by_label = {}
    for label, _, _, _ in items:
        by_label[label] = by_label.get(label, 0) + 1
    heads = [want for label, _, want, _ in items if label != "error"]
    read = [w for w in heads if w.startswith("OK")]
    frames = [w.split("\t")[3] for w in read]
    targets = {"origin": 0, "absolute": 0, "authority": 0, "asterisk": 0, "IPv6": 0}
    for label, req, want, _ in items:
        if want.startswith("OK"):
            t = reference(bytes.fromhex(req.split(" ")[1]))[1]
            if t == b"*":
                targets["asterisk"] += 1
            elif t.startswith(b"/"):
                targets["origin"] += 1
            elif re.fullmatch(ABSOLUTE_URI, t):
                targets["absolute"] += 1
            else:
                targets["authority"] += 1
            if b"[" in t:
                targets["IPv6"] += 1
    mutated = sum(1 for item in items if item[3])
    malformed = [g for item, g in zip(items, out) if item[0] == "error"]

    lines = [
        "# Test results",
        "",
        "Written by `tests/run_tests.py`. Rerun it to check these numbers.",
        "",
        f"- Oracle: {oracle()}",
        f"- Lean: {lean_version()}",
        f"- Seed: {args.seed}",
        f"- Inputs: {len(items)}",
        f"- Mutated: {mutated} of the inputs are mutated heads",
        f"- By kind: " + ", ".join(f"{k} {v}" for k, v in sorted(by_label.items())),
        f"- Heads read: {len(read)} of {len(heads)}, and {len(heads) - len(read)} refused by the grammar",
        f"- Targets of the heads read: {targets['origin']} origin-form, {targets['absolute']} "
        f"absolute-form, {targets['authority']} authority-form (or both: `a:1` fits both), "
        f"{targets['asterisk']} asterisk-form; {targets['IPv6']} with an IP literal",
        f"- Framing of the heads read: {sum(1 for f in frames if f == 'length 0')} with no body, "
        f"{sum(1 for f in frames if f.startswith('length') and f != 'length 0')} with a length, "
        f"{frames.count('chunked')} chunked, {frames.count('reject')} rejected",
        f"- IPv6 addresses checked against `ipaddress`, to test the oracle: {ipv6_count}, "
        f"{len(ipv6_bad)} disagreements",
        f"- Malformed requests answered `error`: {malformed.count('error')} of "
        f"{by_label.get('error', 0)}",
        f"- Requests ending in CR LF: every seventh, {len(items) // 7}",
        f"- Inputs also given to `httphead check` on standard input: {checked}, and once with no "
        f"arguments",
        f"- A last line with no LF, sent alone, answered right: {'yes' if eof_right else 'no'}",
        f"- Failures: {len(failures)}",
        "",
    ]
    if failures:
        lines += ["## Failures", ""]
        lines += [f"- `{req[:160]!r}`: expected `{want[:120]!r}`, got `{got[:120]!r}`"
                  for req, want, got in failures[:50]]
        lines.append("")
    write(lines)
    agree = sum(1 for item, got in zip(items, out) if got == item[2])
    print(f"{agree}/{len(items)} inputs agree, {len(failures)} failures; results in {RESULTS}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
