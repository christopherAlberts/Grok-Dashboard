# Grok Dashboards

Reusable static-site host on this machine. New dashboards are folders. They become live on wildcard subdomains without adding a Cloudflare hostname each time.

## URLs

| What | URL |
| --- | --- |
| Portal (apex) | https://dash.streblainnovations.com/ |
| An app | https://`<slug>`.dash.streblainnovations.com/ |
| First stub | https://races.dash.streblainnovations.com/ |

LAN origin: `http://192.168.0.251:8080` (Caddy, HTTP only). Cloudflare Tunnel terminates TLS.

## How a request is served

1. Browser hits `https://races.dash.streblainnovations.com`.
2. Cloudflare DNS (proxied CNAME) sends the name into the existing tunnel.
3. `cloudflared` on this host forwards HTTP to `127.0.0.1:8080`.
4. Caddy reads the `Host` header:
   - `dash.streblainnovations.com` → `/var/www/apps/_index`
   - `*.dash.streblainnovations.com` → `/var/www/apps/<leftmost-label>/`
5. The live files are copies of `apps/` in this git repo.

You do **not** create a new Cloudflare public hostname per app. The wildcard `*.dash` covers every slug.

## Add a new app (one command)

```bash
# from this repo
mkdir -p apps/my-app
# put index.html (and assets) in apps/my-app/
./scripts/deploy-app.sh my-app
```

That app is then live at `https://my-app.dash.streblainnovations.com/` once the wildcard tunnel/DNS exists.

From this admin checkout the script uses sudo (the live tree is owned by `deploy`, who cannot read `/home/admin`). Remote agents should SSH as `deploy` and use `/home/deploy/Grok-Dashboard`.

Idempotent: run the same command again after edits. It rsyncs, commits inside `/var/www/apps/<slug>`, and appends `/var/www/apps/_logs/deploy.log`.

Sync everything currently in `apps/`:

```bash
./scripts/sync-www.sh
```

First-time machine install (Caddy, `deploy` user, directories, Caddyfile):

```bash
./scripts/install-platform.sh
```

## Layout

```
apps/_index/     portal (lists published slugs)
apps/races/      Garden Route race dashboard stub
Caddyfile        canonical Caddy config (:8080, auto_https off)
scripts/         install-platform.sh, deploy-app.sh, sync-www.sh
docs/            Cloudflare click-path + security/audit
```

Live tree: `/var/www/apps/<slug>/` owned by user `deploy`.

## Cloudflare (required for the public 502 to go away)

This repo cannot log into Cloudflare. In Zero Trust, both of these public hostnames must point at **this Caddy**, not at an old origin port:

- `dash.streblainnovations.com` → `http://127.0.0.1:8080`
- `*.dash.streblainnovations.com` → `http://127.0.0.1:8080`

Use `http://192.168.0.251:8080` only if `cloudflared` runs on a **different** machine.

DNS (proxied CNAME) for `dash` and `*.dash` must target the same `*.cfargotunnel.com` hostname.

Remove or stop using the old `grok_dashboards` / `*.grok_dashboards` public hostnames (they were pointed at dead `:8111`).

Step-by-step: [docs/cloudflare.md](docs/cloudflare.md).

## Notes for this host

- Caddy listens on **8080**. nginx was already bound there for Coastal Hound; install moves that nginx listener to **8084** and Caddy reverse-proxies the Coastal Hound Host names back so existing tunnels to :8080 keep working.
- Do not open WAN port 22. Prefer Cloudflare Tunnel + Access for SSH (`ssh.streblainnovations.com` → `ssh://localhost:22`).
- Audit trail: git history in this repo **and** each live app dir, plus append-only `deploy.log`. See [docs/security-and-audit.md](docs/security-and-audit.md).
