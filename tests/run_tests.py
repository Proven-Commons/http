#!/usr/bin/env python3
"""Differential tests: the Lean request head parser against a copy of
the rules written here in Python.

The oracle is the grammar and the rules of RFC 9112, RFC 9110 and
RFC 3986, written in this script from the RFCs, separately from the Lean
code and the Lean spec: regular expressions for the request line, the
field lines and the request target, then the Host rule of RFC 9112
section 3.2, the CONNECT rule of RFC 9110 section 9.3.6, the rule of
RFC 9110 sections 4.2.1, 4.2.2 and 4.2.4 for http and https targets, the
rule of RFC 9112 section 3.3 that the host of the target URI built from
a Host value or a CONNECT target is not empty, and the framing rules of
RFC 9112 section 6.3, with the choices the Lean spec makes (see
SPEC.md). Transfer-Encoding is read as one list made of all its field
lines (RFC 9110 section 5.2), in which empty elements do not count
(section 5.6.1.2). The IPv6 rule of RFC 3986 is also checked against
Python's `ipaddress`, as a test of the oracle itself.

Inputs come from a recorded seed:

- valid heads: methods, targets in all four forms (paths with
  percent-escapes and queries, URIs with user info, registered names,
  IPv4, IPv6 in all its compressed forms, IPvFuture with `v` or `V`, and
  ports, host and port, and `*`), versions, fields with values of
  visible characters, obs-text and inner whitespace, and Host,
  Content-Length and Transfer-Encoding fields in many forms, some valid
  and some not;
- hosts that RFC 3986 does not allow, in targets and Host values: an
  IPv6 literal whose IPv4 tail has an octet above 255 or with a leading
  zero, an IP literal with an RFC 6874 zone ID such as
  `[fe80::1%25eth0]`, and an IPv6 address with no brackets;
- Host values that are empty, and Host values with an empty host before
  a colon, such as `:80` and `:`;
- CONNECT, and `connect`, which is another method, with host and port
  targets whose port is empty, 0, above 65535, long or with leading
  zeros, with an empty host, such as `:443`, and with targets of the
  other three forms;
- http and https targets, with the scheme in any case: with a host
  (registered names and IP literals, ports, paths and queries), with an
  empty host such as `http:///a`, with no `//` such as `http:/a`, with
  userinfo such as `http://u@a/`, and with an empty port; `CONNECT
  http:80`, which names the host `http`, and the same target with
  another method; and schemes such as `httpx` and `ws`, which the rule
  does not cover;
- Transfer-Encoding lists with empty elements, such as `chunked,` and
  `, chunked`, and heads with several Transfer-Encoding lines: all but
  one empty or only commas, chunked in two of them, or chunked split
  over two;
- empty lines before the request line, and octets after the head;
- mutations of valid heads: an octet replaced, deleted or inserted, a
  bare CR, a bare LF, a NUL, whitespace before a colon, a folded line, a
  line starting with whitespace, a tab or two spaces in the request
  line, a line repeated, the head cut short;
- fixed cases: the examples of RFC 9112, the classic shapes of request
  smuggling, every input of `Spec.head_vectors` in Spec.lean, the inputs
  that the reviews of these tests named, and malformed requests to the
  tool.

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
# Host = uri-host [ ":" port ]
HOST_FIELD = re.compile(rb"(?P<host>" + HOST + rb")(?::" + PORT + rb")?")

# RFC 9112, sections 3.2.1 to 3.2.4
ORIGIN_FORM = ABSOLUTE_PATH + rb"(?:\?" + QUERY + rb")?"
AUTHORITY_FORM = HOST + rb":" + PORT
REQUEST_TARGET = rb"(?:" + ORIGIN_FORM + rb"|" + ABSOLUTE_URI + rb"|" + AUTHORITY_FORM + rb"|\*)"

# RFC 9112, sections 3 and 5: the request line and a field line.
REQUEST_LINE = re.compile(rb"(" + TOKEN + rb") (" + REQUEST_TARGET + rb") HTTP/([0-9])\.([0-9])")
FIELD_LINE = re.compile(rb"(" + TOKEN + rb"):[ \t]*(" + FIELD_VALUE + rb")[ \t]*")
IPV6_RE = re.compile(IPV6)
TARGET_RE = re.compile(REQUEST_TARGET)

# RFC 9110, section 5.6.1.2: a recipient reads a list `#element` as
# [ element ] *( OWS "," OWS [ element ] ), and "Empty elements do not
# contribute to the count of elements present". So a list of the one
# coding chunked has chunked once, and any number of empty elements
# before and after it. Coding names are case-insensitive (RFC 9112,
# section 7).
OWS = rb"[ \t]*"
EMPTY_ELEMENTS = rb"(?:" + OWS + rb"," + OWS + rb")*"
CHUNKED_ALONE = re.compile(EMPTY_ELEMENTS + rb"[Cc][Hh][Uu][Nn][Kk][Ee][Dd]" + EMPTY_ELEMENTS)

# RFC 9110, section 9.3.6: the target of CONNECT is the host and the port
# of the tunnel, "separated by a colon": `uri-host ":" port`.
CONNECT_TARGET = re.compile(rb"(?P<host>" + HOST + rb"):(?P<port>" + PORT + rb")")

# RFC 9110, sections 4.2.1 and 4.2.2:
#   http-URI  = "http"  "://" authority path-abempty [ "?" query ]
#   https-URI = "https" "://" authority path-abempty [ "?" query ]
# An authority with no userinfo is host [ ":" port ] (RFC 3986, section
# 3.2), and after it come path-abempty and the query.
HOST_PORT = re.compile(rb"(" + HOST + rb")(?::" + PORT + rb")?")
PATH_QUERY = re.compile(PATH_ABEMPTY + rb"(?:\?" + QUERY + rb")?")


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


def target_uri_host_ok(host):
    """RFC 9112, section 3.3: for a target that is not in absolute-form,
    the target URI is "the scheme, "://", authority, and combined path
    and query component", and its authority is the CONNECT target, or
    else the Host value. The scheme here is http or https, so by RFC 9110
    sections 4.2.1 and 4.2.2 the host in that authority must not be
    empty: "A recipient that processes such a URI reference MUST reject
    it as invalid"."""
    return host != b""


