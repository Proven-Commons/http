#!/usr/bin/env python3
"""Compare http-tool with a second transcription of SPEC.md."""

import pathlib
import random
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
BIN = ROOT / ".lake" / "build" / "bin" / "http-tool"
SEED = 20261120
MAX = (1 << 64) - 1
RESULTS = ROOT / "tests" / "TEST-RESULTS.md"

TCHAR = set(b"!#$%&'*+-.^_`|~")


def is_vchar(b):
    return 33 <= b <= 126


def is_tchar(b):
    return 65 <= b <= 90 or 97 <= b <= 122 or 48 <= b <= 57 or b in TCHAR


def is_digit(b):
    return 48 <= b <= 57


def is_hex(b):
    return is_digit(b) or 97 <= b <= 102 or 65 <= b <= 70


def is_alpha(b):
    return 65 <= b <= 90 or 97 <= b <= 122


def lower(bs):
    return bytes(b + 32 if 65 <= b <= 90 else b for b in bs)


def split_crlf(bs):
    for i, b in enumerate(bs):
        if b == 13:
            if i + 1 < len(bs) and bs[i + 1] == 10:
                return bs[:i], bs[i + 2 :]
            return None
        if b == 10:
            return None
    return None


def skip_empty(bs):
    while bs.startswith(b"\r\n"):
        bs = bs[2:]
    return bs


def split_byte(sep, bs):
    parts = [bytearray()]
    for b in bs:
        if b == sep:
            parts.append(bytearray())
        else:
            parts[-1].append(b)
    return [bytes(p) for p in parts]


def split_first(sep, bs):
    for i, b in enumerate(bs):
        if b == sep:
            return bs[:i], bs[i + 1 :]
    return None


def parse_acc(base, val, acc, bs):
    for b in bs:
        d = val(b)
        if d is None:
            return None
        acc = acc * base + d
        if acc > MAX:
            return None
    return acc


def dec_val(b):
    return b - 48 if 48 <= b <= 57 else None


def hex_val(b):
    if 48 <= b <= 57:
        return b - 48
    if 97 <= b <= 102:
        return b - 87
    if 65 <= b <= 70:
        return b - 55
    return None


def parse_dec(bs):
    if not bs:
        return None
    return parse_acc(10, dec_val, 0, bs)


def parse_hex(bs):
    if not bs:
        return None
    return parse_acc(16, hex_val, 0, bs)


def digits(bs):
    return bool(bs) and all(is_digit(b) for b in bs)


def vchars(bs):
    return all(is_vchar(b) for b in bs)


def bare_token(bs):
    return bool(bs) and all(is_tchar(b) for b in bs)


def trim_ows(bs):
    i = 0
    while i < len(bs) and bs[i] in (32, 9):
        i += 1
    j = len(bs)
    while j > i and bs[j - 1] in (32, 9):
        j -= 1
    return bs[i:j]


def host_port(bs):
    if not bs or not vchars(bs):
        return False
    if bs[0] == 91:
        cut = split_first(93, bs)
        if cut is None:
            return False
        lit, rest = cut
        if len(lit) <= 1:
            return False
        if not rest:
            return True
        if rest[0] != 58:
            return False
        port = rest[1:]
        return not port or digits(port)
    cut = split_first(58, bs)
    if cut is None:
        return True
    host, port = cut
    return bool(host) and (not port or digits(port))


def http_target(bs):
    low = lower(bs)
    if low.startswith(b"https:"):
        pre = 6
    elif low.startswith(b"http:"):
        pre = 5
    else:
        return False
    rest = bs[pre:]
    if not rest.startswith(b"//"):
        return False
    auth_and = rest[2:]
    cut = len(auth_and)
    for i, b in enumerate(auth_and):
        if b in (47, 63):
            cut = i
            break
    auth, path = auth_and[:cut], auth_and[cut:]
    return (
        vchars(bs)
        and 64 not in auth
        and host_port(auth)
        and vchars(path)
        and 35 not in path
    )


def scheme_rest(bs):
    cut = split_first(58, bs)
    if cut is None:
        return False
    scheme, rest = cut
    if not scheme or not is_alpha(scheme[0]):
        return False
    if not all(is_alpha(b) or is_digit(b) or b in (43, 45, 46) for b in scheme[1:]):
        return False
    if not vchars(rest) or 35 in rest:
        return False
    return lower(scheme) not in (b"http", b"https")


def connect_port(port):
    n = parse_dec(port)
    return n is not None and digits(port) and 1 <= n <= 65535


def connect_target(bs):
    if not bs or not vchars(bs) or 64 in bs:
        return False
    if bs[0] == 91:
        cut = split_first(93, bs)
        if cut is None:
            return False
        _, rest = cut
        return bool(rest) and rest[0] == 58 and connect_port(rest[1:])
    cut = split_first(58, bs)
    if cut is None:
        return False
    host, port = cut
    return bool(host) and 58 not in host and connect_port(port)


