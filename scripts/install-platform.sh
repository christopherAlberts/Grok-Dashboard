#!/usr/bin/env bash
# Install Caddy, deploy user, live apps tree, SSH key, and Caddyfile on this host.
# Safe to re-run (idempotent). Requires sudo.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

DEPLOY_USER="${DEPLOY_USER:-deploy}"
DEPLOY_PUBKEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJcBUyISD1Z50lAUmGBb5RP1YRO8IGX8NlVcpEsso2UP grok-bot-deploy'
NGINX_ORIGIN_PORT="${NGINX_ORIGIN_PORT:-8084}"
COASTALHOUND_NGINX="${COASTALHOUND_NGINX:-/etc/nginx/sites-available/coastalhound}"

need_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    exec sudo -E env APPS_ROOT="$APPS_ROOT" "$0" "$@"
  fi
}

log() { printf '[install-platform] %s\n' "$*"; }

record_status() {
  local label="$1"
  log "=== service status (${label}) ==="
  systemctl is-active nginx 2>/dev/null | sed 's/^/nginx: /' || true
  systemctl is-active caddy 2>/dev/null | sed 's/^/caddy: /' || true
  systemctl is-active cloudflared 2>/dev/null | sed 's/^/cloudflared: /' || true
  ss -tlnH | awk '$4 ~ /:8080$|:8084$|:80$|:443$/ {print}' || true
}

install_caddy() {
  if command -v caddy >/dev/null 2>&1; then
    log "Caddy already installed: $(caddy version 2>/dev/null | head -1)"
    return 0
  fi

  log "Installing Caddy from the official stable apt repository"
  apt-get update -qq
  apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl gnupg rsync git

  install -d -m 0755 /usr/share/keyrings
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
  chmod o+r /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  chmod o+r /etc/apt/sources.list.d/caddy-stable.list

  apt-get update -qq
  if ! DEBIAN_FRONTEND=noninteractive apt-get install -y caddy; then
    if ! command -v caddy >/dev/null 2>&1; then
      log "ERROR: Caddy package failed and the binary is missing"
      return 1
    fi
    log "Caddy package reported an error (often :80 already taken by nginx). Binary is present; continuing."
  fi
  systemctl stop caddy 2>/dev/null || true
  log "Caddy installed: $(caddy version | head -1)"
}

ensure_deploy_user() {
  if id -u "$DEPLOY_USER" >/dev/null 2>&1; then
    log "User ${DEPLOY_USER} already exists"
  else
    log "Creating user ${DEPLOY_USER}"
    useradd --create-home --shell /bin/bash --comment "Grok Dashboard deploys" "$DEPLOY_USER"
  fi

  local ssh_dir="/home/${DEPLOY_USER}/.ssh"
  local keys="${ssh_dir}/authorized_keys"
  install -d -m 0700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$ssh_dir"
  touch "$keys"
  chown "$DEPLOY_USER:$DEPLOY_USER" "$keys"
  chmod 0600 "$keys"
  if ! grep -qF "AAAAC3NzaC1lZDI1NTE5AAAAIJcBUyISD1Z50lAUmGBb5RP1YRO8IGX8NlVcpEsso2UP" "$keys"; then
    printf '%s\n' "$DEPLOY_PUBKEY" >> "$keys"
    log "Authorized grok-bot-deploy key for ${DEPLOY_USER}"
  else
    log "grok-bot-deploy key already present"
  fi
  chmod 0600 "$keys"
  chown "$DEPLOY_USER:$DEPLOY_USER" "$keys"
}

ensure_www_tree() {
  install -d -m 0755 /var/www
  install -d -m 0755 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$APPS_ROOT"
  install -d -m 0755 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$APPS_ROOT/_index"
  install -d -m 0755 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$APPS_ROOT/_logs"
  install -d -m 0755 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$APPS_ROOT/races"

  if [[ -f "$DEPLOY_LOG" ]]; then
    chattr -a "$DEPLOY_LOG" 2>/dev/null || true
  else
    umask 022
    sudo -u "$DEPLOY_USER" touch "$DEPLOY_LOG"
  fi
  chown "$DEPLOY_USER:$DEPLOY_USER" "$DEPLOY_LOG"
  chmod 0644 "$DEPLOY_LOG"
  if command -v chattr >/dev/null 2>&1; then
    chattr +a "$DEPLOY_LOG" 2>/dev/null || log "note: could not set append-only on deploy.log (chattr +a)"
  fi
}