def host_ok(value):
    """The Host rule of RFC 9112, section 3.2, for one Host value: it is
    `uri-host [ ":" port ]` (RFC 9110, section 7.2), with a host that is
    not empty, as target_uri_host_ok says. An empty value is allowed:
    section 3.2 has a client send one when the target URI has no
    authority, and section 3.3 says that then "the server can reject the
    request or determine whether a configured default applies"."""
    if value == b"":
        return True
    m = HOST_FIELD.fullmatch(value)
    return m is not None and target_uri_host_ok(m.group("host"))


def connect_ok(method, target):
    """RFC 9110, section 9.3.6: "A server MUST reject a CONNECT request
    that targets an empty or invalid port number". The method token is
    case-sensitive (section 9.1), so only `CONNECT` is held to this. Its
    target must be a host and a port, the host must not be empty (see
    target_uri_host_ok), and here a valid port is from 1 to 65535."""
    if method != b"CONNECT":
        return True
    m = CONNECT_TARGET.fullmatch(target)
    if not m or not target_uri_host_ok(m.group("host")):
        return False
    # Leading zeros do not change the number. More than five digits after
    # them is above 65535, and int() is not given very long strings.
    digits = m.group("port").lstrip(b"0")
    return 1 <= len(digits) <= 5 and int(digits) <= 65535


def http_scheme(target):
    """Whether the scheme of `target` is http or https. Schemes are
    case-insensitive (RFC 3986, section 3.1), and a scheme ends at the
    first colon."""
    scheme, colon, _ = target.partition(b":")
    return bool(colon) and scheme.lower() in (b"http", b"https")


def http_problem(target):
    """Why a target whose scheme is http or https is not allowed, or None.
    RFC 9110, sections 4.2.1 and 4.2.2: such a URI is `scheme "://"
    authority path-abempty [ "?" query ]`, and "A recipient that
    processes such a URI reference MUST reject it as invalid" when its
    host is empty. Section 4.2.4: "a recipient SHOULD parse for userinfo
    and treat its presence as an error"."""
    rest = target.partition(b":")[2]
    if not rest.startswith(b"//"):
        return "no authority"
    # RFC 3986, section 3.2: the authority "is terminated by the next
    # slash ("/"), question mark ("?"), or number sign ("#") character,
    # or by the end of the URI". Section 3.2.1: userinfo is followed by
    # "@", which no host holds.
    end = 2
    while end < len(rest) and rest[end] not in b"/?#":
        end += 1
    authority, tail = rest[2:end], rest[end:]
    if b"@" in authority:
        return "userinfo"
    hp = HOST_PORT.fullmatch(authority)
    if hp and hp.group(1) == b"":
        return "empty host"
    if not hp or not PATH_QUERY.fullmatch(tail):
        return "other"
    return None


def http_target_ok(method, target):
    """The rule of RFC 9110, sections 4.2.1, 4.2.2 and 4.2.4, for a target
    whose scheme is http or https. The target of CONNECT is a host and a
    port (section 9.3.6), in authority-form, which has no scheme, so the
    rule is not for it, and `CONNECT http:80` names the host `http`. Any
    other method, `connect` too, is held to it."""
    return method == b"CONNECT" or not http_scheme(target) or http_problem(target) is None


def combined(values):
    """The combined field value of field lines with these values (RFC
    9110, section 5.2): the values in order, with a comma between each."""
    return b",".join(values)


def framing(head):
    """How this library frames the body after the head, or None when this
    library refuses it: RFC 9112 sections 3.2 and 6.3 and RFC 9110
    sections 4.2.1, 4.2.2, 4.2.4 and 9.3.6, with the choices of SPEC.md."""
    method, target, major, minor, fields, _ = head
    if major != 1:
        return None

    def named(n):
        return [v for k, v in fields if k.lower() == n]

    hosts = named(b"host")
    if len(hosts) > 1 or (minor >= 1 and len(hosts) != 1):
        return None
    if any(not host_ok(v) for v in hosts):
        return None
    if not connect_ok(method, target):
        return None
    if not http_target_ok(method, target):
        return None
    te, cl = named(b"transfer-encoding"), named(b"content-length")
    if te and cl:
        return None
    if te:
        if minor < 1 or not CHUNKED_ALONE.fullmatch(combined(te)):
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

# CONNECT has its own targets, in valid_head().
METHODS = [b"GET", b"POST", b"PUT", b"DELETE", b"HEAD", b"OPTIONS", b"PATCH", b"TRACE"]
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


# Octets that are not a dec-octet (RFC 3986, section 3.2.2): above 255,
# or with a leading zero.
BAD_OCTETS = [b"256", b"259", b"260", b"299", b"300", b"999", b"1000", b"00", b"01", b"099", b"000",
              b"0255"]


def ipv4(rng, bad=False):
    """A dotted quad of dec-octets, or with `bad`, with one octet that is
    not a dec-octet."""
    def octet():
        return str(rng.choice([0, 1, 9, 10, 99, 100, 199, 200, 249, 250, 255, rng.randint(0, 255)])).encode()
    octets = [octet() for _ in range(4)]
    if bad:
        octets[rng.randrange(4)] = rng.choice(BAD_OCTETS)
    return b".".join(octets)