def target_ok(method, target):
    if method == b"CONNECT":
        return connect_target(target)
    low = lower(target)
    if low.startswith(b"http:") or low.startswith(b"https:"):
        return http_target(target)
    if target == b"*":
        return True
    if target[:1] == b"/":
        return vchars(target) and 35 not in target
    if scheme_rest(target):
        return True
    return host_port(target) and 47 not in target and 63 not in target and 35 not in target


def parse_version(bs):
    if len(bs) != 8 or bs[:7] != b"HTTP/1.":
        return None
    d = bs[7]
    if d == 48:
        return "1.0"
    if 49 <= d <= 57:
        return "1.1"
    return None


def parse_field(line):
    if not line or line[0] in (32, 9):
        return None
    cut = split_first(58, line)
    if cut is None:
        return None
    name, raw = cut
    value = trim_ows(raw)
    if bare_token(name) and all(b == 9 or b == 32 or is_vchar(b) or b >= 128 for b in value):
        return name, value
    return None


def parse_fields(bs):
    headers = []
    fuel = len(bs)
    while True:
        if fuel == 0:
            return None
        fuel -= 1
        cut = split_crlf(bs)
        if cut is None:
            return None
        line, bs = cut
        if line == b"":
            return headers, bs
        field = parse_field(line)
        if field is None:
            return None
        headers.append(field)


def host_value_ok(v):
    return v == b"" or (host_port(v) and (not v or v[0] != 58))


def te_values(headers):
    return [v for n, v in headers if lower(n) == b"transfer-encoding"]


def cl_headers(headers):
    return [(n, v) for n, v in headers if lower(n) == b"content-length"]


def normalized(headers):
    vals = te_values(headers)
    if not vals:
        return []
    joined = b",".join(vals)
    elems = [trim_ows(p) for p in joined.split(b",")]
    elems = [e for e in elems if e]
    if not all(bare_token(e) for e in elems):
        return None
    return [lower(e) for e in elems]


def cl_state(headers):
    got = cl_headers(headers)
    if not got:
        return ("absent", None)
    if len(got) != 1 or not digits(got[0][1]):
        return ("bad", None)
    n = parse_dec(got[0][1])
    if n is None:
        return ("bad", None)
    return ("ok", n)


def request_ok(method, target, version, headers):
    hosts = [v for n, v in headers if lower(n) == b"host"]
    if version == "1.1":
        if len(hosts) != 1:
            return False
    elif len(hosts) > 1:
        return False
    if not all(host_value_ok(v) for v in hosts):
        return False
    if method == b"CONNECT":
        if te_values(headers):
            return False
        kind, n = cl_state(headers)
        if kind == "ok" and n != 0:
            return False
        if kind == "bad":
            return False
    if target[:1] == b":":
        return False
    return target_ok(method, target)


def framing(version, headers):
    codes = normalized(headers)
    if codes is None:
        return None
    kind, n = cl_state(headers)
    if kind == "bad":
        return None
    if kind == "ok":
        if codes == [] and not te_values(headers):
            return ("fixed", n)
        return None
    if codes == [] and not te_values(headers):
        return ("fixed", 0)
    if codes == [b"chunked"] and version == "1.1":
        return ("chunked", None)
    return None


def is_qdtext(b):
    return b in (9, 32, 33) or 35 <= b <= 91 or 93 <= b <= 126 or b >= 128


def is_quoted_char(b):
    return b in (9, 32) or is_vchar(b) or b >= 128


def parse_quoted(bs):
    if not bs:
        return None
    if bs[0] == 34:
        return bs[1:]
    if bs[0] == 92:
        if len(bs) < 2 or not is_quoted_char(bs[1]):
            return None
        return parse_quoted(bs[2:])
    if is_qdtext(bs[0]):
        return parse_quoted(bs[1:])
    return None


def skip_ows(bs):
    i = 0
    while i < len(bs) and bs[i] in (32, 9):
        i += 1
    return bs[i:]


def take_token(bs):
    i = 0
    while i < len(bs) and is_tchar(bs[i]):
        i += 1
    if i == 0:
        return None
    return bs[i:]


def parse_one_ext(bs):
    bs = skip_ows(bs)
    if not bs or bs[0] != 59:
        return None
    after = take_token(skip_ows(bs[1:]))
    if after is None:
        return None
    rest = skip_ows(after)
    if not rest or rest[0] != 61:
        return rest
    val = skip_ows(rest[1:])
    if val[:1] == b'"':
        return parse_quoted(val[1:])
    return take_token(val)


