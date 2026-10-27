#!/usr/bin/env python3
"""A one-off comparison with three other HTTP/1.1 request parsers. It is
not part of the verified bar. Its record is tests/CROSS-CHECK.md.

The three parsers:

- Node's built-in server, with its default strict parser, llhttp
  (tests/cross_check/server.js);
- Go's net/http server (tests/cross_check/server.go);
- Python's h11, from .lake/oracle-packages if it is there
  (pip install --target .lake/oracle-packages h11).

The heads are the first `--count` inputs of the differential tests,
less the malformed requests to the tool. Every parser is sent every
head, each on a connection of its own. What is sent is the head: the
octets up to its first empty line, with any empty lines before it.

After a head this project accepts, the body its framing asks for comes
next. For a Content-Length of N up to 1,000,000, that is N octets. For
chunked, it is `5\\r\\nhello\\r\\n0\\r\\n\\r\\n`, which holds 5 octets of
data. Nothing comes after a head this project rejects, or after a head
with a Content-Length above 1,000,000. Then the client closes its side.

Each parser is judged on the head:

- Node and Go accept a head when the servers here answer 2xx. They
  answer 2xx once the request has been read. They also answer 2xx when
  the client closes before the body ends, or the body holds an error,
  and they say which of the three it was.
- llhttp checks the Transfer-Encoding codings only after Node has
  passed the request on. When it then stops on them, Node has refused
  the head, and the server here answers 400 (see server.js).
- h11 accepts a head when it gives a Request event.
- A parser rejects a head with a 4xx or 5xx answer, or, for h11, with
  an error before the Request event.

So a parser that reads the head and then waits for a body that is never
sent still accepts it.

Where both accept and a body was sent, the body lengths are compared.
They agree when the parser read as many octets as this project frames,
and its body ended there. Node gives no count for CONNECT, since it
reads what follows the head as a tunnel.

Where the verdicts differ, the head goes in one category, and it may
be sent again with changes, as below. features() lists the features
the categories name, in order. Apart from the empty lines before the
request line, it looks at the head with those lines removed. A feature
is of one of two kinds:

- a reason this project rejects the head, such as a bare LF or two Host
  lines;
- a feature this project accepts as it is, but another parser may not,
  such as empty lines before the request line, or a method other than
  the registered ones (GET, HEAD, POST, PUT, DELETE, CONNECT, OPTIONS,
  TRACE and PATCH).

The category is found like this:

- The parser accepts a head this project rejects: the category is the
  first reason this project rejects it. So the parser accepted a head
  that has this fault.
- The parser rejects a head this project accepts: the head is sent
  again with one accepted feature changed, for example with the empty
  lines removed or the method set to GET. Each feature has its own
  change, in REPAIRS. The category is the first feature whose change
  makes the parser accept. So the parser rejects the head because of
  this feature, given the rest of the head. If no single change does
  it, the changes are made one more at a time, in order, until the
  parser accepts. Then each change the parser still accepts without is
  left out, and the category names the ones left. If even all the
  changes together do not make the parser accept, the category is
  "other".
- The parser gives no answer: the category is the first feature.
- Both accept, but the body lengths differ: the category is the first
  accepted feature.

RFC 9112 lets a recipient repair some of these heads, so a difference
is not always an error.
"""

import argparse
import re
import socket
import subprocess
import sys
import threading
from pathlib import Path
from typing import NamedTuple, Optional, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_tests as rt  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "tests" / "CROSS-CHECK.md"
sys.path.insert(0, str(ROOT / ".lake" / "oracle-packages"))
try:
    import h11
except ImportError:
    h11 = None


# RFC 9110, section 9, and PATCH (RFC 5789).
REGISTERED_METHODS = {b"GET", b"HEAD", b"POST", b"PUT", b"DELETE", b"CONNECT", b"OPTIONS", b"TRACE",
                      b"PATCH"}
BODY_LIMIT = 1_000_000
CHUNKED_BODY = b"5\r\nhello\r\n0\r\n\r\n"
CHUNKED_DATA = 5
# The two kinds of feature.
REJECTED = "rejected"
ACCEPTED = "accepted"


