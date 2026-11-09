#!/usr/bin/env python3
"""MALLET relay (docs/RELAY.md).

One small process that holds playtest sessions: the map maker's MALLET opens a session and gets its secret, test
builds join with that secret and post live positions and finished attempts, and the maker receives them. The same
connection carries 0.17's co-editing edits.

Standard library only (no pip install), so the Docker image stays tiny:

    python relay/relay.py --port 8787
    python relay/relay.py --host 0.0.0.0 --port 8787 --data-dir /data
"""

import argparse
import asyncio
import base64
import hashlib
import hmac
import json
import math
import os
import secrets
import time

GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
MAX_MESSAGE = 4 << 20            # one message, bytes
MAX_ATTEMPT = 256 << 10
MAX_RUNS = 5000
MAX_PEERS = 32
MAX_SESSIONS = 500
PING_EVERY = 20.0
STALE_AFTER = 75.0
SESSION_FORGET = 12 * 3600.0
RATES = {"tester": (40.0, 60.0), "maker": (400.0, 600.0), "editor": (200.0, 300.0)}
ROLES = ("maker", "tester", "editor")
FORWARD_TO = ("maker", "editor")

sessions = {}                    # code -> session
data_dir = ""
log_path = ""
quiet = True


def log(*a):
    line = "%s %s" % (time.strftime("%H:%M:%S"), " ".join(str(x) for x in a))
    if log_path:
        try:
            with open(log_path, "a", encoding="utf-8") as f:
                f.write(line + "\n")
        except OSError:
            pass
    if not quiet:
        print(line, flush=True)


# ---------------------------------------------------------------------------------------------- WebSocket

def ws_frame(op, data=b""):
    n = len(data)
    head = bytearray([0x80 | op])
    if n < 126:
        head.append(n)
    elif n < 65536:
        head.append(126)
        head += n.to_bytes(2, "big")
    else:
        head.append(127)
        head += n.to_bytes(8, "big")
    return bytes(head) + data


class TooBig(Exception):
    pass


async def ws_read(reader):
    """One frame: (fin, opcode, payload). Clients must mask; the mask is stripped here."""
    hdr = await reader.readexactly(2)
    fin = bool(hdr[0] & 0x80)
    op = hdr[0] & 0x0F
    ln = hdr[1] & 0x7F
    if ln == 126:
        ln = int.from_bytes(await reader.readexactly(2), "big")
    elif ln == 127:
        ln = int.from_bytes(await reader.readexactly(8), "big")
    if ln > MAX_MESSAGE:
        raise TooBig()
    mask = await reader.readexactly(4) if hdr[1] & 0x80 else None
    payload = await reader.readexactly(ln) if ln else b""
    if mask:
        payload = bytes(b ^ mask[i & 3] for i, b in enumerate(payload))
    return fin, op, payload


class Peer:
    def __init__(self, writer):
        self.id = secrets.token_hex(4)
        self.writer = writer
        self.role = ""
        self.name = ""
        self.session = ""
        self.map_version = 0
        self.tokens = 1.0
        self.rate_t = time.monotonic()
        self.last = time.monotonic()
        self.closed = False
        self.lock = asyncio.Lock()

    async def raw(self, op, data=b""):
        if self.closed:
            return
        try:
            async with self.lock:
                self.writer.write(ws_frame(op, data))
                await self.writer.drain()
        except (ConnectionError, OSError):
            self.closed = True

    async def send(self, obj):
        if self.closed:
            return
        try:
            data = json.dumps(obj, separators=(",", ":")).encode()
        except (TypeError, ValueError):
            return
        if len(data) > MAX_MESSAGE:
            return
        await self.raw(0x1, data)

    async def close(self, code=1000, reason=""):
        log("closing", self.name or "?", code, reason)
        await self.raw(0x8, code.to_bytes(2, "big") + reason.encode()[:120])
        self.closed = True

    def allow(self):
        rate, burst = RATES.get(self.role, (60.0, 60.0))
        t = time.monotonic()
        self.tokens = min(burst, self.tokens + (t - self.rate_t) * rate)
        self.rate_t = t
        if self.tokens < 1.0:
            return False
        self.tokens -= 1.0
        return True