def h16(rng):
    return b"".join(pick(rng, b"0123456789abcdefABCDEF") for _ in range(rng.randint(1, 4)))


def ipv6(rng):
    """An IPv6 address, plain or compressed with "::", sometimes with an
    IPv4 tail, and sometimes with one group too many for "::". About a
    third of the IPv4 tails have an octet that is not a dec-octet."""
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
    return s + ipv4(rng, rng.random() < 0.35) if v4 else s


def zone(rng):
    """An RFC 6874 zone ID, which RFC 3986 does not allow, after "%25" or
    a bare "%"."""
    zid = rng.choice([b"eth0", b"1", b"lo", b"en%30", b"x~y", pchars(rng, rng.randint(1, 4), b"")])
    return rng.choice([b"%25", b"%25", b"%"]) + zid


def host(rng):
    """A host: a registered name, IPv4, an IP literal, or an empty name.
    Some are not a host of RFC 3986: an IP literal with a zone ID, an
    IPv6 address with no brackets, and the bad IPv4 tails of ipv6()."""
    r = rng.random()
    if r < 0.48:
        return b".".join(pchars(rng, rng.randint(1, 8), b"") for _ in range(rng.randint(1, 3)))
    if r < 0.66:
        return ipv4(rng)
    if r < 0.86:
        return b"[" + ipv6(rng) + b"]"
    if r < 0.89:
        return b"[" + ipv6(rng) + zone(rng) + b"]"
    if r < 0.92:
        return ipv6(rng)
    if r < 0.97:
        tail = b"".join(pick(rng, UNRES + SUBS + b":") for _ in range(rng.randint(1, 5)))
        v = rng.choice([b"v", b"V"])
        return b"[" + v + h16(rng) + b"." + (tail if rng.random() < 0.8 else pchars(rng, 3)) + b"]"
    return b""


def port(rng):
    return str(rng.choice([80, 443, 8080, 0, 65535, rng.randint(0, 99999)])).encode() if rng.random() < 0.9 else b""


# Ports for CONNECT: empty, 0, the limits of 1 to 65535, leading zeros,
# and numbers that wrap to 80 in 16, 32 or 64 bits.
CONNECT_PORTS = [b"", b"0", b"00", b"1", b"80", b"080", b"443", b"65535", b"065535", b"65536", b"99999",
                 b"65616", b"4294967376", b"18446744073709551696", b"000000000000000000000443"]


def connect_port(rng):
    r = rng.random()
    if r < 0.5:
        return rng.choice(CONNECT_PORTS)
    if r < 0.8:
        return str(rng.randint(0, 70000)).encode()
    if r < 0.92:
        return b"0" * rng.randint(1, 30) + str(rng.randint(0, 66000)).encode()
    return b"".join(pick(rng, b"0123456789") for _ in range(rng.randint(6, 40)))


def connect_target(rng):
    """A target for CONNECT: mostly a host and a port, sometimes with an
    empty host or with the host `http` or `https`, and sometimes another
    form, such as a URI that also fits authority-form."""
    r = rng.random()
    if r < 0.65:
        return host(rng) + b":" + connect_port(rng)
    if r < 0.7:
        return b":" + connect_port(rng)
    if r < 0.77:
        return scheme_case(rng, rng.choice([b"http", b"https"])) + b":" + connect_port(rng)
    if r < 0.87:
        return rng.choice([b"a:1", b"x:443", b"a:0", b"a:65536", b"a:", b"http://a:80/", b"http://a:80",
                           b"a:b", b"a:1/", b"a:/", b"a:1?q", b"fe80::1:80", b"mailto:x@y", b"*", b"/",
                           b"http:80", b"https:443", b"HTTP:443", b"http:", b"https:0", b"http:/a"])
    return target(rng)


def scheme_case(rng, s):
    """`s` in lower case, upper case, with a capital, or in mixed case.
    Schemes are case-insensitive (RFC 3986, section 3.1)."""
    r = rng.random()
    if r < 0.5:
        return s
    if r < 0.7:
        return s.upper()
    if r < 0.85:
        return s[:1].upper() + s[1:]
    return bytes(c ^ 0x20 if rng.random() < 0.5 else c for c in s)


# Ends of http and https targets, after the colon, that are easy to get
# wrong: an empty port, "@" after the authority, userinfo that looks
# like a port, an empty host before ":" or "?", and a path that starts
# with "//".
HTTP_TRICKY = [b"//a:/", b"//a:", b"//a?", b"//a?@", b"//a/u@b", b"//a/?u@b", b"//a:1@b/", b"//a:b@c/",
               b"//@a", b"//u@", b"//u@:80", b"////a", b"//[::1]", b"//[::1]:/", b"//1.2.3.4:080",
               b"//%41/", b"//!$&'()*+,;=/", b"//a.b.c:65536/x?y", b"//:", b"//:/", b"//?", b"//?q",
               b"//a//", b"80", b"443", b"//80", b"/a:b@c"]