class Answer(NamedTuple):
    """A parser's answer to one head. `read` is (octets, how), where how
    is "end", "eof" or "error", or None when the answer has no count."""
    accepts: bool
    read: Optional[Tuple[int, str]]
    detail: bytes


def strip_empty(bs):
    """`bs` without the empty lines (CRLF) before the request line."""
    i = 0
    while bs[i:i + 2] == b"\r\n":
        i += 2
    return bs[i:]


def head_part(bs):
    """The octets up to the first empty line after the request line, with
    any empty lines before it."""
    i = len(bs) - len(strip_empty(bs))
    end = bs.find(b"\r\n\r\n", i)
    return bs if end < 0 else bs[:end + 4]


def body_for(ours):
    """The body to send after the head, and the number of data octets this
    project frames in it, or None when there is nothing to compare."""
    if ours is None:
        return b"", None
    if ours == "chunked":
        return CHUNKED_BODY, CHUNKED_DATA
    n = int(ours.split()[1])
    if n > BODY_LIMIT:
        return b"", None
    return b"x" * n, n


def parse_answer(resp):
    """The Answer in the octets a server sent, or None when they hold no
    final status line."""
    while True:
        m = re.match(rb"HTTP/1\.[01] ([0-9]{3})[^\r\n]*\r\n", resp)
        if not m:
            return None
        end = resp.find(b"\r\n\r\n")
        if end < 0:
            return None
        if m.group(1).startswith(b"1"):
            resp = resp[end + 4:]
            continue
        status = int(m.group(1))
        x = re.search(rb"\r\nX-Body: *([^\r\n]*)", resp[:end + 2], re.I)
        read = None
        if x:
            w = x.group(1).split()
            if len(w) >= 2 and w[0].isdigit():
                read = (int(w[0]), w[1].decode())
        detail = (x.group(1) if x else b"") + b" " + resp[end + 4:end + 84]
        return Answer(200 <= status < 300, read, detail.strip())


def ask(port, data, timeout=5):
    """The server's Answer to `data`, or None for no answer. The client
    sends from a thread of its own and reads at the same time, so an answer
    that comes before the server has read all of `data` is still seen."""
    try:
        s = socket.create_connection(("127.0.0.1", port), timeout=timeout)
    except OSError:
        return None

    def send():
        try:
            s.sendall(data)
            s.shutdown(socket.SHUT_WR)
        except OSError:
            pass

    t = threading.Thread(target=send, daemon=True)
    t.start()
    resp = b""
    try:
        while True:
            chunk = s.recv(65536)
            if not chunk:
                break
            resp += chunk
    except OSError:
        pass
    t.join(timeout)
    s.close()
    return parse_answer(resp)


def h11_verdict(data):
    """h11's Answer to `data`, judged on the head as the servers are."""
    conn = h11.Connection(h11.SERVER)
    conn.receive_data(data)
    conn.receive_data(b"")
    try:
        ev = conn.next_event()
    except h11.RemoteProtocolError as e:
        return Answer(False, None, str(e).encode())
    if not isinstance(ev, h11.Request):
        return None
    n = 0
    try:
        while True:
            ev = conn.next_event()
            if isinstance(ev, h11.Data):
                n += len(ev.data)
            elif isinstance(ev, h11.EndOfMessage):
                return Answer(True, (n, "end"), b"")
            else:
                return Answer(True, (n, "error"), repr(ev).encode())
    except h11.RemoteProtocolError as e:
        # Both of these mean the data ended before the body did.
        ended = ("without sending complete message body" in str(e)
                 or "peer unexpectedly closed connection" in str(e))
        how = "eof" if ended else "error"
        return Answer(True, (n, how), str(e).encode())


def verdict(got):
    return None if got is None else got.accepts


# The features of a head

