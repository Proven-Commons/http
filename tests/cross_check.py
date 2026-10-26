#!/usr/bin/env python3
"""A one-off comparison with three other HTTP/1.1 request parsers. It is
not part of the verified bar, and its record is tests/CROSS-CHECK.md.

- Node's built-in server, with its default strict parser, llhttp
  (tests/cross_check/server.js);
- Go's net/http server (tests/cross_check/server.go);
- Python's h11, from .lake/oracle-packages if it is there
  (pip install --target .lake/oracle-packages h11).

Each is given the same heads as the differential tests, the first
`--count` of them, each on a connection of its own. After a head this
project accepts, the body its framing asks for is sent: that many
octets, or an empty chunked body. After a head it rejects, nothing more
is sent. Then the client closes its side. A server accepts a request
when it answers with a 2xx status, and rejects it with a 4xx or 5xx.
Where both accept, the body lengths they read are compared too.

Each difference is put in the first category below that fits the head,
so a count says how often a parser takes a given choice, not that it
is wrong: RFC 9112 lets a recipient repair several of these.
"""

import argparse
import re
import socket
import subprocess
import sys
import threading
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_tests as rt  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "tests" / "CROSS-CHECK.md"
sys.path.insert(0, str(ROOT / ".lake" / "oracle-packages"))
try:
    import h11
except ImportError:
    h11 = None


COMMON_METHODS = {b"GET", b"HEAD", b"POST", b"PUT", b"DELETE", b"CONNECT", b"OPTIONS", b"TRACE",
                  b"PATCH"}


def head_part(bs):
    """The octets up to the first empty line after the request line, with
    any empty lines before it."""
    i = 0
    while bs[i:i + 2] == b"\r\n":
        i += 2
    end = bs.find(b"\r\n\r\n", i)
    return bs if end < 0 else bs[:end + 4]


def body_for(bs):
    """The body this project's framing asks for, or None when it rejects
    the head, or the length is too big to send."""
    head = rt.reference(bs)
    fr = rt.framing(head) if head else None
    if fr is None:
        return None
    if fr == "chunked":
        return b"0\r\n\r\n"
    n = int(fr.split()[1])
    return b"x" * n if n <= 65536 else None


def ask(port, data, timeout=3):
    """The status code and body of the answer, or None for no answer."""
    try:
        s = socket.create_connection(("127.0.0.1", port), timeout=timeout)
        s.sendall(data)
        s.shutdown(socket.SHUT_WR)
        resp = b""
        while True:
            chunk = s.recv(65536)
            if not chunk:
                break
            resp += chunk
        s.close()
    except OSError:
        return None
    m = re.match(rb"HTTP/1\.[01] ([0-9]{3})", resp)
    if not m:
        return None
    return int(m.group(1)), resp.split(b"\r\n\r\n", 1)[-1]


def h11_verdict(data):
    conn = h11.Connection(h11.SERVER)
    conn.receive_data(data)
    conn.receive_data(b"")
    try:
        ev = conn.next_event()
        if not isinstance(ev, h11.Request):
            return None
        n = 0
        while True:
            ev = conn.next_event()
            if isinstance(ev, h11.Data):
                n += len(ev.data)
            elif isinstance(ev, h11.EndOfMessage):
                return (200, str(n).encode())
            else:
                return None
    except h11.RemoteProtocolError:
        return (400, b"")


