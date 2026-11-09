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

**2b. If Nginx Proxy Manager runs in Docker** — this server does (`proxy_manager-app-1`) — NPM cannot reach the
server's own `127.0.0.1`, because inside that container `127.0.0.1` is NPM itself. Put the relay on NPM's network
and use the container's name in the proxy:

```
docker inspect --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' proxy_manager-app-1
docker network connect proxy_manager_default mallet-relay      # once; repeat after a fresh docker run
curl -s http://127.0.0.1:8787/health                          # still the host's own check
```

On the current server the command prints `nginx-proxy proxy_manager_default`; `proxy_manager_default` is the one NPM
shares with the containers it proxies, so use that name in the command above (substitute another name only if
your stack differs).

**3. Nginx Proxy Manager** (`https://npm.sebz.xyz`) > Hosts > Proxy Hosts > Add Proxy Host:

- Details: Domain Names `relay.sebz.xyz`, Scheme `http`, Forward Hostname (NPM in Docker: `mallet-relay`; NPM on
the host itself: `127.0.0.1`), Forward Port `8787`, **Websockets Support on**, Block Common Exploits on. (NPM then
  sets a one-hour read timeout, which is what an idle tester in the pause menu needs — no Advanced entries
  required.)
- SSL: Request a new SSL certificate, Force SSL on, HTTP/2 on, agree to the terms. Save.

**4. Test from outside** (any machine, including this one):

```
curl -s https://relay.sebz.xyz/health      # {"ok": true, "sessions": 0}
```

- 502 → the container isn't running, or NPM can't reach it: `docker logs --tail 20 mallet-relay`, and if NPM is
  in Docker make sure the relay was connected to its network (2b) and is forwarded to as `mallet-relay:8787`.
- TLS error → the DNS record for `relay.sebz.xyz` isn't pointing at this server (it should be an A record to the
  same IP as `npm.sebz.xyz`), or the certificate wasn't issued.
- A WebSocket that connects and closes at once → Websockets Support is off for that host.

**5. In MALLET**: Export > Playtest session… → Relay address `wss://relay.sebz.xyz/ws` → Start / join with the
code empty. You get a six-letter code; test builds made now carry it, and their runs and live positions arrive
while they play.

## Updating the relay later

Copy the folder, rebuild, replace the container, and put the new one back on NPM's network (a fresh container is
not on it, and without that step the proxy answers 502):

```
scp -r D:/SurfForge/relay <you>@sebz.xyz:~/mallet-relay
```

```
ssh <you>@sebz.xyz 'set -e; cd ~/mallet-relay && docker build -t mallet-relay . && docker rm -f mallet-relay && \
  docker run -d --name mallet-relay --restart unless-stopped -p 127.0.0.1:8787:8787 \
  -v mallet-relay-data:/data mallet-relay && docker network connect proxy_manager_default mallet-relay && \
  sleep 1 && curl -s http://127.0.0.1:8787/health'
curl -s https://relay.sebz.xyz/health        # {"ok": true, "sessions": n}
```

(`set -e` stops at the first failure, so a 502 is not reported as if it worked. `docker network connect` only once
per container; if a later step fails before it, the health check at the end is what catches it.)

Replacing the container ends every open connection. MALLET retries and rejoins the same session on its own, so a
restart during co-editing costs a few seconds and nothing else.

Sessions and runs live in the `mallet-relay-data` volume, so removing the container does not lose testers' runs.
The relay keeps no map (the maker's MALLET is the one true copy) and forgets a session after 12 idle hours.

## Logs and looking inside

```
docker logs --tail 50 -f mallet-relay      # joins, attempts received, refusals
docker exec mallet-relay ls -l /data       # sessions.jsonl, runs.jsonl
docker stats --no-stream mallet-relay
```