def http_target(rng):
    """A target with the scheme http or https, in any case: mostly an
    http-URI or https-URI with a host, and sometimes one with an empty
    host, with userinfo, or with no "//" at all."""
    scheme = scheme_case(rng, rng.choice([b"http", b"https"]))

    def opt_port():
        return b":" + port(rng) if rng.random() < 0.35 else b""
    r = rng.random()
    if r < 0.64:
        rest = b"//" + host(rng) + opt_port()
    elif r < 0.72:
        # An empty host
        rest = b"//" + opt_port()
    elif r < 0.82:
        # Userinfo, sometimes empty
        user = rng.choice([b"", b"u", b"u:p", b":", b"u:", pchars(rng, rng.randint(0, 5), b":")])
        rest = b"//" + user + b"@" + host(rng) + opt_port()
    elif r < 0.94:
        # No "//": an empty hier-part, path-absolute, path-rootless, or
        # digits, which also fit authority-form
        rest = rng.choice([b"", b"/", b"/" + pchars(rng, rng.randint(1, 5)),
                           pchars(rng, rng.randint(1, 5)), port(rng) or b"80"])
        if rest and rng.random() < 0.3:
            rest += path(rng)
        return scheme + b":" + rest + (b"?" + query(rng) if rng.random() < 0.2 else b"")
    else:
        return scheme + b":" + rng.choice(HTTP_TRICKY)
    if rng.random() < 0.6:
        rest += path(rng)
    if rng.random() < 0.3:
        rest += b"?" + query(rng)
    return scheme + b":" + rest


def target(rng):
    r = rng.random()
    if r < 0.55:
        return path(rng) + (b"?" + query(rng) if rng.random() < 0.4 else b"")
    if r < 0.8:
        if rng.random() < 0.45:
            return http_target(rng)
        # Other schemes, some of which start with http, are not held to
        # the rule for http and https.
        scheme = rng.choice([b"ws", b"WS", b"a+b.c-d", b"x", b"httpx", b"HTTPX", b"https+x", b"http.s",
                             b"htt"])
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
    """A Host value: mostly a host with an optional port, sometimes empty
    or with an empty host before a colon, and sometimes not of the
    grammar."""
    r = rng.random()
    if r < 0.9:
        h = host(rng)
        return h + (b":" + port(rng) if rng.random() < 0.3 else b"")
    if r < 0.95:
        return rng.choice([b"", b"", b":", b":80", b":" + port(rng)])
    return rng.choice([b"a b", b"x/y", b"[::1", b"h:p", b"@x", b"%zz", b"x?", b"::1", b"fe80::1",
                       b"::ffff:1.2.3.4"])


CL_VALUES = [b"0", b"5", b"007", b"18446744073709551616", b"+5", b"-1", b"5, 5", b"5,5", b"0x5",
             b"5 5", b" ", b"", b"1e3"]
TE_VALUES = [b"chunked", b"Chunked", b"CHUNKED", b"gzip, chunked", b"chunked, identity", b"xchunked",
             b"chunked;q=1", b"identity", b"chunked,", b",chunked", b"chunk", b"chunked chunked"]
# Lists with empty elements (RFC 9110, section 5.6.1.2), some of the one
# coding chunked and some not.
TE_LISTS = [b"chunked,", b", chunked", b",chunked,", b"chunked , ,", b"chunked\t,", b",", b", ,",
            b"chunked,,chunked", b"chunked, chunked", b"CHUNKED ,", b", ,chunked, ,", b",,", b"gzip,",
            b", gzip, chunked", b"chunked, ,identity", b"cHuNkEd\t,\t,"]
# Values with no element: empty, or only commas and whitespace.
NO_ELEMENT = [b"", b"", b",", b", ,", b" , ", b",,", b"\t,"]


def te_list(rng):
    """A list with chunked in any case and empty elements around it, and
    sometimes chunked twice or another coding before it."""
    name = bytes(c ^ 0x20 if rng.random() < 0.25 else c for c in b"chunked")

    def commas():
        return b"".join(ows(rng) + b"," + ows(rng) for _ in range(rng.choice([0, 0, 1, 1, 2, 3])))
    v = commas() + name + commas()
    r = rng.random()
    if r < 0.12:
        v += b"," + ows(rng) + b"chunked"
    elif r < 0.2:
        v = rng.choice([b"gzip", b"identity", b"x"]) + ows(rng) + b"," + ows(rng) + v
    return v


def te_lines(rng):
    """The values of the Transfer-Encoding lines of a head: one or more."""
    r = rng.random()
    if r < 0.3:
        return [rng.choice(TE_VALUES) if rng.random() < 0.5 else rng.choice(TE_VALUES[:3])]
    if r < 0.5:
        return [te_list(rng)]
    if r < 0.6:
        return [rng.choice(TE_LISTS)]
    if r < 0.78:
        # All lines but one empty or only commas.
        lines = [rng.choice(NO_ELEMENT) for _ in range(rng.randint(1, 3))]
        lines.insert(rng.randint(0, len(lines)), rng.choice(TE_VALUES[:3] + [te_list(rng)]))
        return lines
    if r < 0.86:
        # Two lines that both list chunked.
        return [rng.choice(TE_VALUES[:3] + [b"chunked,"]), rng.choice(TE_VALUES[:3] + [b", chunked"])]
    if r < 0.9:
        # chunked split over two lines.
        k = rng.randint(1, 6)
        return [b"chunked"[:k], b"chunked"[k:]]
    if r < 0.94:
        return [rng.choice(NO_ELEMENT) for _ in range(rng.randint(1, 3))]
    return [rng.choice(TE_VALUES), rng.choice(TE_VALUES)]


NAMES_CASED = {b"host": [b"Host", b"host", b"HOST", b"hOsT"],
               b"content-length": [b"Content-Length", b"content-length", b"CONTENT-LENGTH"],
               b"transfer-encoding": [b"Transfer-Encoding", b"transfer-encoding", b"TRANSFER-ENCODING"]}