EMPTY_LINES = "empty lines before the request line"
OTHER_METHOD = "a method other than the registered ones"
AUTHORITY_FORM = "the authority-form with a method other than CONNECT"
ASTERISK_FORM = "the asterisk-form with a method other than OPTIONS"
HTTP_NO_HOST = "an http or https target with no host"
HTTP_USERINFO = "an http or https target with userinfo"
NO_AUTHORITY = "an absolute-form target with no authority"
MINOR = "HTTP/1.2 to 1.9"
SCHEME_CHARS = "a scheme with a digit, \"+\", \"-\" or \".\""
HOST_ESCAPE = "a percent escape of an ASCII octet in the host of the target"
TE_EMPTY = "a Transfer-Encoding list with empty elements"
CL_BIG = "a Content-Length of 2^63 or more"
VALUE_TAB = "a tab after a Content-Length or Transfer-Encoding value"
CL_ZEROS = "a Content-Length with leading zeros"
OBS_TEXT = "obs-text in a field value"
EMPTY_HOST = "an empty Host"


def te_reason(te):
    """Why this project does not read these Transfer-Encoding values as
    the one coding chunked."""
    codings = [e.strip(b" \t") for e in rt.combined(te).split(b",")]
    codings = [c for c in codings if c]
    if not codings:
        cat = "a Transfer-Encoding with no coding"
    elif sum(c.lower() == b"chunked" for c in codings) > 1:
        cat = "chunked twice"
    elif codings[-1].lower() != b"chunked":
        cat = "a Transfer-Encoding whose last coding is not chunked"
    elif len(codings) > 1:
        cat = "a Transfer-Encoding with another coding before chunked"
    else:
        cat = "another Transfer-Encoding"
    return cat + (", over two or more lines" if len(te) > 1 else "")


def http_reason(method, target):
    """Why this project rejects a target of the grammar under RFC 9110,
    sections 4.2.1, 4.2.2 and 4.2.4, or None. The rule is for a target
    whose scheme is http or https, in any case, with a method other than
    CONNECT. Such a target needs "//" and a host that is not empty, and
    its authority may not hold userinfo. With no "//" it has no host. A
    target with userinfo and an empty host, such as `http://u@/`, is
    counted as one with userinfo."""
    scheme, colon, rest = target.partition(b":")
    if method == b"CONNECT" or not colon or scheme.lower() not in (b"http", b"https"):
        return None
    if not rest.startswith(b"//"):
        return HTTP_NO_HOST
    authority = re.match(rb"//([^/?#]*)", rest).group(1)
    if b"@" in authority:
        return HTTP_USERINFO
    host = authority
    if not host.startswith(b"["):
        host = host.partition(b":")[0]
    return HTTP_NO_HOST if host == b"" else None


def target_host(method, target):
    """(start, end) of the host in a target of the grammar, or None when
    the target has no host."""
    if method == b"CONNECT" or (re.fullmatch(rt.AUTHORITY_FORM, target)
                                and not re.fullmatch(rt.ABSOLUTE_URI, target)):
        return 0, target.rfind(b":")
    m = re.match(rt.SCHEME + rb"://([^/?#]*)", target)
    if not m or target.startswith(b"/"):
        return None
    start = m.start(1) + m.group(1).rfind(b"@") + 1
    if target[start:start + 1] == b"[":
        return start, target.index(b"]", start) + 1
    colon = target.find(b":", start, m.end(1))
    return start, colon if colon >= 0 else m.end(1)


def without_host_escapes(bs):
    """`bs` with each percent escape of an ASCII octet in the host of its
    target replaced by `x`."""
    method, target, version = split_head(bs)[1].split(b" ")
    a, b = target_host(method, target)
    host = re.sub(rb"%[0-7][0-9A-Fa-f]", b"x", target[a:b])
    return change_request_line(bs, target=target[:a] + host + target[b:])


def field_name(line):
    return line.split(b":", 1)[0].lower()


def framing_field(line):
    return field_name(line) in (b"content-length", b"transfer-encoding")


def value_after_ows(line):
    """A field line's value with the whitespace before it removed, and
    the whitespace after it kept."""
    return line.split(b":", 1)[1].lstrip(b" \t")


