#!/usr/bin/env bash
#
# Link this checkout into the Omarchy plugin directory and enable it.
# There is no package to build. The deck is already in cards/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ID="io.github.tomfaulkner.tuts-tomb"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/${ID}"
SECTION="${TUTS_TOMB_SECTION:-right}"

if ! command -v omarchy >/dev/null 2>&1; then
  printf '%s\n' "This needs Omarchy 4 (the omarchy CLI is not on PATH)."
  exit 1
fi

mkdir -p "$(dirname "$DEST")"
# Validate the real tree. The checker rejects a plugin directory that is
# itself a symlink, which is how a checkout is linked in for development.
omarchy plugin validate "$ROOT"
ln -sfn "$ROOT" "$DEST"
omarchy plugin enable "$ID" --section "$SECTION" || true
omarchy bar move "$ID" --section "$SECTION" >/dev/null 2>&1 || true

printf '\n%s\n' "Enabled ${ID}."
printf '%s\n' "If the ▲ is not in the bar yet, restart the shell:"
printf '%s\n' "  omarchy-restart-shell"
printf '%s\n' "Open the table with:"
printf '%s\n' "  omarchy-shell shell toggle ${ID}"
