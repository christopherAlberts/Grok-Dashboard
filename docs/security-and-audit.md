# Security and audit

## Who can change live files

| Identity | Scope |
| --- | --- |
| `admin` (sudo) | Full machine. Used for `scripts/install-platform.sh` and Caddyfile changes. |
| `deploy` | Home plus `/var/www/apps`. Day-to-day deploys: rsync into an app folder, git commit in that folder, append `deploy.log`. |
| `caddy` | Reads published files. Does not write apps. |
| Cloudflare Tunnel | Forwards HTTP to `127.0.0.1:8080`. TLS stays at Cloudflare. |

`deploy` is **not** root. sudoers grants only:

- `systemctl reload caddy`
- `systemctl status caddy`
- `caddy validate --config /etc/caddy/Caddyfile`

App publishes do **not** reload Caddy. Host routing is wildcard; a new folder is enough.

Authorized SSH key for `deploy` (only this key, unless Christopher adds more):

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJcBUyISD1Z50lAUmGBb5RP1YRO8IGX8NlVcpEsso2UP grok-bot-deploy
```

Permissions: `~deploy/.ssh` mode `700`, `authorized_keys` mode `600`, owner `deploy`.

## Audit trail (every change)

1. **Append-only log** — `/var/www/apps/_logs/deploy.log`  
   One line per action:

   `ISO-UTC | slug | action | commit | user=… host=… source=…`

   `chattr +a` is set so the file can be appended but not rewritten in place.

2. **Git on the platform repo** — `/home/admin/Desktop/Projects/Grok Dashboard`  
   Source of truth for Caddyfile, scripts, docs, and `apps/` stubs. Remote: `https://github.com/christopherAlberts/Grok-Dashboard.git`.

3. **Git inside each live app** — `/var/www/apps/<slug>/`  
   `deploy-app.sh` `git init`s if needed and commits after every rsync.

Together: who, which slug, which commit, when.

## Notify on external deploys

If a Cursor agent, CI job, or laptop uses the `deploy` key, **say so in chat** at deploy time (slug + commit). The log is the system of record; the chat ping is how humans notice an unexpected publish.

## Network / SSH

- Prefer **Cloudflare Tunnel SSH** (`ssh.streblainnovations.com` → `ssh://localhost:22`) behind **Cloudflare Access**. Do not open WAN port 22 on the router.
- This installer **does not** change `sshd`. On this host, effective sshd at install time was: `PubkeyAuthentication yes`, `PasswordAuthentication yes`, `PermitRootLogin without-password`. Tightening passwords (`PasswordAuthentication no`, `PermitRootLogin no`) is recommended but must be done only when a working pubkey login is confirmed, with the diff reviewed first.

## Secrets

- Never commit `.env`, tunnel tokens, or origin certificates to this repo.
- `cloudflared` on this machine uses a dashboard token in systemd — leave it there; do not copy it into git.
- Caddy `file_server` hides `.git` and `.env`.

## What `deploy` cannot do (by design)

- Edit `/etc/caddy/Caddyfile` without extra access
- Change nginx, Docker, or other sites
- Truncate `deploy.log`
- Become root except for the three sudoers commands above
