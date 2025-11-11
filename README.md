# ZEPHYRUS — Distributed Intelligence Console

Portable core pieces of your Zephyrus workspace.

Includes:
- Dark/Light cheat sheets
- Kitty overlay (Ctrl+Shift+H)
- Neovim floating cheat sheet (:ZephyrusCheat / <leader>ch)
- Branding prompt for generating the Zephyrus logo

## Layout

```text
zephyrus/
  cheatsheets/
    cheatsheet_dark.md
    cheatsheet_light.md
  overlays/
    kitty/
      cheat_overlay.sh
  nvim/
    plugin/
      zephyrus_cheat.lua
  branding/
    logo_prompt.txt
  bootstrap.sh
```

## Install (per host)

```bash
git clone <your-zephyrus-repo-url> ~/zephyrus
cd ~/zephyrus
./bootstrap.sh
```

Then:

1. Kitty:

```conf
map ctrl+shift+h launch --type=overlay --title "Zephyrus Cheats" --cwd=current --env ZE_CHALK=1 sh -lc "~/.config/zephyrus/overlays/kitty/cheat_overlay.sh"
```

2. Neovim (Lazy.nvim example):

```lua
{ dir = vim.fn.expand("~/.config/zephyrus/nvim"), lazy = false },
```

Integrate tmux + other configs in your main dotfiles repo using this as the core shared module.
