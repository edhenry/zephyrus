#!/usr/bin/env bash
# Zephyrus cheat overlay for Kitty
# Bind in kitty.conf:
#   map ctrl+shift+h launch --type=overlay --title "Zephyrus Cheats" --cwd=current --env ZE_CHALK=1 sh -lc "~/.config/zephyrus/overlays/kitty/cheat_overlay.sh"

set -euo pipefail

ZE_CHALK="${ZE_CHALK:-1}"
CHEATS_BASE="${HOME}/.config/zephyrus/cheatsheets"
SRC="${CHEATS_BASE}/cheatsheet_dark.md"
if [ "${ZE_CHALK}" = "0" ]; then
  SRC="${CHEATS_BASE}/cheatsheet_light.md"
fi

if [ ! -f "${SRC}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  SRC="${SCRIPT_DIR}/../../cheatsheets/cheatsheet_dark.md"
fi

if command -v glow >/dev/null 2>&1; then
  glow -s dark "${SRC}"
else
  cat "${SRC}"
fi | LESSCHARSET=utf-8 less -R
