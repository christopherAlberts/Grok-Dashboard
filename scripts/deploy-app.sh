#!/usr/bin/env bash
# Deploy one app folder into /var/www/apps/<slug>/ and append deploy.log.
# Usage: ./scripts/deploy-app.sh <slug> [source-dir]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

# Dest is owned by deploy; source often lives under /home/admin (unreadable to deploy).
# Root can read the repo and write the live tree, then chown back to deploy.
if [[ "$(id -un)" != "deploy" && "$(id -u)" -ne 0 ]]; then
  exec sudo -E "$0" "$@"
fi

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <slug> [source-dir]" >&2
  exit 2
fi

slug="$1"
source_dir="${2:-$REPO_ROOT/apps/$slug}"

if ! slug_ok "$slug"; then
  echo "Invalid slug '$slug'. Use a DNS label: lowercase letters, digits, hyphens." >&2
  exit 2
fi

if [[ ! -d "$source_dir" ]]; then
  echo "Source directory not found: $source_dir" >&2
  exit 1
fi

if [[ ! -d "$APPS_ROOT" ]]; then
  echo "Live apps root missing: $APPS_ROOT (run scripts/install-platform.sh first)" >&2
  exit 1
fi

dest="$APPS_ROOT/$slug"
mkdir -p "$dest"

rsync -a --delete \
  --exclude '.git/' \
  --exclude '.env' \
  --exclude '.env.*' \
  "$source_dir"/ "$dest"/

platform_commit="none"
if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  platform_commit="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo none)"
fi

commit="$(ensure_app_git "$dest" "deploy ${slug} from ${source_dir} (platform ${platform_commit})")"

if [[ -x "$SCRIPT_DIR/generate-index.sh" ]]; then
  "$SCRIPT_DIR/generate-index.sh" "$APPS_ROOT" "$APPS_ROOT/_index/index.html" || true
  ensure_app_git "$APPS_ROOT/_index" "refresh portal listing after ${slug}" >/dev/null || true
fi

if [[ "$(id -u)" -eq 0 ]] && id deploy >/dev/null 2>&1; then
  chown -R deploy:deploy "$dest" 2>/dev/null || true
  if [[ -d "$APPS_ROOT/_index" ]]; then
    chown -R deploy:deploy "$APPS_ROOT/_index" 2>/dev/null || true
  fi
fi

log_deploy "$slug" "deploy" "$commit" "source=${source_dir} platform=${platform_commit}"

echo "Deployed ${slug} → ${dest}"
echo "URL: https://${slug}.${APP_BASE_DOMAIN}/"
echo "Logged: ${DEPLOY_LOG}"