def features(bs):
    """The features of the head that the categories name, in order, as
    (kind, name). The list ends at the first reason this project rejects
    the head."""
    h = head_part(bs)
    head = rt.reference(bs)
    if re.search(rb"(?<!\r)\n", h):
        yield REJECTED, "a bare LF"
        return
    if re.search(rb"\r(?!\n)", h):
        yield REJECTED, "a bare CR"
        return
    if h.startswith(b"\r\n"):
        yield ACCEPTED, EMPTY_LINES
    lines = strip_empty(h).split(b"\r\n")
    request_line = lines[0]
    fields = []
    for line in lines[1:]:
        if not line:
            break
        fields.append(line)
    grammar = None
    parts = request_line.split(b" ")
    if fields and fields[0][:1] in (b" ", b"\t"):
        grammar = "whitespace before the first field line"
    elif any(line[:1] in (b" ", b"\t") for line in fields[1:]):
        grammar = "a folded line (obs-fold)"
    elif any(re.match(rb"[^:]*[ \t]:", line) for line in fields if b":" in line):
        grammar = "whitespace before a colon"
    elif re.search(rb"[\t\x0b\x0c]|  |^ | $", request_line):
        grammar = "other whitespace in the request line"
    elif len(parts) != 3:
        grammar = "a request line that is not three parts"
    elif any(b"\x00" in line for line in fields):
        grammar = "a NUL in a field line"
    elif any(re.search(rb"[\x01-\x08\x0a-\x1f\x7f]", line) for line in fields):
        grammar = "another control octet in a field line"
    if grammar:
        yield REJECTED, grammar
        return
    method, target, version = parts
    if re.fullmatch(rb"HTTP/1\.[2-9]", version):
        yield ACCEPTED, MINOR
    elif re.fullmatch(rb"HTTP/[02-9]\.[0-9]", version):
        grammar = "a major version other than 1"
    elif not re.fullmatch(rb"HTTP/1\.[01]", version):
        grammar = "a version outside the grammar"
    if not grammar and not re.fullmatch(rt.TOKEN, method):
        grammar = "a method outside token"
    if not grammar and not rt.TARGET_RE.fullmatch(target):
        if re.search(rb"[\x80-\xff]", target):
            grammar = "a target with octets above 0x7F"
        elif re.search(rb"%(?![0-9A-Fa-f]{2})", target):
            grammar = "a target with a bad percent escape"
        elif b"[" in target:
            grammar = "a target with a bad IP literal"
        else:
            grammar = "another target outside RFC 3986"
    if not grammar and head is None:
        names = [line.split(b":", 1)[0] for line in fields]
        if any(not re.fullmatch(rt.TOKEN, n) for n in names):
            grammar = "a field name outside token"
        else:
            grammar = "another field line outside the grammar"
    if grammar:
        yield REJECTED, grammar
        return

    # RFC 9110, section 9.3.6
    if method == b"CONNECT":
        m = rt.CONNECT_TARGET.fullmatch(target)
        reason = None
        if not m:
            reason = "CONNECT whose target is not a host and port"
        elif m.group("host") == b"":
            reason = "CONNECT with an empty host"
        elif m.group("port") == b"":
            reason = "CONNECT with an empty port"
        elif m.group("port").lstrip(b"0") == b"":
            reason = "CONNECT with port 0"
        elif not rt.connect_ok(method, target):
            reason = "CONNECT with a port above 65535"
        if reason:
            yield REJECTED, reason
            return
    # RFC 9110, sections 4.2.1, 4.2.2 and 4.2.4
    reason = http_reason(method, target)
    if reason:
        yield REJECTED, reason
        return
    # RFC 9112, sections 3.2.2 to 3.2.4
    # A CONNECT target that got this far is a host and port, read as the
    # authority-form even when it also fits absolute-URI, such as `a:1`.
    is_absolute = (method != b"CONNECT" and not target.startswith(b"/") and target != b"*"
                   and re.fullmatch(rt.ABSOLUTE_URI, target))
    if not is_absolute and re.fullmatch(rt.AUTHORITY_FORM, target) and method != b"CONNECT":
        yield ACCEPTED, AUTHORITY_FORM
    if target == b"*" and method != b"OPTIONS":
        yield ACCEPTED, ASTERISK_FORM
    if method not in REGISTERED_METHODS:
        yield ACCEPTED, OTHER_METHOD
    if is_absolute and not re.fullmatch(rt.SCHEME + rb"://.*", target):
        yield ACCEPTED, NO_AUTHORITY
    if is_absolute and not re.match(rb"[A-Za-z]+:", target):
        yield ACCEPTED, SCHEME_CHARS
    span = target_host(method, target)
    if span and re.search(rb"%[0-7][0-9A-Fa-f]", target[span[0]:span[1]]):
        yield ACCEPTED, HOST_ESCAPE

    def named(n):
        return [v for k, v in head[4] if k.lower() == n]

    te, cl, hosts = named(b"transfer-encoding"), named(b"content-length"), named(b"host")
    reason = None
    if te and cl:
        reason = "Transfer-Encoding with Content-Length"
    elif te and head[3] == 0:
        reason = "Transfer-Encoding in HTTP/1.0"
    elif te and not rt.CHUNKED_ALONE.fullmatch(rt.combined(te)):
        reason = te_reason(te)
    elif len(cl) > 1:
        reason = "two Content-Length lines" + (" with the same value" if len(set(cl)) == 1
                                               else " with different values")
    elif cl and not re.fullmatch(rb"[0-9]+", cl[0]):
        values = [v.strip(b" \t") for v in cl[0].split(b",")]
        if len(values) > 1 and all(re.fullmatch(rb"[0-9]+", v) for v in values) \
                and len({int(v) for v in values}) == 1:
            reason = "a Content-Length list of equal values"
        else:
            reason = "a Content-Length that is not digits"
    elif len(hosts) > 1:
        reason = "two Host lines"
    elif head[3] >= 1 and not hosts:
        reason = "no Host, in HTTP/1.1 to 1.9"
    elif hosts and not rt.host_ok(hosts[0]):
        if rt.HOST_FIELD.fullmatch(hosts[0]):
            reason = "a Host value with an empty host, such as `:80`"
        elif b"[" in hosts[0] or b"]" in hosts[0] or hosts[0].count(b":") > 1:
            reason = "a Host value with a bad IP literal"
        else:
            reason = "another Host value outside RFC 3986"
    if reason:
        yield REJECTED, reason
        return
    if te and len([e for e in rt.combined(te).split(b",")]) > 1:
        yield ACCEPTED, TE_EMPTY
    if cl and int(cl[0]) >= 2 ** 63:
        yield ACCEPTED, CL_BIG
    if any(b"\t" in value_after_ows(line) for line in fields if framing_field(line)):
        yield ACCEPTED, VALUE_TAB
    if cl and len(cl[0]) > 1 and cl[0].startswith(b"0"):
        yield ACCEPTED, CL_ZEROS
    if any(re.search(rb"[\x80-\xff]", v) for _, v in head[4]):
        yield ACCEPTED, OBS_TEXT
    if hosts and hosts[0] == b"":
        yield ACCEPTED, EMPTY_HOST