def parse_ext(bs):
    fuel = len(bs)
    while bs:
        if fuel == 0:
            return False
        fuel -= 1
        nxt = parse_one_ext(bs)
        if nxt is None or len(nxt) >= len(bs):
            return False
        bs = nxt
    return True


def parse_chunk_size(line):
    i = 0
    while i < len(line) and is_hex(line[i]):
        i += 1
    if i == 0:
        return None
    n = parse_hex(line[:i])
    if n is None or not parse_ext(line[i:]):
        return None
    return n


def parse_trailers(bs):
    fuel = len(bs)
    headers = []
    while True:
        if fuel == 0:
            return None
        fuel -= 1
        cut = split_crlf(bs)
        if cut is None:
            return None
        line, bs = cut
        if line == b"":
            return headers, bs
        if parse_field(line) is None:
            return None
        headers.append(parse_field(line))


def decode_chunked(buf):
    fuel = len(buf) + 1
    acc = b""
    while True:
        if fuel == 0:
            return None
        fuel -= 1
        cut = split_crlf(buf)
        if cut is None:
            return None
        line, rest = cut
        n = parse_chunk_size(line)
        if n is None:
            return None
        if n == 0:
            got = parse_trailers(rest)
            if got is None:
                return None
            _, rest2 = got
            return acc, rest2
        if len(rest) < n + 2 or rest[n : n + 2] != b"\r\n":
            return None
        acc += rest[:n]
        buf = rest[n + 2 :]


def parse_request(bs):
    cut = split_crlf(skip_empty(bs))
    if cut is None:
        return None
    line, rest = cut
    parts = split_byte(32, line)
    if len(parts) != 3:
        return None
    method, target, version_b = parts
    version = parse_version(version_b)
    if version is None or not bare_token(method) or not target or not vchars(target):
        return None
    got = parse_fields(rest)
    if got is None:
        return None
    headers, rest = got
    if not request_ok(method, target, version, headers):
        return None
    fr = framing(version, headers)
    if fr is None:
        return None
    kind, n = fr
    if kind == "fixed":
        if len(rest) < n:
            return None
        return n
    decoded = decode_chunked(rest)
    if decoded is None:
        return None
    body, _ = decoded
    return len(body)


def tool(data):
    with tempfile.NamedTemporaryFile(delete=False) as fh:
        fh.write(data)
        path = fh.name
    out = subprocess.run([str(BIN), path], check=False, capture_output=True)
    text = out.stdout.decode()
    if text == "reject\n":
        return None
    if text.startswith("accept "):
        return int(text.split()[1])
    raise SystemExit(f"unexpected tool output {text!r} for {data!r}")


SMUGGLE = [
    b"POST / HTTP/1.1\r\nHost: example.com\r\nContent-Length: 6\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\nG",
    b"POST / HTTP/1.1\r\nHost: example.com\r\nTransfer-Encoding: chunked\r\nContent-Length: 4\r\n\r\n0\r\n\r\n",
    b"POST / HTTP/1.1\r\nHost: example.com\r\nTransfer-Encoding: chunked, gzip\r\n\r\n0\r\n\r\n",
    b"POST / HTTP/1.0\r\nHost: example.com\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n",
    b"POST / HTTP/1.1\r\nHost: example.com\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhelloXX0\r\n\r\n",
    b"POST / HTTP/1.1\r\nHost: example.com\r\nContent-Length : 5\r\n\r\n12345",
    b"POST / HTTP/1.1\r\nHost: example.com\r\nTransfer-Encoding:\r\n chunked\r\n\r\n0\r\n\r\n",
    b"GET / HTTP/1.1\nHost: example.com\n\n",
    b"POST / HTTP/1.1\r\nHost: example.com\r\nContent-Length: 5\r\nContent-Length: 10\r\n\r\n1234567890",
    b"POST / HTTP/1.1\r\nHost: example.com\r\nContent-Length: +5\r\n\r\n12345",
]


def chunked_body(payload, ext=b""):
    size = format(len(payload), "x").encode()
    return size + ext + b"\r\n" + payload + b"\r\n0\r\n\r\n"