free_port_8080_from_nginx() {
  if [[ ! -f "$COASTALHOUND_NGINX" ]]; then
    log "No ${COASTALHOUND_NGINX}; skipping nginx :8080 move"
    return 0
  fi
  if grep -qE 'listen \[::\]:8084;|listen 8084;' "$COASTALHOUND_NGINX" \
     && ! grep -qE 'listen \[::\]:8080;|listen 8080;' "$COASTALHOUND_NGINX"; then
    log "nginx Coastal Hound origin already on :${NGINX_ORIGIN_PORT}"
    return 0
  fi
  if ! grep -qE 'listen 8080;' "$COASTALHOUND_NGINX"; then
    log "nginx Coastal Hound is not listening on :8080; nothing to move"
    return 0
  fi

  local bak="${COASTALHOUND_NGINX}.bak.grok-dashboard-$(date -u +%Y%m%dT%H%M%SZ)"
  cp -a "$COASTALHOUND_NGINX" "$bak"
  log "Backed up nginx site to ${bak}"
  sed -i \
    -e "s/listen 8080;/listen ${NGINX_ORIGIN_PORT};/" \
    -e "s/listen \[::\]:8080;/listen [::]:${NGINX_ORIGIN_PORT};/" \
    "$COASTALHOUND_NGINX"
  nginx -t
  systemctl reload nginx
  log "Moved nginx Coastal Hound origin listener 8080 → ${NGINX_ORIGIN_PORT}"
}

install_caddyfile() {
  install -d -m 0755 /etc/caddy/Caddyfile.d
  cp "$REPO_ROOT/Caddyfile" /etc/caddy/Caddyfile
  cp "$REPO_ROOT/Caddyfile.d/placeholder.caddy" /etc/caddy/Caddyfile.d/placeholder.caddy

  cat > /etc/caddy/Caddyfile.d/coastalhound.caddy <<EOF
# Preserve Coastal Hound Cloudflare origin on :8080 after nginx moved to :${NGINX_ORIGIN_PORT}.
http://coastalhound.com:8080, http://www.coastalhound.com:8080, http://coastalhound.streblainnovations.com:8080, http://coastalhound.co.za:8080, http://www.coastalhound.co.za:8080 {
	reverse_proxy 127.0.0.1:${NGINX_ORIGIN_PORT}
}
EOF

  chmod 0644 /etc/caddy/Caddyfile /etc/caddy/Caddyfile.d/*.caddy
  caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
}

install_sudoers() {
  local file="/etc/sudoers.d/grok-dashboard-deploy"
  cat > "$file" <<EOF
# Limited Caddy reload for ${DEPLOY_USER} when the platform Caddyfile changes.
${DEPLOY_USER} ALL=(root) NOPASSWD: /bin/systemctl reload caddy, /bin/systemctl status caddy, /usr/bin/caddy validate --config /etc/caddy/Caddyfile
EOF
  chmod 0440 "$file"
  visudo -c -f "$file"
}

enable_caddy() {
  systemctl enable caddy
  systemctl restart caddy
  systemctl --no-pager --full status caddy | head -20
}

main() {
  need_root "$@"
  record_status "before"
  apt-get install -y rsync git curl python3 >/dev/null
  install_caddy
  ensure_deploy_user
  ensure_www_tree
  free_port_8080_from_nginx
  install_caddyfile
  install_sudoers

  # Live tree must be writable by deploy before sync.
  # append-only (chattr +a) on deploy.log blocks chown; lift it briefly.
  if [[ -f "$DEPLOY_LOG" ]]; then
    chattr -a "$DEPLOY_LOG" 2>/dev/null || true
  fi
  chown -R "$DEPLOY_USER:$DEPLOY_USER" "$APPS_ROOT"
  chmod -R u+rwX,go+rX "$APPS_ROOT"

  # deploy cannot traverse /home/admin. Keep a working copy in deploy's home,
  # and run the first sync as root then chown (git objects must end up deploy-owned).
  local deploy_src="/home/${DEPLOY_USER}/Grok-Dashboard"
  install -d -m 0755 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "$deploy_src"
  rsync -a --delete \
    --exclude '.git/' \
    "$REPO_ROOT"/ "$deploy_src"/
  chown -R "$DEPLOY_USER:$DEPLOY_USER" "$deploy_src"

  "$REPO_ROOT/scripts/sync-www.sh"
  chown -R "$DEPLOY_USER:$DEPLOY_USER" "$APPS_ROOT"
  chmod -R a+rX "$APPS_ROOT"
  chmod 0644 "$DEPLOY_LOG"
  chattr +a "$DEPLOY_LOG" 2>/dev/null || log "note: could not re-apply append-only on deploy.log"

  enable_caddy
  record_status "after"

  log "Local Host-header checks:"
  curl -sI -H "Host: ${PORTAL_DOMAIN}" "http://127.0.0.1:8080/" | head -15 || true
  curl -sI -H "Host: ${PORTAL_DOMAIN}" "http://127.0.0.1:8080/races/" | head -15 || true

  log "Done. Public TLS still depends on Cloudflare Tunnel hostnames pointing at http://127.0.0.1:8080"
}

main "$@"