# Repairs: each changes one accepted feature of a head and keeps the rest.

def split_head(bs):
    """(empty lines, request line, field lines, the rest from the empty
    line that ends the head)."""
    i = len(bs) - len(strip_empty(bs))
    end = bs.find(b"\r\n\r\n", i)
    lines = bs[i:end].split(b"\r\n")
    return bs[:i], lines[0], lines[1:], bs[end:]


def join_head(prefix, request_line, fields, rest):
    return prefix + b"\r\n".join([request_line] + fields) + rest


def change_request_line(bs, method=None, target=None, version=None):
    prefix, request_line, fields, rest = split_head(bs)
    m, t, v = request_line.split(b" ")
    return join_head(prefix, b" ".join([method or m, target or t, version or v]), fields, rest)


def change_fields(bs, f):
    """`bs` with each field line replaced by the lines f gives for it."""
    prefix, request_line, fields, rest = split_head(bs)
    return join_head(prefix, request_line, [out for line in fields for out in f(line)], rest)


def one_chunked(bs):
    """`bs` with its Transfer-Encoding lines replaced by one line that holds
    only chunked."""
    seen = []

    def f(line):
        if field_name(line) != b"transfer-encoding":
            return [line]
        if seen:
            return []
        seen.append(line)
        return [b"Transfer-Encoding: chunked"]
    return change_fields(bs, f)