# ---------------------------------------------------------------------------------------------- sessions

def new_code():
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"        # no I / O / 0 / 1: easy to read out loud
    while True:
        code = "".join(secrets.choice(alphabet) for _ in range(6))
        if code not in sessions:
            return code


def peer_brief(p):
    return {"id": p.id, "name": p.name, "role": p.role, "map_version": p.map_version}


def session_of(p):
    return sessions.get(p.session)


def persist(kind, obj):
    if not data_dir:
        return
    try:
        os.makedirs(data_dir, exist_ok=True)
        with open(os.path.join(data_dir, kind + ".jsonl"), "a", encoding="utf-8") as f:
            f.write(json.dumps(obj, separators=(",", ":")) + "\n")
    except OSError:
        log("can't write to", data_dir)


def load_state():
    """Sessions and runs from before a restart (only with --data-dir)."""
    if not data_dir:
        return
    path = os.path.join(data_dir, "sessions.jsonl")
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            try:
                d = json.loads(line)
            except ValueError:
                continue
            code = str(d.get("session", ""))[:12]
            if code:
                sessions[code] = {"secret": str(d.get("secret", "")), "made": float(d.get("made", 0.0)),
                                  "map": str(d.get("map", ""))[:80], "map_version": int(d.get("map_version", 0)),
                                  "peers": {}, "runs": [], "seen": time.monotonic()}
    path = os.path.join(data_dir, "runs.jsonl")
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            try:
                d = json.loads(line)
            except ValueError:
                continue
            code = str(d.get("session", ""))[:12]
            if code in sessions and isinstance(d.get("run"), dict):
                sessions[code]["runs"].append(d["run"])


def number(v, lo, hi, default=0.0):
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        return default
    v = float(v)
    if not math.isfinite(v):
        return default
    return max(lo, min(hi, v))


async def broadcast(code, obj, skip=None, roles=("maker", "editor", "tester")):
    s = sessions.get(code)
    if s is None:
        return
    for p in list(s["peers"].values()):
        if p is not skip and p.role in roles:
            await p.send(obj)


async def reject(p, code, message):
    await p.send({"t": "error", "code": code, "message": message})
    await asyncio.sleep(0.15)        # (let the client read why before the socket goes)
    await p.close(1008, code)


# ---------------------------------------------------------------------------------------------- messages

async def on_hello(p, msg):
    role = msg.get("role")
    if role not in ROLES:
        return await reject(p, "bad_role", "Unknown role.")
    p.role = role
    p.tokens = RATES[role][1]          # (a fresh connection may spend a full burst before it is throttled)
    p.rate_t = time.monotonic()
    p.name = str(msg.get("name", ""))[:40].strip() or role.capitalize()
    p.map_version = int(number(msg.get("map_version", 0), 0, 10 ** 9))
    code = str(msg.get("session", "")).strip().upper()[:12]
    secret = str(msg.get("secret", ""))[:128]

    if role == "maker" and code == "":
        if len(sessions) >= MAX_SESSIONS:
            return await reject(p, "busy", "The relay has too many sessions right now.")
        code = new_code()
        sessions[code] = {"secret": secrets.token_hex(16), "made": time.time(),
                          "map": str(msg.get("map", ""))[:80], "map_version": p.map_version,
                          "peers": {}, "runs": [], "seen": time.time()}
        persist("sessions", {"session": code, "secret": sessions[code]["secret"], "made": sessions[code]["made"],
                             "map": sessions[code]["map"], "map_version": p.map_version})
        log("session", code, "opened by", p.name)
    else:
        s = sessions.get(code)
        if s is None:
            return await reject(p, "unknown_session", "No playtest session with that code.")
        if not secret or not hmac.compare_digest(secret, s["secret"]):
            return await reject(p, "bad_secret", "That session's secret doesn't match.")
        if len(s["peers"]) >= MAX_PEERS:
            return await reject(p, "session_full", "This session already has %d people in it." % MAX_PEERS)

    s = sessions[code]
    p.session = code
    s["peers"][p.id] = p
    s["seen"] = time.time()
    welcome = {"t": "welcome", "you": p.id, "session": code, "map_version": s["map_version"],
               "runs": len(s["runs"]), "peers": [peer_brief(x) for x in s["peers"].values() if x is not p]}
    if role == "maker":
        welcome["secret"] = s["secret"]
    await p.send(welcome)
    await broadcast(code, {"t": "peer_join", "peer": peer_brief(p)}, skip=p)
    log("joined:", p.name, p.role, code)


