# Cloudflare DNS + Tunnel for Grok Dashboards

Christopher must do these clicks. This host cannot access the Cloudflare account.

**Goal:** portal + each app as a **first-level** subdomain of `streblainnovations.com`, both through the **existing** tunnel, both to Caddy on this machine.

Public names (subdomains, not paths — and **not** nested under `dash`):

- `https://dash.streblainnovations.com/` — portal
- `https://races.streblainnovations.com/` — Garden Route race dashboard

Cloudflare Universal SSL covers `*.streblainnovations.com`. It does **not** cover `*.dash.streblainnovations.com`, so apps must not use that nested pattern.

Origin on this Pi:

- Caddy HTTP: `127.0.0.1:8080` and `192.168.0.251:8080`
- `cloudflared` is **already running on this same host**, so the tunnel origin should be `http://127.0.0.1:8080` (not `:8111`, not `:8001`, not `:80`).

---

## A. Copy the tunnel CNAME target

1. Open [Cloudflare Zero Trust](https://one.dash.cloudflare.com/).
2. Go to **Networks → Tunnels**.
3. Open the tunnel this Pi already uses (`cloudflared` systemd service on `streblainnovations`).
4. On the tunnel overview, copy the connector hostname. It looks like:

   `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx.cfargotunnel.com`

   You will paste that as the CNAME **target** below. Do not invent a new tunnel.

---

## B. DNS (zone `streblainnovations.com`)

1. Cloudflare dashboard → **streblainnovations.com** → **DNS** → **Records**.
2. Add (or edit) these records. Proxy status = **Proxied** (orange cloud).

| Type | Name | Target | Proxy |
| --- | --- | --- | --- |
| CNAME | `dash` | `<the cfargotunnel.com hostname from A>` | Proxied |
| CNAME | `races` | **same target** | Proxied |

3. Do **not** add `*.dash` for apps (nested wildcard / no free SSL).
4. Do **not** add a catch-all `*` on `streblainnovations.com` that would collide with existing app CNAMEs. Each new dashboard gets its own `slug` CNAME like `races`.
5. Optional cleanup: delete `grok_dashboards`, `*.grok_dashboards`, and `*.dash` if they exist.

TTL can stay Auto.

---

## C. Tunnel public hostnames

1. Zero Trust → **Networks → Tunnels** → the same tunnel → **Public Hostname**.
2. **Add** (or edit) hostname 1:

   - **Subdomain:** `dash`
   - **Domain:** `streblainnovations.com`
   - **Path:** empty
   - **Type:** HTTP
   - **URL:** `http://127.0.0.1:8080`

3. **Add** (or edit) hostname 2:

   - **Subdomain:** `races`
   - **Domain:** `streblainnovations.com`
   - **Path:** empty
   - **Type:** HTTP
   - **URL:** `http://127.0.0.1:8080`

4. Save. Wait ~30 seconds.

**If `cloudflared` is ever moved off this Pi**, change both URLs to `http://192.168.0.251:8080` instead. While it runs here, `127.0.0.1:8080` is correct.

**Do not** point these names at `:8111`, `:8001`, `:80`, or `:443`. Caddy for this platform is **:8080 only**.

5. Remove old public hostnames `grok_dashboards…`, `*.grok_dashboards…`, `*.dash.streblainnovations.com`, and `races.dash…` if present.

Do **not** add a tunnel catch-all `*.streblainnovations.com` → :8080; that would steal other apps on this tunnel. Caddy already serves an existing `/var/www/apps/<slug>` when Host is `<slug>.streblainnovations.com`, so a new app only needs its own DNS + public hostname.

---

## D. Optional: SSH for remote agents (keep port 22 off the WAN)

1. Same tunnel → **Public Hostname** → Add:
   - **Subdomain:** `ssh`
   - **Domain:** `streblainnovations.com`
   - **Type:** SSH
   - **URL:** `ssh://localhost:22`
2. Zero Trust → **Access → Applications** → Add an application of type **SSH** (or self-hosted covering `ssh.streblainnovations.com`).
3. Restrict to your email / Google / one-time PIN. Do not leave SSH published without Access.
4. Client: Cloudflare `cloudflared access ssh` config, or the Zero Trust SSH docs. Do **not** port-forward 22 on the router.

---

## E. Quick checks after saving

From any browser:

- https://dash.streblainnovations.com/ → portal page
- https://races.streblainnovations.com/ → Garden Route race dashboard

From this Pi (does not need Cloudflare):

```bash
curl -I -H 'Host: dash.streblainnovations.com' http://127.0.0.1:8080/
curl -I -H 'Host: races.streblainnovations.com' http://127.0.0.1:8080/
```

Expect `HTTP/1.1 200` from Caddy and race HTML with title **Garden Route Runs**.

If local curl is 200 but the public URL is still 502, the tunnel public hostname URL is still wrong — re-do section C.