def content_length(g):
    def f(line):
        if field_name(line) != b"content-length":
            return [line]
        name, value = line.split(b":", 1)
        return [name + b":" + g(value)]
    return f


REPAIRS = {
    EMPTY_LINES: strip_empty,
    MINOR: lambda bs: change_request_line(bs, version=b"HTTP/1.1"),
    AUTHORITY_FORM: lambda bs: change_request_line(bs, target=b"/"),
    ASTERISK_FORM: lambda bs: change_request_line(bs, target=b"/"),
    # Only the method changes. When the target is `*` or a host and port,
    # its own feature comes first, so a parser that also wants another
    # target for GET gets the two changes together.
    OTHER_METHOD: lambda bs: change_request_line(bs, method=b"GET"),
    NO_AUTHORITY: lambda bs: change_request_line(bs, target=b"/"),
    SCHEME_CHARS: lambda bs: change_request_line(
        bs, target=b"x:" + split_head(bs)[1].split(b" ")[1].split(b":", 1)[1]),
    HOST_ESCAPE: without_host_escapes,
    TE_EMPTY: one_chunked,
    CL_BIG: lambda bs: change_fields(bs, content_length(lambda v: b" 0")),
    VALUE_TAB: lambda bs: change_fields(bs, lambda line: [
        line.split(b":", 1)[0] + b": " + value_after_ows(line).replace(b"\t", b" ")
        if framing_field(line) else line]),
    CL_ZEROS: lambda bs: change_fields(bs, content_length(
        lambda v: b" " + str(int(v.strip(b" \t"))).encode())),
    OBS_TEXT: lambda bs: change_fields(bs, lambda line: [re.sub(rb"[\x80-\xff]", b"x", line)]),
    EMPTY_HOST: lambda bs: change_fields(
        bs, lambda line: [b"Host: a" if field_name(line) == b"host" else line]),
}


def file_difference(fn, bs, body, got, how):
    """The category of a difference, as the module docstring says."""
    found = list(features(bs))
    accepted = [name for kind, name in found if kind == ACCEPTED]
    if how == "accepts":
        rejected = [name for kind, name in found if kind == REJECTED]
        return rejected[0] if rejected else "other"
    if how != "rejects":
        return found[0][1] if found else "other"
    for name in accepted:
        if verdict(fn(head_part(REPAIRS[name](bs)) + body)) != verdict(got):
            return name
    # No single change: change the features one more at a time until the
    # parser accepts, then leave out each change it still accepts without.
    def flips(names):
        fixed = bs
        for name in names:
            # An earlier change can take a later feature away too.
            if any(n == name for _, n in features(fixed)):
                fixed = REPAIRS[name](fixed)
        return verdict(fn(head_part(fixed) + body)) != verdict(got)

    for k in range(2, len(accepted) + 1):
        if flips(accepted[:k]):
            needed = accepted[:k]
            for name in accepted[:k - 1]:
                fewer = [n for n in needed if n != name]
                if flips(fewer):
                    needed = fewer
            return "together: " + "; ".join(needed)
    return "other"


def compare(fn, items):
    """Send every head to one parser, and count how its answers compare
    with this project's."""
    r = {"sent": 0, "both_accept": 0, "both_reject": 0, "they_accept": 0, "they_reject": 0,
         "no_answer": 0, "compared": 0, "compared_zero": 0, "compared_chunked": 0,
         "compared_length": 0, "same_length": 0, "other_length": 0, "over_limit": 0,
         "no_count": 0, "cats": {}}
    for bs in items:
        head = rt.reference(bs)
        ours = rt.framing(head) if head else None
        body, expect = body_for(ours)
        got = fn(head_part(bs) + body)
        r["sent"] += 1
        accepted = ours is not None
        if got is None or got.accepts != accepted:
            if got is None:
                r["no_answer"] += 1
                how = "no answer"
            elif got.accepts:
                r["they_accept"] += 1
                how = "accepts"
            else:
                r["they_reject"] += 1
                how = "rejects"
            cat = file_difference(fn, bs, body, got, how)
            r["cats"].setdefault((how, cat), []).append((bs, got))
            continue
        if not accepted:
            r["both_reject"] += 1
            continue
        r["both_accept"] += 1
        if expect is None:
            r["over_limit"] += 1
            continue
        if got.read is None:
            r["no_count"] += 1
            continue
        r["compared"] += 1
        if expect == 0:
            r["compared_zero"] += 1
        elif ours == "chunked":
            r["compared_chunked"] += 1
        else:
            r["compared_length"] += 1
        n, end = got.read
        if end == "end" and n == expect:
            r["same_length"] += 1
            continue
        r["other_length"] += 1
        if end == "eof":
            how = f"reads the head, then waits for a longer body ({n} octets read)"
        elif end == "error":
            how = "reads the head, then finds an error in the body"
        else:
            how = f"reads {n} body octets where this project frames {expect}"
        accepted_features = [name for kind, name in features(bs) if kind == ACCEPTED]
        cat = accepted_features[0] if accepted_features else "other"
        r["cats"].setdefault((how, cat), []).append((bs, got))
    return r


