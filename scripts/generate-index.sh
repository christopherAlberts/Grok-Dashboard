#!/usr/bin/env bash
# Rebuild the portal app list from sibling folders that contain index.html.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

APPS_DIR="${1:-}"
INDEX_HTML="${2:-}"

if [[ -z "$APPS_DIR" ]]; then
  if [[ -d "$APPS_ROOT" ]]; then
    APPS_DIR="$APPS_ROOT"
  else
    APPS_DIR="$(cd "$SCRIPT_DIR/../apps" && pwd)"
  fi
fi

if [[ -z "$INDEX_HTML" ]]; then
  INDEX_HTML="${APPS_DIR}/_index/index.html"
fi

if [[ ! -f "$INDEX_HTML" ]]; then
  echo "generate-index: missing $INDEX_HTML" >&2
  exit 1
fi

cards=""
shopt -s nullglob
for dir in "$APPS_DIR"/*/; do
  name="$(basename "$dir")"
  case "$name" in
    _*|.*) continue ;;
  esac
  if [[ ! -f "$dir/index.html" ]]; then
    continue
  fi
  title="$name"
  blurb="Published static app."
  case "$name" in
    races) blurb="Garden Route race dashboard (placeholder)." ;;
  esac
  cards+="      <a class=\"card\" href=\"https://${name}.${PLATFORM_DOMAIN}/\">
        <h2>${name}</h2>
        <p>${blurb}</p>
        <p class=\"url\">${name}.${PLATFORM_DOMAIN}</p>
      </a>
"
done
shopt -u nullglob

if [[ -z "$cards" ]]; then
  cards='      <div class="empty">No apps published yet. Create <code>apps/&lt;slug&gt;</code> and run <code>./scripts/deploy-app.sh &lt;slug&gt;</code>.</div>
'
fi

python3 - "$INDEX_HTML" "$cards" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
cards = sys.argv[2]
text = path.read_text(encoding="utf-8")
start = "<!-- APPS_START -->"
end = "<!-- APPS_END -->"
i = text.find(start)
j = text.find(end)
if i < 0 or j < 0 or j < i:
    sys.exit(f"generate-index: markers missing in {path}")
new = text[: i + len(start)] + "\n" + cards + text[j:]
path.write_text(new, encoding="utf-8")
PY

echo "generate-index: wrote app list into $INDEX_HTML"