async def on_message(p, msg):
    t = msg.get("t")
    if t != "live":
        log("msg", p.name or "?", t)
    if p.session == "":
        if t != "hello":
            return await reject(p, "need_hello", "The first message must be hello.")
        return await on_hello(p, msg)
    s = session_of(p)
    if s is None:
        return await reject(p, "unknown_session", "That session is gone.")

    if t == "live":
        if p.role != "tester":
            return
        at = msg.get("p")
        if not isinstance(at, list) or len(at) != 3:
            return
        state = str(msg.get("state", "run"))[:8]
        await broadcast(p.session, {
            "t": "live", "id": p.id, "name": p.name,
            "attempt": int(number(msg.get("attempt", 0), 0, 10 ** 6)),
            "p": [round(number(at[0], -1e6, 1e6), 2), round(number(at[1], -1e6, 1e6), 2),
                  round(number(at[2], -1e6, 1e6), 2)],
            "speed": int(number(msg.get("speed", 0), 0, 100000)),
            "stage": int(number(msg.get("stage", 0), 0, 999)),
            "state": state if state in ("wait", "run", "finish") else "run",
        }, skip=p, roles=FORWARD_TO)

    elif t == "attempt":
        if p.role != "tester":
            return
        a = msg.get("attempt")
        if not isinstance(a, dict) or str(a.get("outcome", "")) not in ("finish", "restart", "quit"):
            return
        try:
            size = len(json.dumps(a))
        except (TypeError, ValueError):
            return
        if size > MAX_ATTEMPT:
            return await reject(p, "too_big", "That run is too big.")
        run = {"tester": p.name, "map_version": p.map_version, "attempt": a, "at": time.time()}
        s["runs"].append(run)
        if len(s["runs"]) > MAX_RUNS:
            s["runs"] = s["runs"][-MAX_RUNS:]
        persist("runs", {"session": p.session, "run": run})
        await broadcast(p.session, {"t": "attempt", "id": p.id, "name": p.name, "attempt": a}, skip=p)

    elif t == "collect":
        if p.role == "maker":
            await p.send({"t": "runs", "runs": s["runs"]})

    elif t in ("edit", "cursor", "state"):
        # 0.17 co-editing: passed to the maker and the other editors, after the same checks
        if p.role not in ("maker", "editor"):
            return
        if len(json.dumps(msg)) > MAX_MESSAGE // 2:
            return await reject(p, "too_big", "That message is too big.")
        out = dict(msg)
        out["id"] = p.id
        out["name"] = p.name
        await broadcast(p.session, out, skip=p, roles=FORWARD_TO)

    elif t == "ping":
        await p.send({"t": "pong", "at": msg.get("at", 0)})

    elif t == "bye":
        p.closed = True


# ---------------------------------------------------------------------------------------------- connection

async def leave(p):
    s = session_of(p)
    if s is None or p.id not in s["peers"]:
        return
    s["peers"].pop(p.id, None)
    s["seen"] = time.time()
    await broadcast(p.session, {"t": "peer_leave", "id": p.id}, skip=p)
    log("left:", p.name, p.session)


async def keepalive(p):
    while not p.closed:
        await asyncio.sleep(PING_EVERY)
        if time.monotonic() - p.last > STALE_AFTER:
            p.closed = True
            try:
                p.writer.close()
            except OSError:
                pass
            return
        await p.raw(0x9, b"")


