# Grok Dashboards

Reusable static-site host on this machine. New dashboards are folders. They become live as **paths** on one hostname. **No Cloudflare change is required for a new app.**

## URLs

| What | URL |
| --- | --- |
| Portal | https://dash.streblainnovations.com/ |
| An app | https://dash.streblainnovations.com/`<slug>`/ |
| Race dashboard | https://dash.streblainnovations.com/races/ |

LAN origin: `http://192.168.0.251:8080` (Caddy, HTTP only). Cloudflare Tunnel terminates TLS.

## How a request is served

1. Browser hits `https://dash.streblainnovations.com/races/`.
2. Cloudflare DNS (one proxied CNAME: `dash`) sends that name into the existing tunnel.
3. `cloudflared` on this host forwards HTTP to `127.0.0.1:8080`.
4. Caddy reads Host `dash.streblainnovations.com` and the path:
   - `/` → `/var/www/apps/_index` (portal)
   - `/<slug>/*` → `/var/www/apps/<slug>/` (prefix stripped so relative assets like `images/` work)
   - only if that folder exists; `_index` and `_logs` are not public slugs
5. The live files are copies of `apps/` in this git repo.

Coastal Hound Host names that still arrive on :8080 are reverse-proxied to nginx :8084.

`races.streblainnovations.com` 301s to `https://dash.streblainnovations.com/races/` if someone still uses the old host.

## Add a new app (one command)

```bash
# from this repo
mkdir -p apps/my-app
# put index.html (and assets) in apps/my-app/
./scripts/deploy-app.sh my-app
```

That app is then live at **https://dash.streblainnovations.com/my-app/**. Caddy does not reload. Cloudflare does not change.

Use **relative** asset paths (`images/hero.jpg`), not root-absolute (`/images/hero.jpg`).

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
apps/races/      Garden Route race dashboard
Caddyfile        canonical Caddy config (:8080, auto_https off)
scripts/         install-platform.sh, deploy-app.sh, sync-www.sh
docs/            Cloudflare click-path + security/audit
```

Live tree: `/var/www/apps/<slug>/` owned by user `deploy`.

## Cloudflare

Only **one** public hostname is required:

- `dash.streblainnovations.com` → `http://127.0.0.1:8080`

Do not add `*.dash` or a new hostname per app. Do not point this name at `:8111`.

Use `http://192.168.0.251:8080` only if `cloudflared` runs on a **different** machine.

Step-by-step: [docs/cloudflare.md](docs/cloudflare.md).

## Notes for this host

- Caddy listens on **8080**. nginx was already bound there for Coastal Hound; install moves that nginx listener to **8084** and Caddy reverse-proxies the Coastal Hound Host names back so existing tunnels to :8080 keep working.
- Do not open WAN port 22. Prefer Cloudflare Tunnel + Access for SSH (`ssh.streblainnovations.com` → `ssh://localhost:22`).
- Audit trail: git history in this repo **and** each live app dir, plus append-only `deploy.log`. See [docs/security-and-audit.md](docs/security-and-audit.md).
