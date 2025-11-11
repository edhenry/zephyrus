#!/usr/bin/env bash
set -euo pipefail

REPO="${HOME}/zephyrus"

echo "[Zephyrus] Linking core assets from ${REPO}"

mkdir -p   "${HOME}/.config/kitty"   "${HOME}/.config/nvim"   "${HOME}/.config/zephyrus"

ln -sf "${REPO}/zephyrus"               "${HOME}/.config/zephyrus"
ln -sf "${REPO}/nvim"                   "${HOME}/.config/nvim"

echo
echo "Add this to your kitty.conf:"
echo "  map ctrl+shift+h launch --type=overlay --title 'Zephyrus Cheats' --cwd=current --env ZE_CHALK=1 sh -lc '~/.config/zephyrus/overlays/kitty/cheat_overlay.sh'"
echo
echo "Add this to your Neovim plugin loader (Lazy.nvim example):"
echo "  { dir = vim.fn.expand('~/.config/zephyrus/nvim'), lazy = false },"