def category(bs):
    """The first category the head fits, for a difference."""
    h = head_part(bs)
    lines = h.split(b"\r\n")
    head = rt.reference(bs)
    if re.search(rb"(?<!\r)\n", h):
        return "a bare LF"
    if re.search(rb"\r(?!\n)", h):
        return "a bare CR"
    if h.startswith(b"\r\n") or h.startswith(b"\n"):
        return "empty lines before the request line"
    if any(l[:1] in (b" ", b"\t") for l in lines[1:]):
        return "a line starting with whitespace (obs-fold)"
    if any(re.match(rb"[^:]*[ \t]:", l) for l in lines[1:] if b":" in l):
        return "whitespace before a colon"
    if not re.fullmatch(rb"[^ \t\x0b\x0c]+ [^ \t\x0b\x0c]+ [^ \t\x0b\x0c]+", lines[0]):
        return "other whitespace in the request line"
    if any(re.search(rb"[\x00-\x08\x0a-\x1f\x7f]", l) for l in lines[1:]):
        return "a control octet in a field line"
    parts = lines[0].split(b" ")
    if not re.fullmatch(rb"HTTP/1\.[01]", parts[2]):
        return "another version: " + ("1.2 to 1.9" if re.fullmatch(rb"HTTP/1\.[2-9]", parts[2])
                                       else "not HTTP/1.x")
    if not re.fullmatch(rt.TOKEN, parts[0]):
        return "a method outside token"
    if not rt.TARGET_RE.fullmatch(parts[1]):
        if re.search(rb"[\x80-\xff]", parts[1]):
            return "a target with octets above 0x7F"
        if re.search(rb"%(?![0-9A-Fa-f]{2})", parts[1]):
            return "a target with a bad percent escape"
        if b"[" in parts[1]:
            return "a target with a bad IP literal"
        return "another target outside RFC 3986"
    if head is None:
        names = [l.split(b":", 1)[0] for l in lines[1:] if l]
        if any(not re.fullmatch(rt.TOKEN, n) for n in names):
            return "a field name outside token"
        return "another field line outside the grammar"
    fields = head[4]
    method, target = parts[0], parts[1]
    if method not in COMMON_METHODS:
        return "a method other than the registered ones"
    if target != b"*" and not target.startswith(b"/") and re.fullmatch(rt.ABSOLUTE_URI, target):
        if not re.fullmatch(rt.SCHEME + rb"://.*", target):
            return "an absolute-form target with no authority"
    if target != b"*" and not target.startswith(b"/") and not re.fullmatch(rt.ABSOLUTE_URI, target):
        if method != b"CONNECT":
            return "the authority-form with a method other than CONNECT"
    if target == b"*" and method != b"OPTIONS":
        return "the asterisk-form with a method other than OPTIONS"
    if method == b"CONNECT" and (target.startswith(b"/") or target == b"*"):
        return "CONNECT with a target other than the authority-form"

    def named(n):
        return [v for k, v in fields if k.lower() == n]

    te, cl, hosts = named(b"transfer-encoding"), named(b"content-length"), named(b"host")
    if te and cl:
        return "Transfer-Encoding with Content-Length"
    if te and head[3] == 0:
        return "Transfer-Encoding in HTTP/1.0"
    if len(te) > 1:
        return "two Transfer-Encoding lines"
    if te and te[0].lower() != b"chunked":
        return "a Transfer-Encoding other than chunked alone"
    if len(cl) > 1:
        return "two Content-Length lines" + (" with the same value" if len(set(cl)) == 1 else "")
    if cl and not re.fullmatch(rb"[0-9]+", cl[0]):
        return "a Content-Length that is not digits"
    if len(hosts) > 1:
        return "two Host lines"
    if head[3] >= 1 and not hosts:
        return "no Host in HTTP/1.1"
    if hosts and not rt.HOST_FIELD.fullmatch(hosts[0]):
        return "a Host value outside RFC 3986"
    if any(re.search(rb"[\x80-\xff]", v) for _, v in fields):
        return "obs-text in a field value"
    if hosts and hosts[0] == b"":
        return "an empty Host"
    return "other"


def start(cmd):
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    port = int(proc.stdout.readline())
    return proc, port


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
    report = {}
    for name, fn in servers.items():
        same = differ = noans = same_len = diff_len = skipped = 0
        cats = {}
        for bs in items:
            body = body_for(bs)
            head = rt.reference(bs)
            ours = rt.framing(head) if head else None
            if ours is not None and body is None:
                skipped += 1
                continue
            data = head_part(bs) + (body or b"")
            got = fn(data)
            if got is None:
                noans += 1
                theirs = None
            else:
                theirs = 200 <= got[0] < 300
            accepted = ours is not None
            if theirs is None:
                key = ("no answer", category(bs))
                cats.setdefault(key, []).append(bs)
                continue
            if theirs == accepted:
                same += 1
                # HEAD and CONNECT answers, and Go's answer to OPTIONS *,
                # carry no count.
                if accepted and got[1].isdigit():
                    n = int(got[1])
                    if n == len(body) - (5 if ours == "chunked" else 0):
                        same_len += 1
                    else:
                        diff_len += 1
                        cats.setdefault(("accepts, another body length", category(bs)), []).append(bs)
            else:
                differ += 1
                key = ("accepts" if theirs else "rejects", category(bs))
                cats.setdefault(key, []).append(bs)
        report[name] = (same, differ, noans, same_len, diff_len, skipped, cats)
    for p in procs:
        p.kill()

    lines = ["# Cross-check with other HTTP parsers", "",
             "Written by `tests/cross_check.py`, a one-off comparison that is not part of the "
             "verified bar. RFC 9112 lets a recipient repair some malformed heads instead of "
             "rejecting them, so a difference here is a different choice, not always an error.", "",
             f"- Heads: the first {len(items)} of the differential tests, seed {args.seed}", ""]
    for name, (same, differ, noans, same_len, diff_len, skipped, cats) in report.items():
        lines += [f"## {name}", "",
                  f"- Same verdict, accept or reject: {same}; of those accepted with a body "
                  f"count in the answer, {same_len} read the same body length and {diff_len} "
                  f"another",
                  f"- Different verdict: {differ}",
                  f"- No answer: {noans}",
                  f"- Not sent, since the body would be over 64 KiB: {skipped}", ""]
        if cats:
            lines += ["Where it differs from this project, by the first category that fits the head:", "",
                      "| It | Category | Heads | Example |", "| --- | --- | --- | --- |"]
            for (how, cat), bss in sorted(cats.items(), key=lambda kv: -len(kv[1])):
                ex = ", ".join(f"`{b[:90]!r}`".replace("|", "\\|") for b in bss[:2])
                lines.append(f"| {how} | {cat} | {len(bss)} | {ex} |")
            lines.append("")
    OUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"{len(items)} heads; report in {OUT}")


if __name__ == "__main__":
    main()