def messages():
    methods = [b"GET", b"POST", b"OPTIONS", b"CONNECT", b"connect"]
    targets = [
        b"/",
        b"/a",
        b"/a?q=1",
        b"*",
        b"*no",
        b":80",
        b":",
        b"a:80",
        b"a:00080",
        b"a:0",
        b"a:65536",
        b"a:",
        b"http://a/x",
        b"HTTP://a:/x",
        b"http://",
        b"http:///a",
        b"https://u@a/",
        b"http:",
        b"http:/a",
        b"ftp://a",
        b"/#frag",
        b"[::1]:443",
        b"[]:80",
    ]
    versions = [b"HTTP/1.0", b"HTTP/1.1", b"HTTP/1.2"]
    header_sets = [
        [],
        [b"Host: a"],
        [b"Host:"],
        [b"Host: :80"],
        [b"Host: :"],
        [b"Host: a", b"Host: b"],
        [b"Host: [::1]"],
        [b"Host: []"],
        [b"Content-Length: 0"],
        [b"Content-Length: 5"],
        [b"Content-Length: 000"],
        [b"Content-Length: +5"],
        [b"Content-Length: 5", b"Content-Length: 5"],
        [b"Transfer-Encoding: chunked"],
        [b"Transfer-Encoding: Chunked"],
        [b"Transfer-Encoding: chunked,"],
        [b"Transfer-Encoding: , chunked"],
        [b"Transfer-Encoding: chunked, gzip"],
        [b"Transfer-Encoding: gzip, chunked"],
        [b"Transfer-Encoding: chunked, chunked"],
        [b"Transfer-Encoding: chunked;a=b"],
        [b"Transfer-Encoding:"],
        [b"Transfer-Encoding: ,"],
        [b"Transfer-Encoding: chunked", b"Transfer-Encoding:"],
        [b"Transfer-Encoding: chunked", b"Content-Length: 0"],
        [b"Host: a", b"Content-Length: 5"],
        [b"Host: a", b"Transfer-Encoding: chunked"],
        [b"Host: a", b"Transfer-Encoding: , chunked"],
        [b"Host: a", b"Transfer-Encoding: chunked,"],
        [b"Host: a", b"Content-Length: 0"],
    ]
    bodies = [b"", b"hello", b"Z"]
    exts = [b"", b";a=b", b';a="x"', b";=x", b';a="x']
    out = list(SMUGGLE)
    for method in methods:
        for target in targets:
            for version in versions:
                for headers in header_sets:
                    # A content-length of 5 is paired with a 5-octet body.
                    # Other bodies are appended only for chunked and empty.
                    head = method + b" " + target + b" " + version + b"\r\n"
                    for h in headers:
                        head += h + b"\r\n"
                    head += b"\r\n"
                    names = b" ".join(headers)
                    if b"chunked" in lower(names) and b"Content-Length" not in names:
                        for ext in exts:
                            out.append(head + chunked_body(b"Z", ext))
                    elif b"Content-Length: 5" in names and b"Content-Length: 5\r" not in names + b"\r":
                        out.append(head + b"hello")
                    elif any(h == b"Content-Length: 5" for h in headers):
                        out.append(head + b"hello")
                    else:
                        out.append(head + b"")
                    if b"Content-Length" not in names and b"chunked" not in lower(names):
                        out.append(head + b"extra")
    # A few explicit chunk and fold cases the grid does not build.
    out.append(b"POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding:\tchunked\r\n\r\n" + chunked_body(b"Z"))
    out.append(b"POST / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\nTransfer-Encoding: gzip\r\n\r\n0\r\n\r\n")
    out.append(b"GET / HTTP/1.1\r\nHost: a\r\n\r\n")
    out.append(b"\r\n\r\nGET / HTTP/1.1\r\nHost: a\r\n\r\n")
    out.append(b"CONNECT a:443 HTTP/1.1\r\nHost: a\r\nContent-Length: 0\r\n\r\n")
    out.append(b"CONNECT a:443 HTTP/1.1\r\nHost: a\r\nContent-Length: 5\r\n\r\nhello")
    out.append(b"CONNECT a:443 HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n")
    out.append(b"GET :80 HTTP/1.1\r\nHost: a\r\n\r\n")
    out.append(b"OPTIONS : HTTP/1.1\r\nHost: a\r\n\r\n")
    out.append(b"GET /#frag HTTP/1.1\r\nHost: a\r\n\r\n")
    # Keep the unused samples referenced so a later edit can see them.
    del bodies
    return out


def main():
    if not BIN.is_file():
        raise SystemExit(f"missing {BIN}; run lake build first")
    random.Random(SEED)
    failures = []
    data = messages()
    for i, msg in enumerate(data):
        expect = parse_request(msg)
        got = tool(msg)
        if expect != got:
            failures.append((i, expect, got, msg[:120]))
            if len(failures) >= 12:
                break
    text = (
        "# Test record\n\n"
        "- Oracle: Python transcription of SPEC.md, compared with http-tool\n"
        f"- Seed: {SEED}\n"
        f"- Inputs: {len(data)}\n"
        f"- Failures: {len(failures)}\n"
    )
    RESULTS.write_text(text)
    if failures:
        for i, expect, got, sample in failures:
            print(f"mismatch {i}: oracle {expect} tool {got} sample {sample!r}")
        raise SystemExit(1)
    print(text)


if __name__ == "__main__":
    main()
