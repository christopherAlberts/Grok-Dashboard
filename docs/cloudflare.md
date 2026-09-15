# Cloudflare DNS + Tunnel for Grok Dashboards

Christopher must do these clicks. This host cannot access the Cloudflare account.

**Goal:** one public hostname. Apps are URL **paths**, so a new dashboard does **not** need a new Cloudflare DNS record or public hostname.

Public names:

- `https://dash.streblainnovations.com/` — portal
- `https://dash.streblainnovations.com/<slug>/` — an app (example: `races`)

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
2. Add (or edit) **one** record. Proxy status = **Proxied** (orange cloud).

| Type | Name | Target | Proxy |
| --- | --- | --- | --- |
| CNAME | `dash` | `<the cfargotunnel.com hostname from A>` | Proxied |

3. Do **not** add `*.dash`. Do **not** add a new CNAME per app.
4. Optional: keep `races` CNAME if you want `races.streblainnovations.com` to 301 to `/races/` (Caddy already redirects). New apps do not need this.
5. Optional cleanup: delete `grok_dashboards`, `*.grok_dashboards`, and `*.dash`.

TTL can stay Auto.

---

## C. Tunnel public hostnames

1. Zero Trust → **Networks → Tunnels** → the same tunnel → **Public Hostname**.
2. **Add** (or edit) **one** hostname:

   - **Subdomain:** `dash`
   - **Domain:** `streblainnovations.com`
   - **Path:** empty (Caddy routes `/` vs `/races/` itself)
   - **Type:** HTTP
   - **URL:** `http://127.0.0.1:8080`

3. Save. Wait ~30 seconds.

**If `cloudflared` is ever moved off this Pi**, change the URL to `http://192.168.0.251:8080`. While it runs here, `127.0.0.1:8080` is correct.

**Do not** point this name at `:8111`, `:8001`, `:80`, or `:443`. Caddy for this platform is **:8080 only**.

4. Optional: `races.streblainnovations.com` → same origin (Caddy 301s to `/races/`). Not required for new apps.

5. Remove leftover public hostnames `grok_dashboards…`, `*.grok_dashboards…`, `*.dash.streblainnovations.com` if present.

Do **not** add a tunnel catch-all `*.streblainnovations.com` → :8080; that would steal other apps on this tunnel.

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
- https://dash.streblainnovations.com/races/ → Garden Route race dashboard

From this Pi (does not need Cloudflare):

```bash
curl -I -H 'Host: dash.streblainnovations.com' http://127.0.0.1:8080/
curl -I -H 'Host: dash.streblainnovations.com' http://127.0.0.1:8080/races/
```

Expect `HTTP/1.1 200` from Caddy and race HTML with title **Garden Route Runs**.

If local curl is 200 but the public URL is still 502, the tunnel public hostname URL is still wrong — re-do section C.
