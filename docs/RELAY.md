# The MALLET relay (0.16 live playtesting, 0.17 co-editing)

One small server that every MALLET and test build connects **out** to, so nobody opens router ports and nobody
sees anyone else's IP address. The server only moves messages: the map maker's MALLET stays the one true copy of
the map, and test builds keep saving their runs to disk (0.15) whether or not the relay can be reached.

Files:

- `relay/relay.py` — the server. Python standard library only, so the Docker image needs no `pip install`.
- `relay/Dockerfile`, `relay/README.md` — how to run it on the VPS later.
- `core/relay.gd` — MALLET's side (`class_name Relay`): JSON over Godot's `WebSocketPeer`.
- `tests/relay_test.gd` — starts the server and drives two clients through the whole conversation.

## Running it locally

```
python relay/relay.py --port 8787
```

`--host 0.0.0.0` to listen on everything (the container does this), `--data-dir <folder>` to keep sessions and
runs across restarts, `--quiet` for tests. `GET /health` answers `{"ok": true, "sessions": n}` for the Docker
healthcheck and the proxy.

## Messages

Text frames, one JSON object each. The first message a client sends must be `hello`; the first reply is either
`welcome` or `error`. Unknown fields are ignored, every value is type- and range-checked, and oversized or
malformed messages are refused (never parsed into anything but plain data).

### hello (client → server)

```json
{"t": "hello", "v": 1, "role": "maker", "session": "", "secret": "", "name": "Maker",
 "map": "surf_emerald", "map_version": 3, "client": "MALLET 0.16.0 preview"}
```

- `role`: `maker` (the editor that owns the map), `tester` (a test build), `editor` (a co-editing peer, 0.17).
- A `maker` with an empty `session` **opens** a new session and gets a code and a secret back.
- Everyone else must give the session code and its secret. A wrong secret is refused (`bad_secret`) and closed.
- `map_version` is the test build number from 0.15 (`test_version`), so runs from an older build are labeled and
  never laid over a newer layout.

### welcome (server → client)

```json
{"t": "welcome", "you": "3f9a1c2e", "session": "K7QM2P", "map_version": 3, "runs": 4,
 "peers": [{"id": "a1b2c3d4", "name": "Sam", "role": "tester", "map_version": 3}],
 "secret": "…"}
```

`secret` is only sent to `maker` (it goes into the test builds they export, never into the map file).
`runs` is how many runs the relay is holding for the session.

### tester → server

```json
{"t": "live", "attempt": 2, "p": [128.5, 96.0, -32.25], "speed": 683, "stage": 2, "state": "run"}
{"t": "attempt", "attempt": {"outcome": "finish", "time": 24.517, "splits": [[2, 9.2]], "deaths": [],
 "route": [[x, y, z, speed], …], "top_speed": 1180, "finish_speed": 902, "started": 1762600000.0}}
```

`live` is sent at 10 a second while playing (the same rate as the recorded route), `attempt` once per attempt — the
exact dictionary `PlayMode.attempt_ended` already produces in 0.15, so the editor's existing importer can take it.
`state` is `wait` / `run` / `finish`.

### server → maker (and editors)

`live` and `attempt` are forwarded with `id` and `name` added:

```json
{"t": "live", "id": "a1b2c3d4", "name": "Sam", "attempt": 2, "p": [128.5, 96.0, -32.25],
 "speed": 683, "stage": 2, "state": "run"}
{"t": "attempt", "id": "a1b2c3d4", "name": "Sam", "attempt": {…}}
{"t": "peer_join", "peer": {"id": "a1b2c3d4", "name": "Sam", "role": "tester", "map_version": 3}}
{"t": "peer_leave", "id": "a1b2c3d4"}
{"t": "runs", "runs": [{"tester": "Sam", "map_version": 3, "attempt": {…}, "at": 1762600000.0}]}
```

`collect` (maker → server) asks for everything the relay is holding, so runs made while MALLET was closed still
arrive.

### 0.17 co-editing (same connection)

```json
{"t": "cursor", "pos": [x, y, z], "aim": [x, y, z], "sel": ["id…"], "doing": "dragging a ramp"}
{"t": "edit", "seq": 41, "op": {"kind": "ramp_points", "id": "…", "points": [...]}}
{"t": "state", "rev": 12, "map": {…}}
```

`cursor` is throttled to about 10 a second. `edit` messages are relayed to the maker and the other editors (never
back to the sender); the sender's own file stays authoritative and the editor applies remote edits without adding
them to its own undo history. `state` is the whole map for someone joining mid-session, chunked if it is large
(the relay refuses anything over 4 MB in one message).

## Limits and trust

- 32 people per session, 500 sessions, sessions forgotten after 12 idle hours.
- 4 MB per message (4 MB is also MALLET's client buffer), 256 KB per attempt, 5000 runs kept per session.
- Rate limits: testers 40 messages a second (10 a second is normal), makers and editors more; a client that
  floods is closed rather than slowed.
- Names are cut to 40 characters, numbers are clamped, strings are never used as paths or commands.
- The relay keeps no map: it only holds runs until `collect`.

## On the VPS (later, when the client side is done)

Docker, behind Nginx Proxy Manager with a subdomain and TLS (`wss://relay.example`), container port 8787,
`/data` as a volume so runs survive a restart. NPM needs **Websockets Support** switched on for the host, and
`proxy_read_timeout` of at least 120 s since a tester can idle in the menu. The exact steps are in
`relay/README.md`.