async def serve_peer(p, reader):
    task = asyncio.create_task(keepalive(p))
    parts = []
    frag_op = 0
    try:
        while not p.closed:
            fin, op, payload = await ws_read(reader)
            p.last = time.monotonic()
            if op == 0x8:
                break
            if op == 0x9:
                await p.raw(0xA, payload)
                continue
            if op == 0xA:
                continue
            if op in (0x1, 0x2):
                if not fin:
                    parts, frag_op = [payload], op
                    continue
                text, body = op == 0x1, payload
            elif op == 0x0 and parts:
                parts.append(payload)
                if sum(len(x) for x in parts) > MAX_MESSAGE:
                    raise TooBig()
                if not fin:
                    continue
                text, body = frag_op == 0x1, b"".join(parts)
                parts = []
            else:
                continue
            if not text:
                continue
            if not p.allow():
                await p.close(1008, "too many messages")
                break
            try:
                msg = json.loads(body.decode("utf-8"))
            except (UnicodeDecodeError, ValueError):
                await p.send({"t": "error", "code": "bad_json", "message": "Messages must be JSON."})
                continue
            if not isinstance(msg, dict):
                await p.send({"t": "error", "code": "bad_message", "message": "Messages must be JSON objects."})
                continue
            await on_message(p, msg)
    except TooBig:
        log("too big", p.name or "?")
        await p.close(1009, "message too big")
    except (asyncio.IncompleteReadError, ConnectionError, OSError) as e:
        log("socket gone", p.name or "?", type(e).__name__)
    except Exception:
        import traceback
        log("ERROR", p.name or "?", traceback.format_exc().replace("\n", " | "))
    finally:
        log("closed", p.name or "?", p.session or "-")
        p.closed = True
        task.cancel()
        await leave(p)
        try:
            p.writer.close()
        except OSError:
            pass


async def handle(reader, writer):
    try:
        head = await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), 10.0)
    except (asyncio.IncompleteReadError, asyncio.LimitOverrunError, asyncio.TimeoutError, ConnectionError):
        writer.close()
        return
    text = head.decode("latin-1")
    lines = text.split("\r\n")
    if not lines or not lines[0].startswith("GET "):
        writer.close()
        return
    path = lines[0].split(" ")[1].split("?")[0]

    headers = {}
    for line in lines[1:]:
        if ":" in line:
            k, v = line.split(":", 1)
            headers[k.strip().lower()] = v.strip()

    if path == "/health":
        body = json.dumps({"ok": True, "sessions": len(sessions)}).encode()
        writer.write(b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\n"
                     b"Connection: close\r\n\r\n" % len(body) + body)
        try:
            await writer.drain()
        except ConnectionError:
            pass
        writer.close()
        return

    key = headers.get("sec-websocket-key", "")
    if headers.get("upgrade", "").lower() != "websocket" or not key:
        writer.write(b"HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
        writer.close()
        return

    accept = base64.b64encode(hashlib.sha1((key + GUID).encode()).digest()).decode()
    writer.write(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                  "Sec-WebSocket-Accept: %s\r\n\r\n" % accept).encode())
    try:
        await writer.drain()
    except ConnectionError:
        writer.close()
        return
    await serve_peer(Peer(writer), reader)


async def prune():
    while True:
        await asyncio.sleep(600)
        now = time.time()
        for code in list(sessions):
            s = sessions[code]
            if not s["peers"] and now - s["seen"] > SESSION_FORGET:
                sessions.pop(code, None)
                log("forgot session", code)


async def main():
    ap = argparse.ArgumentParser(description="MALLET relay (docs/RELAY.md)")
    ap.add_argument("--host", default="127.0.0.1", help="address to listen on (0.0.0.0 in the container)")
    ap.add_argument("--port", type=int, default=8787)
    ap.add_argument("--data-dir", default="", help="keep sessions and runs here (a Docker volume)")
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--log", default="", help="also write a log to this file")
    args = ap.parse_args()

    global data_dir, quiet, log_path
    data_dir, quiet, log_path = args.data_dir, args.quiet, args.log
    load_state()
    server = await asyncio.start_server(handle, args.host, args.port)
    addrs = ", ".join(str(s.getsockname()) for s in server.sockets)
    print("MALLET relay listening on %s (sessions: %d)" % (addrs, len(sessions)), flush=True)
    asyncio.create_task(prune())
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
