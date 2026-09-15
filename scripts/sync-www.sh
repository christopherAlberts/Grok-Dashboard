#!/usr/bin/env bash
# Sync every apps/<slug> from this repo into /var/www/apps (plus the portal).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

if [[ "$(id -un)" != "deploy" && "$(id -u)" -ne 0 ]]; then
  exec sudo -E "$0" "$@"
fi

if [[ ! -d "$APPS_ROOT" ]]; then
  echo "Live apps root missing: $APPS_ROOT (run scripts/install-platform.sh first)" >&2
  exit 1
fi

src_apps="$REPO_ROOT/apps"
if [[ ! -d "$src_apps" ]]; then
  echo "No apps/ directory in repo: $src_apps" >&2
  exit 1
fi

# Portal first so generate-index has a template on disk.
mkdir -p "$APPS_ROOT/_index"
rsync -a --delete \
  --exclude '.git/' \
  --exclude '.env' \
  --exclude '.env.*' \
  "$src_apps/_index"/ "$APPS_ROOT/_index"/

shopt -s nullglob
for dir in "$src_apps"/*/; do
  name="$(basename "$dir")"
  case "$name" in
    _index|_logs) continue ;;
    _*|.*) continue ;;
  esac
  "$SCRIPT_DIR/deploy-app.sh" "$name" "$dir"
done
shopt -u nullglob

"$SCRIPT_DIR/generate-index.sh" "$APPS_ROOT" "$APPS_ROOT/_index/index.html"
ensure_app_git "$APPS_ROOT/_index" "sync portal from platform repo" >/dev/null || true
log_deploy "_index" "sync-www" "$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo none)" "full tree sync from ${REPO_ROOT}"

echo "sync-www: live tree is ${APPS_ROOT}"
