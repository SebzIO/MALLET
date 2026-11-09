# Running the relay

The protocol is in [docs/RELAY.md](../docs/RELAY.md). This file is only about putting it on the server.

## The public relay

`wss://relay.sebz.xyz/ws` is MALLET's default relay address (Export > Playtest session…, remembered in Settings).
`https://relay.sebz.xyz/health` should answer `{"ok": true, "sessions": 0}`.

## On the development machine

```
python relay/relay.py --port 8787
```

Point MALLET at `ws://127.0.0.1:8787/ws` to try a session without the internet. `--data-dir relay-data` keeps
sessions and runs across restarts. Check it answers: `curl http://127.0.0.1:8787/health`.

## On the VPS (Debian 12, Docker, sebz.xyz, TLS through Nginx Proxy Manager)

**1. Copy the folder up** (from Git Bash here; repeat after changing `relay.py`):

```
scp -r D:/SurfForge/relay <you>@sebz.xyz:~/mallet-relay
```

**2. Build and start it** (on the server):

```
cd ~/mallet-relay
docker build -t mallet-relay .
docker run -d --name mallet-relay --restart unless-stopped \
  -p 127.0.0.1:8787:8787 -v mallet-relay-data:/data mallet-relay
curl -s http://127.0.0.1:8787/health        # {"ok": true, "sessions": 0}
```

`127.0.0.1:8787:8787` keeps the container off the public internet: only the proxy reaches it. If 8787 is already
taken on the server, publish `-p 127.0.0.1:8788:8787` instead and give the proxy port 8788.

**3. Nginx Proxy Manager** (`https://npm.sebz.xyz`) > Hosts > Proxy Hosts > Add Proxy Host:

- Details: Domain Names `relay.sebz.xyz`, Scheme `http`, Forward Hostname `127.0.0.1`, Forward Port `8787`,
  **Websockets Support on**, Block Common Exploits on. (NPM then sets a one-hour read timeout, which is what an
  idle tester in the pause menu needs — no Advanced entries required.)
- SSL: Request a new SSL certificate, Force SSL on, HTTP/2 on, agree to the terms. Save.

**4. Test from outside** (any machine, including this one):

```
curl -s https://relay.sebz.xyz/health      # {"ok": true, "sessions": 0}
```

- 502 → the container isn't running or the port is wrong: `docker logs --tail 20 mallet-relay`.
- TLS error → the DNS record for `relay.sebz.xyz` isn't pointing at this server (it should be an A record to the
  same IP as `npm.sebz.xyz`), or the certificate wasn't issued.
- A WebSocket that connects and closes at once → Websockets Support is off for that host.

**5. In MALLET**: Export > Playtest session… → Relay address `wss://relay.sebz.xyz/ws` → Start / join with the
code empty. You get a six-letter code; test builds made now carry it, and their runs and live positions arrive
while they play.

## Updating the relay later

```
scp -r D:/SurfForge/relay <you>@sebz.xyz:~/mallet-relay
ssh <you>@sebz.xyz 'cd ~/mallet-relay && docker build -t mallet-relay . && docker rm -f mallet-relay && \
  docker run -d --name mallet-relay --restart unless-stopped -p 127.0.0.1:8787:8787 \
  -v mallet-relay-data:/data mallet-relay'
```

Sessions and runs live in the `mallet-relay-data` volume, so removing the container does not lose testers' runs.
The relay keeps no map (the maker's MALLET is the one true copy) and forgets a session after 12 idle hours.

## Logs and looking inside

```
docker logs --tail 50 -f mallet-relay      # joins, attempts received, refusals
docker exec mallet-relay ls -l /data       # sessions.jsonl, runs.jsonl
docker stats --no-stream mallet-relay
```