def valid_head(rng):
    """A head that fits the grammar, which the framing may still reject."""
    r = rng.random()
    if r < 0.07:
        method, tgt = b"CONNECT", connect_target(rng)
    elif r < 0.085:
        # Another method: the method token is case-sensitive.
        method, tgt = rng.choice([b"connect", b"connect", b"Connect"]), connect_target(rng)
    else:
        method = rng.choice(METHODS) if rng.random() < 0.8 else token(rng)
        tgt = target(rng)
    major, minor = rng.choice([(1, 1)] * 14 + [(1, 0)] * 4 + [(1, 2), (2, 0), (0, 9), (1, 9)])
    line = method + b" " + tgt + b" HTTP/" + str(major).encode() + b"." + str(minor).encode()
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
        for v in te_lines(rng):
            fields.append((rng.choice(NAMES_CASED[b"transfer-encoding"]), v))
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
    # Spec.head_vectors: a body, and chunked in any case
    b"POST /a HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\n\r\nhello",
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: Chunked\r\n\r\n",
    # RFC 9112, section 6.1
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: gzip, chunked\r\n\r\n",
    # RFC 9110, section 5.6.1.2: lists with empty elements, one line or
    # several (section 5.2)
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked,\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: , chunked\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nTransfer-Encoding:\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding:\r\nTransfer-Encoding: chunked\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: ,\r\nTransfer-Encoding: Chunked\r\n"
    b"Transfer-Encoding: , ,\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: ,chunked,\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked , ,\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\t,\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: CHUNKED ,\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: ,\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: , ,\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding:\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding:\r\nTransfer-Encoding: ,\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked,,chunked\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nTransfer-Encoding: chunked\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chun\r\nTransfer-Encoding: ked\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: gzip\r\nTransfer-Encoding: chunked\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked,\r\nContent-Length: 0\r\n\r\n",
    b"POST /a HTTP/1.0\r\nTransfer-Encoding: chunked,\r\n\r\n",
    # Smuggling shapes
    b"POST /a HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nContent-Length: 6\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nContent-Length: 6\r\n\r\nhello",
    b"POST /a HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nContent-Length: 5\r\n\r\nhello",
    b"POST /a HTTP/1.1\r\nHost: x\r\nContent-Length: 5, 5\r\n\r\nhello",
    b"POST /a HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nTransfer-Encoding: chunked\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nContent-Length: 5\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: xchunked\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding:  chunked\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding:\tchunked\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked, identity\r\n\r\n",
    b"POST /a HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked, chunked\r\n\r\n",
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
    b"GET /%4g HTTP/1.1\r\nHost: x\r\n\r\n",
    b"G\"ET /a HTTP/1.1\r\nHost: x\r\n\r\n",
    b"GET /a HTTP/1.1\r\nHost: x\r\nX\"Y: z\r\n\r\n",
    b"GET http://[::1]:80/ HTTP/1.1\r\nHost: [::1]:80\r\n\r\n",
    b"GET http://[::ffff:192.0.2.1]/ HTTP/1.1\r\nHost: [::ffff:192.0.2.1]\r\n\r\n",
    b"GET http://[1::2::3]/ HTTP/1.1\r\nHost: x\r\n\r\n",
    b"GET http://[vF.a:b]/ HTTP/1.1\r\nHost: x\r\n\r\n",
    # IP literals: IPvFuture with an upper-case V, IPv4 tails that are not
    # four dec-octets, an RFC 6874 zone ID, and IPv6 with no brackets
    b"GET http://[V1.a]/ HTTP/1.1\r\nHost: x\r\n\r\n",
    b"GET / HTTP/1.1\r\nHost: [VF.a]\r\n\r\n",
    b"GET / HTTP/1.1\r\nHost: [::1.2.3.255]\r\n\r\n",
    b"GET / HTTP/1.1\r\nHost: [::1.2.3.256]\r\n\r\n",
    b"GET / HTTP/1.1\r\nHost: [::1.2.3.259]\r\n\r\n",
    b"GET / HTTP/1.1\r\nHost: [::1.2.3.260]\r\n\r\n",
    b"GET / HTTP/1.1\r\nHost: [::1.2.3.300]\r\n\r\n",
    b"GET / HTTP/1.1\r\nHost: [::1.2.3.1000]\r\n\r\n",
    b"GET / HTTP/1.1\r\nHost: [::01.2.3.4]\r\n\r\n",
    b"GET / HTTP/1.1\r\nHost: [::1.2.3.00]\r\n\r\n",
    b"GET / HTTP/1.1\r\nHost: [::1.2.099.4]\r\n\r\n",
    b"GET http://[::ffff:1.2.3.256]/ HTTP/1.1\r\nHost: x\r\n\r\n",
    b"GET http://[fe80::1%25eth0]/ HTTP/1.1\r\nHost: x\r\n\r\n",
    b"GET / HTTP/1.1\r\nHost: [fe80::1%25eth0]\r\n\r\n",
    b"GET / HTTP/1.1\r\nHost: ::1\r\n\r\n",
    b"GET / HTTP/1.1\r\nHost: fe80::1\r\n\r\n",
    b"GET http://::1/ HTTP/1.1\r\nHost: x\r\n\r\n",
    # The Host rule
    b"GET / HTTP/1.1\r\n\r\n",
    b"GET / HTTP/1.1\r\nHost: a\r\nHost: a\r\n\r\n",
    b"GET / HTTP/1.1\r\nHost:\r\n\r\n",
    b"GET / HTTP/1.1\r\nHost: a b\r\n\r\n",
    # An empty host before a colon: the target URI of RFC 9112 section 3.3
    # would have an empty host. The first two are in Spec.head_vectors.
    b"GET / HTTP/1.1\r\nHost: :80\r\n\r\n",
    b"GET / HTTP/1.1\r\nHost: :\r\n\r\n",
    b"OPTIONS * HTTP/1.1\r\nHost: :8080\r\n\r\n",
    b"GET http://a/ HTTP/1.1\r\nHost: :80\r\n\r\n",
    b"GET / HTTP/1.1\r\nHost: a:\r\n\r\n",
    b"GET / HTTP/1.0\r\nHost:\r\n\r\n",
    b"GET / HTTP/1.0\r\n\r\n",
    b"GET / HTTP/1.0\r\nHost: a\r\nHost: b\r\n\r\n",
    # RFC 9110, section 9.3.6: CONNECT, with the port from 1 to 65535
    b"CONNECT a: HTTP/1.1\r\nHost: a\r\n\r\n",
    b"CONNECT a:0 HTTP/1.1\r\nHost: a\r\n\r\n",
    b"CONNECT a:00 HTTP/1.1\r\nHost: a\r\n\r\n",
    b"CONNECT a:65536 HTTP/1.1\r\nHost: a\r\n\r\n",
    b"CONNECT a:99999 HTTP/1.1\r\nHost: a\r\n\r\n",
    b"CONNECT a:65616 HTTP/1.1\r\nHost: a\r\n\r\n",
    b"CONNECT a:4294967376 HTTP/1.1\r\nHost: a\r\n\r\n",
    b"CONNECT a:18446744073709551696 HTTP/1.1\r\nHost: a\r\n\r\n",
    b"CONNECT / HTTP/1.1\r\nHost: a\r\n\r\n",
    b"CONNECT * HTTP/1.1\r\nHost: a\r\n\r\n",
    b"CONNECT http://a:80/ HTTP/1.1\r\nHost: a\r\n\r\n",
    b"CONNECT fe80::1:80 HTTP/1.1\r\nHost: a\r\n\r\n",
    b"CONNECT ::1:80 HTTP/1.1\r\nHost: a\r\n\r\n",
    b"CONNECT [fe80::1%25eth0]:80 HTTP/1.1\r\nHost: a\r\n\r\n",
    b"CONNECT [::1]:65535 HTTP/1.1\r\nHost: a\r\n\r\n",
    b"CONNECT a:1 HTTP/1.1\r\nHost: a\r\n\r\n",
    b"CONNECT a:00080 HTTP/1.1\r\nHost: a\r\n\r\n",
    b"CONNECT a:065535 HTTP/1.1\r\nHost: a\r\n\r\n",
    b"CONNECT 1.2.3.4:443 HTTP/1.0\r\n\r\n",
    # An empty host. The first is in Spec.head_vectors.
    b"CONNECT :80 HTTP/1.1\r\nHost: a\r\n\r\n",
    b"CONNECT :443 HTTP/1.0\r\n\r\n",
    b"CONNECT : HTTP/1.1\r\nHost: a\r\n\r\n",
    b"connect :80 HTTP/1.1\r\nHost: a\r\n\r\n",
    b"connect a: HTTP/1.1\r\nHost: a\r\n\r\n",
    b"Connect / HTTP/1.1\r\nHost: a\r\n\r\n",
    # RFC 9110, sections 4.2.1, 4.2.2 and 4.2.4: http and https targets,
    # with the scheme in any case (RFC 3986, section 3.1). First the
    # inputs of Spec.head_vectors.
    b"GET http: HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET http:///a HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET https://u@a/ HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET HTTP://a:/x HTTP/1.1\r\nHost: a\r\n\r\n",
    b"CONNECT http:80 HTTP/1.1\r\nHost: http\r\n\r\n",
    # An empty host
    b"GET http:// HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET https:// HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET http://:80/ HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET HTTP://:/ HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET http://?q HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET Https:///a HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET http:////a HTTP/1.1\r\nHost: a\r\n\r\n",
    # No "//", so no authority
    b"GET https: HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET http:/a HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET http:a HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET HTTP:/ HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET http:?q HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET http:/a:b@c HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET http:80 HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET https:443 HTTP/1.1\r\nHost: a\r\n\r\n",
    b"OPTIONS http:80 HTTP/1.1\r\nHost: a\r\n\r\n",
    # Userinfo
    b"GET http://u@a/ HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET http://u:p@a/ HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET http://@a/ HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET HTTPS://u@a HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET http://a:1@b/ HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET http://u@/ HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET http://u@[::1]:80/ HTTP/1.1\r\nHost: a\r\n\r\n",
    # Accepted: an empty port or none, IP literals, registered names,
    # paths and queries, "@" in the path or the query, and a port above
    # 65535, which these rules do not limit
    b"GET http://a:/ HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET http://a: HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET http://a HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET HTTPS://a:443 HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET hTtP://[::1]:8080/x?y HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET https://[v1.x]/ HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET http://192.0.2.1/a/b?c=d HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET http://1.2.3.256/ HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET http://%41%42/ HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET http://a/u@b HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET http://a?u@b HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET http://a//b HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET http://a:99999/ HTTP/1.1\r\nHost: a\r\n\r\n",
    # CONNECT: a host and a port, so the host is http or https
    b"CONNECT http:80 HTTP/1.1\r\nHost: a\r\n\r\n",
    b"CONNECT https:443 HTTP/1.1\r\nHost: https\r\n\r\n",
    b"CONNECT HTTP:8080 HTTP/1.1\r\nHost: a\r\n\r\n",
    b"CONNECT http: HTTP/1.1\r\nHost: a\r\n\r\n",
    b"CONNECT http://a:80 HTTP/1.1\r\nHost: a\r\n\r\n",
    b"connect http:80 HTTP/1.1\r\nHost: a\r\n\r\n",
    # Other schemes are not held to the rule
    b"GET httpx:// HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET httpx://u@/ HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET ws:// HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET ws://u@a/ HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET https+x: HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET htt:a HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET http.s:/ HTTP/1.1\r\nHost: a\r\n\r\n",
    b"GET /http://u@a/ HTTP/1.1\r\nHost: a\r\n\r\n",
    # Versions
    b"GET / HTTP/2.0\r\nHost: a\r\n\r\n",
    b"GET / HTTP/1.2\r\nHost: a\r\n\r\n",
    b"GET / http/1.1\r\nHost: a\r\n\r\n",
    b"GET / HTTP/1.10\r\nHost: a\r\n\r\n",
    b"GET / HTTP/1\r\nHost: a\r\n\r\n",
    b"GET / HTTP/1.x\r\nHost: a\r\n\r\n",
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
    generated addresses and on mutations of them. Returns the count, the
    number with an IPv4 tail that is not four dec-octets, and the
    disagreements."""
    rng = random.Random(seed + 1)
    bad = []
    bad_tails = 0
    for _ in range(n):
        a = ipv6(rng)
        if rng.random() < 0.4:
            a = mutate_text(rng, a)
        tail = re.search(rb"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$", a)
        bad_tails += tail is not None and not re.fullmatch(IPV4, tail.group())
        ours = IPV6_RE.fullmatch(a) is not None
        try:
            ipaddress.IPv6Address(a.decode("latin-1"))
            theirs = b"%" not in a
        except ValueError:
            theirs = False
        if ours != theirs:
            bad.append(a)
    return n, bad_tails, bad


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


def outcome(want):
    """The oracle's answer, in short: refused by the grammar, or read and
    then accepted or rejected."""
    if not want.startswith("OK"):
        return "grammar"
    return "rejected" if want.endswith("\treject") else "accepted"


def tally(answers):
    n = {"accepted": 0, "rejected": 0, "grammar": 0}
    for a in answers:
        n[a] += 1
    return n


# Search patterns for the counts in TEST-RESULTS.md. They look at the
# octets of an input, so a mutated input counts when it still holds the
# pattern.
V4_TAIL = re.compile(rb"\[[0-9A-Fa-f:]*:([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\]")
ZONE_ID = re.compile(rb"\[[0-9A-Fa-f:.]*:[0-9A-Fa-f:.]*%[^\]]*\]")
UPPER_V = re.compile(rb"\[V[0-9A-Fa-f]+\.[^\]]*\]")


def statistics(items):
    """Lines for TEST-RESULTS.md that count how often the inputs reached
    each form of target and each new rule."""
    targets = {"origin": 0, "absolute": 0, "authority": 0, "both": 0, "asterisk": 0, "literal": 0}
    connect = {"accepted": 0, "empty host": 0, "port": 0, "form": 0, "other": 0}
    ports = {"empty": 0, "zero": 0, "big": 0, "zeros": 0}
    other_case = {"accepted": 0, "rejected": 0}
    te = {"lines": 0, "empty": 0, "empty chunked": 0, "several": 0, "several chunked": 0}
    bare_host = {"accepted": 0, "rejected": 0}
    http = {"read": 0, "upper": 0, "accepted": 0, "no authority": 0, "empty host": 0, "userinfo": 0,
            "other": 0, "elsewhere": 0, "connect": 0, "connect accepted": 0}
    other_scheme = {"read": 0, "http": 0, "accepted": 0}
    host_values = {"all": 0, "empty": 0, "empty accepted": 0, "empty host": 0, "empty host accepted": 0}
    bad_tail, zone, upper_v = [], [], []
    for label, req, want, _ in items:
        if label == "error":
            continue
        bs = bytes.fromhex(req.split(" ")[1])
        if any(not re.fullmatch(IPV4, m.group(1)) for m in V4_TAIL.finditer(bs)):
            bad_tail.append(outcome(want))
        if ZONE_ID.search(bs):
            zone.append(outcome(want))
        if UPPER_V.search(bs):
            upper_v.append(outcome(want))
        head = reference(bs)
        if head is None:
            continue
        method, t, _, _, fields, _ = head
        fr = framing(head)
        absolute = re.fullmatch(ABSOLUTE_URI, t) is not None
        authority = re.fullmatch(AUTHORITY_FORM, t) is not None
        if t == b"*":
            targets["asterisk"] += 1
        elif t.startswith(b"/"):
            targets["origin"] += 1
        elif absolute and authority:
            targets["both"] += 1
        elif absolute:
            targets["absolute"] += 1
        else:
            targets["authority"] += 1
        if b"[" in t:
            targets["literal"] += 1
        if method == b"CONNECT":
            if fr:
                connect["accepted"] += 1
            elif connect_ok(method, t):
                connect["other"] += 1
            elif not authority:
                connect["form"] += 1
            elif t.startswith(b":"):
                connect["empty host"] += 1
            else:
                connect["port"] += 1
            if authority:
                p = t.rsplit(b":", 1)[1]
                if p == b"":
                    ports["empty"] += 1
                elif p.strip(b"0") == b"":
                    ports["zero"] += 1
                elif len(p.lstrip(b"0")) > 5 or int(p.lstrip(b"0")) > 65535:
                    ports["big"] += 1
                elif p.startswith(b"0"):
                    ports["zeros"] += 1
        elif method.upper() == b"CONNECT":
            other_case["accepted" if fr else "rejected"] += 1
        scheme = t.partition(b":")[0]
        if http_scheme(t) and method == b"CONNECT":
            http["connect"] += 1
            http["connect accepted"] += fr is not None
        elif http_scheme(t):
            http["read"] += 1
            http["upper"] += scheme != scheme.lower()
            problem = http_problem(t)
            if problem:
                http[problem] += 1
            else:
                http["accepted" if fr else "elsewhere"] += 1
        elif absolute and not authority:
            other_scheme["read"] += 1
            other_scheme["http"] += scheme.lower().startswith(b"http")
            other_scheme["accepted"] += fr is not None
        values = [v for k, v in fields if k.lower() == b"transfer-encoding"]
        if values:
            te["lines"] += 1
            if any(e.strip(b" \t") == b"" for e in combined(values).split(b",")):
                te["empty"] += 1
                te["empty chunked"] += fr == "chunked"
            if len(values) > 1:
                te["several"] += 1
                te["several chunked"] += fr == "chunked"
        for k, v in fields:
            if k.lower() != b"host":
                continue
            host_values["all"] += 1
            if v == b"":
                host_values["empty"] += 1
                host_values["empty accepted"] += fr is not None
            elif v.startswith(b":"):
                host_values["empty host"] += 1
                host_values["empty host accepted"] += fr is not None
            if b"[" not in v and v.count(b":") >= 2:
                bare_host["accepted" if fr else "rejected"] += 1
    n_connect = sum(connect.values())

    def read_or_not(answers):
        n = tally(answers)
        return (f"{len(answers)} inputs: {n['grammar']} refused by the grammar, "
                f"{n['rejected']} read and rejected, {n['accepted']} read and accepted")

    return [
        f"- Targets of the heads read: {targets['origin']} origin-form, {targets['absolute']} "
        f"absolute-form only, {targets['authority']} authority-form only, {targets['both']} that "
        f"fit both absolute-form and authority-form (such as `a:1`), {targets['asterisk']} "
        f"asterisk-form; {targets['literal']} with an IP literal",
        f"- Heads read with the method `CONNECT`: {n_connect}. Accepted: {connect['accepted']}. "
        f"Against the CONNECT rule, and so rejected: {connect['empty host']} with a host and "
        f"port target whose host is empty, such as `:443`, {connect['port']} with a host and "
        f"port target whose host is not empty and whose port is not from 1 to 65535, and "
        f"{connect['form']} with a target of another form. Rejected only by another rule: "
        f"{connect['other']}",
        f"- Ports of those `CONNECT` targets that are a host and port: {ports['empty']} empty, "
        f"{ports['zero']} zero, {ports['big']} above 65535, {ports['zeros']} from 1 to 65535 "
        f"with leading zeros",
        f"- Heads read with `connect` or another case of it, which is a different method: "
        f"{sum(other_case.values())}, {other_case['accepted']} accepted, "
        f"{other_case['rejected']} rejected",
        f"- Heads read with a target whose scheme is http or https, in any case, and a method "
        f"other than `CONNECT`: {http['read']}, {http['upper']} of them with upper case in the "
        f"scheme. Accepted: {http['accepted']}. Against the rule of RFC 9110 section 4.2, and so "
        f"rejected: {http['no authority']} with no `//` and so no authority, "
        f"{http['empty host']} with an empty host, {http['userinfo']} with userinfo"
        + (f", {http['other']} for another reason" if http["other"] else "")
        + f". Rejected only by another rule: {http['elsewhere']}",
        f"- Heads read with `CONNECT` and a target that starts with `http:` or `https:`, in any "
        f"case, which names the host http or https: {http['connect']}, "
        f"{http['connect accepted']} accepted",
        f"- Heads read with an absolute-form target of another scheme, which that rule does not "
        f"cover: {other_scheme['read']}, {other_scheme['http']} of them with a scheme that starts "
        f"with `http`, such as `httpx`; {other_scheme['accepted']} accepted",
        f"- Heads read with Transfer-Encoding: {te['lines']}. With an empty list element in the "
        f"combined value: {te['empty']}, {te['empty chunked']} chunked and "
        f"{te['empty'] - te['empty chunked']} rejected. With two or more Transfer-Encoding "
        f"lines: {te['several']}, {te['several chunked']} chunked and "
        f"{te['several'] - te['several chunked']} rejected",
        f"- IPv6 literals with an IPv4 tail that is not four dec-octets, anywhere in the input, "
        f"so also in a field that is not Host: {read_or_not(bad_tail)}",
        f"- IP literals with a zone ID (`%` inside the brackets), anywhere in the input: "
        f"{read_or_not(zone)}",
        f"- IPvFuture with an upper-case `V`, anywhere in the input: {read_or_not(upper_v)}",
        f"- Host values of the heads read: {host_values['all']}. Empty: {host_values['empty']}, "
        f"{host_values['empty accepted']} of them in an accepted head. With an empty host before "
        f"a colon, such as `:80` or `:`: {host_values['empty host']}, "
        f"{host_values['empty host accepted']} of them in an accepted head",
        f"- Host values of the heads read that hold two or more colons and no `[`, such as an "
        f"IPv6 address with no brackets: {sum(bare_host.values())}, {bare_host['accepted']} "
        f"in an accepted head",
    ]


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

    ipv6_count, ipv6_bad_tails, ipv6_bad = check_ipv6_oracle(args.seed)
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
    stats = statistics(items)
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
        f"- Framing of the heads read: {sum(1 for f in frames if f == 'length 0')} with no body, "
        f"{sum(1 for f in frames if f.startswith('length') and f != 'length 0')} with a length, "
        f"{frames.count('chunked')} chunked, {frames.count('reject')} rejected",
    ] + stats + [
        f"- IPv6 addresses checked against `ipaddress`, to test the oracle: {ipv6_count}, of "
        f"them {ipv6_bad_tails} with an IPv4 tail that is not four dec-octets; "
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
