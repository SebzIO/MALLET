# Running the relay

The protocol is in [docs/RELAY.md](../docs/RELAY.md). This file is only about putting it on the server, which
comes last: MALLET and the test builds are developed and tested against a local relay.

## On the development machine

```
python relay/relay.py --port 8787
```

Then point MALLET's playtest panel (or `tester.cfg` in a hand-made test build) at `ws://127.0.0.1:8787/ws`.
`python relay/relay.py --port 8787 --data-dir relay-data` keeps sessions and runs across restarts.

Check it answers: `curl http://127.0.0.1:8787/health`.

## On the VPS (Debian 12, Docker, sebz.xyz behind Nginx Proxy Manager)

1. Copy `relay/` to the server, then:
   ```
   docker build -t mallet-relay relay/
   docker run -d --name mallet-relay --restart unless-stopped \
     -p 127.0.0.1:8787:8787 -v mallet-relay-data:/data mallet-relay
   ```
   `127.0.0.1:8787:8787` keeps the container off the public internet: only the proxy reaches it.
2. Nginx Proxy Manager: a new Proxy Host for `relay.sebz.xyz` → `127.0.0.1:8787`, **Websockets Support on**,
   an SSL certificate with Force SSL on, and in Advanced:
   ```
   proxy_read_timeout 180s;
   proxy_send_timeout 180s;
   ```
   (a tester can sit in the pause menu for a few minutes; the default 60 s would cut them off).
3. Test from outside: `wss://relay.sebz.xyz/health` should return `{"ok": true, ...}`.

Sessions and runs live in the `mallet-relay-data` volume, so `docker rm` + `docker run` does not lose testers'
runs. Nothing else needs a volume or a database: the relay holds runs until the maker collects them.
