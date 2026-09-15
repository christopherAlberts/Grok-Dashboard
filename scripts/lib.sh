#!/usr/bin/env bash
# Shared helpers for Grok Dashboard platform scripts.
set -euo pipefail

PLATFORM_DOMAIN="${PLATFORM_DOMAIN:-grok_dashboards.streblainnovations.com}"
APPS_ROOT="${APPS_ROOT:-/var/www/apps}"
DEPLOY_LOG="${DEPLOY_LOG:-${APPS_ROOT}/_logs/deploy.log}"

slug_ok() {
  local slug="$1"
  [[ "$slug" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]] && [[ "$slug" != "_index" ]] && [[ "$slug" != "_logs" ]]
}

log_deploy() {
  local slug="$1" action="$2" commit="$3" note="$4"
  local ts user_name
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  user_name="${SUDO_USER:-${USER:-unknown}}"
  mkdir -p "$(dirname "$DEPLOY_LOG")"
  printf '%s | %s | %s | %s | user=%s host=%s %s\n' \
    "$ts" "$slug" "$action" "${commit:-none}" "$user_name" "$(hostname -s)" "$note" >> "$DEPLOY_LOG"
}

ensure_app_git() {
  local dest="$1" message="$2"
  export GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-Grok Dashboard Deploy}"
  export GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-deploy@localhost}"
  export GIT_COMMITTER_NAME="${GIT_COMMITTER_NAME:-Grok Dashboard Deploy}"
  export GIT_COMMITTER_EMAIL="${GIT_COMMITTER_EMAIL:-deploy@localhost}"
  # Mixed root/deploy ownership is expected during install.
  local git=(git -c "safe.directory=$dest" -c "safe.directory=*")
  if [[ ! -d "$dest/.git" ]]; then
    "${git[@]}" -C "$dest" init -q
  fi
  "${git[@]}" -C "$dest" add -A
  if "${git[@]}" -C "$dest" diff --cached --quiet 2>/dev/null; then
    "${git[@]}" -C "$dest" rev-parse --short HEAD 2>/dev/null || echo "none"
    return 0
  fi
  "${git[@]}" -C "$dest" -c user.name="$GIT_AUTHOR_NAME" -c user.email="$GIT_AUTHOR_EMAIL" commit -q -m "$message"
  "${git[@]}" -C "$dest" rev-parse --short HEAD
}