def start(cmd):
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    port = int(proc.stdout.readline())
    return proc, port


def example(bs):
    """The head as sent, without the body, for a table cell."""
    return f"`{head_part(bs)[:100]!r}`".replace("|", "\\|")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", type=int, default=6000)
    ap.add_argument("--seed", type=int, default=20261025)
    args = ap.parse_args()

    gobin = ROOT / ".lake" / "cross_check" / "server"
    gobin.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["go", "build", "-o", str(gobin), str(ROOT / "tests" / "cross_check" / "server.go")],
                   check=True)
    node_ver = subprocess.run(["node", "--version"], capture_output=True, text=True).stdout.strip()
    go_ver = subprocess.run(["go", "version"], capture_output=True, text=True).stdout.strip()
    servers = {}
    procs = []
    p, port = start(["node", str(ROOT / "tests" / "cross_check" / "server.js")])
    procs.append(p)
    servers[f"Node {node_ver} (llhttp)"] = lambda d, port=port: ask(port, d)
    p, port = start([str(gobin)])
    procs.append(p)
    servers[f"Go {go_ver.split()[2]} net/http"] = lambda d, port=port: ask(port, d)
    if h11:
        servers[f"h11 {h11.__version__}"] = h11_verdict

    items = [bytes.fromhex(req.split(" ")[1])
             for label, req, _, _ in rt.cases(args.seed, args.count) if label != "error"]
    # features() must name a reason to reject in exactly the heads this
    # project rejects, and each repair must keep a head this project accepts.
    for bs in items:
        head = rt.reference(bs)
        ours = rt.framing(head) if head else None
        found = list(features(bs))
        if (ours is None) != any(kind == REJECTED for kind, _ in found):
            sys.exit(f"features() does not match this project's verdict on {bs!r}")
        for kind, name in found:
            fixed = REPAIRS[name](bs) if ours is not None else None
            if fixed is not None and (rt.reference(fixed) is None
                                      or rt.framing(rt.reference(fixed)) is None):
                sys.exit(f"the repair for {name!r} makes this project reject {bs!r}")
    try:
        report = {name: compare(fn, items) for name, fn in servers.items()}
    finally:
        for p in procs:
            p.kill()

    ours = {"reject": 0, "none": 0, "length": 0, "chunked": 0, "over": 0}
    for bs in items:
        head = rt.reference(bs)
        fr = rt.framing(head) if head else None
        if fr is None:
            ours["reject"] += 1
        elif fr == "chunked":
            ours["chunked"] += 1
        elif fr == "length 0":
            ours["none"] += 1
        elif int(fr.split()[1]) <= BODY_LIMIT:
            ours["length"] += 1
        else:
            ours["over"] += 1

    lines = ["# Cross-check with other HTTP parsers", "",
             "Written by `tests/cross_check.py`, a one-off comparison that is not part of the "
             "verified bar. Its docstring says how the heads are sent and judged, and how a "
             "difference gets its category. RFC 9112 lets a recipient repair some malformed "
             "heads instead of rejecting them, so a difference here is a different choice, not "
             "always an error.", "",
             f"- Heads: the first {len(items)} inputs of the differential tests (seed {args.seed}, "
             f"`--count {args.count}`, less the malformed requests to the tool). Every parser is "
             f"sent all {len(items)}. A head whose verdicts differ is also sent again with "
             f"features changed, to find its category.",
             f"- This project rejects {ours['reject']} of them. It accepts {ours['none']} with no "
             f"body, {ours['length']} with a Content-Length from 1 to {BODY_LIMIT:,}, "
             f"{ours['chunked']} as chunked, and {ours['over']} with a Content-Length above "
             f"{BODY_LIMIT:,}.",
             f"- Sent after the head: nothing after a head this project rejects; the whole body "
             f"for a Content-Length up to {BODY_LIMIT:,}; `5\\r\\nhello\\r\\n0\\r\\n\\r\\n` "
             f"(5 octets of data) for chunked; nothing for a Content-Length above "
             f"{BODY_LIMIT:,}, so those heads are judged on the head alone.",
             "- A parser accepts a head when it reads it and passes the request on, even when "
             "it then waits for a body that is never sent.",
             "- In the tables, \"accepts\" means the other parser accepts a head this project "
             "rejects, and \"rejects\" means it rejects a head this project accepts. The "
             "examples show the head as sent, cut at 100 octets.",
             "- Categories: for a head the other parser accepts, the first reason this project "
             "rejects it. For a head the other parser rejects, the first feature whose change "
             "alone makes that parser accept it, or, after \"together:\", the features whose "
             "changes it needs at once. The script checks that it finds a reason to reject in "
             "each head this project rejects and in no other, and that each change keeps a head "
             "this project accepts.", ""]
    for name, r in report.items():
        nonzero = r["compared_chunked"] + r["compared_length"]
        lines += [f"## {name}", "",
                  f"- Heads sent: {r['sent']}",
                  f"- Same verdict: {r['both_accept'] + r['both_reject']} "
                  f"({r['both_accept']} both accept, {r['both_reject']} both reject)",
                  f"- Different verdict: {r['they_accept'] + r['they_reject']} "
                  f"({r['they_accept']} it accepts and this project rejects, "
                  f"{r['they_reject']} it rejects and this project accepts)",
                  f"- No answer: {r['no_answer']}",
                  f"- Body lengths compared, where both accept: {r['compared']}. Of those, "
                  f"{r['compared_zero']} have no body and {nonzero} a non-zero length "
                  f"({r['compared_length']} by Content-Length, {r['compared_chunked']} chunked). "
                  f"{r['same_length']} read the same length and {r['other_length']} another.",
                  f"- Not compared, where both accept: {r['over_limit']} with a Content-Length "
                  f"above {BODY_LIMIT:,}, and {r['no_count']} whose answer has no count.", ""]
        alone, together = {}, {}
        for (how, cat), found in r["cats"].items():
            if how != "rejects":
                continue
            if cat.startswith("together: "):
                for name in cat[len("together: "):].split("; "):
                    together[name] = together.get(name, 0) + len(found)
            else:
                alone[cat] = alone.get(cat, 0) + len(found)
        if alone or together:
            lines += ["The heads it rejects and this project accepts, by the feature whose change "
                      "makes it accept them: alone, or together with other changes.", "",
                      "| Feature | Alone | With others |", "| --- | --- | --- |"]
            for name in sorted(set(alone) | set(together),
                               key=lambda n: (-alone.get(n, 0) - together.get(n, 0), n)):
                lines.append(f"| {name} | {alone.get(name, 0)} | {together.get(name, 0)} |")
            lines.append("")
        if r["cats"]:
            lines += ["Where it differs from this project (the two shortest examples):", "",
                      "| It | Category | Heads | Examples |", "| --- | --- | --- | --- |"]
            for (how, cat), found in sorted(r["cats"].items(), key=lambda kv: (-len(kv[1]), kv[0])):
                shortest = sorted({head_part(bs) for bs, _ in found}, key=lambda b: (len(b), b))[:2]
                ex = ", ".join(example(b) for b in shortest)
                lines.append(f"| {how} | {cat} | {len(found)} | {ex} |")
            lines.append("")
    OUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"{len(items)} heads; report in {OUT}")


if __name__ == "__main__":
    main()
