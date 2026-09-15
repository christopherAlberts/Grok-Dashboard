# Cloudflare DNS + Tunnel for Grok Dashboards

Christopher must do these clicks. This host cannot access the Cloudflare account.

**Goal:** one apex name plus one wildcard, both through the **existing** tunnel, both to Caddy on this machine. After this, new apps are only a folder + deploy — no new Cloudflare hostname.

Public names (subdomains, not paths):

- `https://dash.streblainnovations.com/`
- `https://<slug>.dash.streblainnovations.com/` (example: `races`)

Origin on this Pi:

- Caddy HTTP: `127.0.0.1:8080` and `192.168.0.251:8080`
- `cloudflared` is **already running on this same host**, so the tunnel origin should be `http://127.0.0.1:8080` (not `:8111`, not `:8001`, not `:80`).

The public **502** happens when the tunnel still points at a dead port. Live ingress has used `http://192.168.0.251:8111` for the old `grok_dashboards` names — nothing listens on 8111. Point the **new** `dash` names at Caddy `:8080`.

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
2. Add (or edit) these two records. Proxy status = **Proxied** (orange cloud).

| Type | Name | Target | Proxy |
| --- | --- | --- | --- |
| CNAME | `dash` | `<the cfargotunnel.com hostname from A>` | Proxied |
| CNAME | `*.dash` | **same target** | Proxied |

3. Do **not** create a new record for `races.dash`. The wildcard covers it.
4. TTL can stay Auto.
5. Optional cleanup: delete `grok_dashboards` and `*.grok_dashboards` if you no longer want those names.

If Cloudflare already created these when you added public hostnames, confirm they match the same tunnel and are proxied.

---

## C. Tunnel public hostnames (this fixes the 502)

1. Zero Trust → **Networks → Tunnels** → the same tunnel → **Public Hostname**.
2. **Add** (or edit) hostname 1:

   - **Subdomain:** `dash`
   - **Domain:** `streblainnovations.com`
   - **Path:** empty
   - **Type:** HTTP
   - **URL:** `http://127.0.0.1:8080`

3. **Add** (or edit) hostname 2 (wildcard):

   - **Subdomain:** `*`
   - **Domain:** `dash.streblainnovations.com`
     (UI wording varies: you want Host `*.dash.streblainnovations.com`)
   - **Path:** empty
   - **Type:** HTTP
   - **URL:** `http://127.0.0.1:8080`

4. Save. Wait ~30 seconds.

**If `cloudflared` is ever moved off this Pi**, change both URLs to `http://192.168.0.251:8080` instead. While it runs here, `127.0.0.1:8080` is correct.

**Do not** point these names at `:8111`, `:8001`, `:80`, or `:443`. Caddy for this platform is **:8080 only**.

5. Remove or update the old public hostnames `grok_dashboards.streblainnovations.com` and `*.grok_dashboards.streblainnovations.com` (they were aimed at `:8111`).

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
- https://races.dash.streblainnovations.com/ → Garden Route placeholder

From this Pi (does not need Cloudflare):

```bash
curl -I -H 'Host: dash.streblainnovations.com' http://127.0.0.1:8080/
curl -I -H 'Host: races.dash.streblainnovations.com' http://127.0.0.1:8080/
```

Expect `HTTP/1.1 200` from Caddy (not nginx).

If local curl is 200 but the public URL is still 502, the tunnel public hostname URL is still wrong — re-do section C.
