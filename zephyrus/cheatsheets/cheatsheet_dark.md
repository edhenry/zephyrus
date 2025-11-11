# ZEPHYRUS — Distributed Intelligence Console
### Ultimate Terminal Dev Cheat Sheet (Dark)

## 🐱 Kitty (macOS-style)
- New tab: ⌘T   • Close tab: ⌘W   • Next/Prev tab: ⌘⇧] / ⌘⇧[
- Search scrollback: ⌘F   • Copy/Paste: ⌘C / ⌘V
- Font size: ⌘+ / ⌘- / ⌘0

## 🔳 tmux (Prefix = Ctrl+a)
- New window: Prefix c
- Next/Prev window: Prefix n / Prefix p
- Vertical split: Prefix %
- Horizontal split: Prefix "
- Move panes: Prefix + arrows
- Toggle last pane: Ctrl+Tab (if bound to last-pane)
- Copy-mode: Prefix [
- Smart scroll: mouse / PgUp/PgDn → app in alt screen, copy-mode otherwise

## 🧠 Neovim (Leader = Space)
### Files & Search
- File tree: Space e
- Find file: Space f f
- Live grep: Space f g
- Recent files: Space f r

### Splits & Windows
- vsp / sp: split vertically/horizontally
- Move between splits: Ctrl+h/j/k/l
- Equalize: Space w =

### Buffers
- Next / Prev: Shift+l / Shift+h
- Close: Space c

### LSP & Diagnostics
- Go to def: gd
- References: gr
- Hover: K
- Rename: Space r n
- Code actions: Alt+.  (via kitty Cmd+. mapping)
- Show diagnostics tooltip: hover or `gl`
- Next / Prev diagnostic: ]d / [d

### Editing
- Save: Space w
- Format: Space f
- Comment: gc / gcc

### Terminal
- Toggle project terminal (tmux split): Ctrl+b %, etc.
- Terminal → Normal: Ctrl+\ Ctrl+n
- Normal → Terminal insert: i

## 🚀 Tools
### LazyGit
- Open: Space g g
- Quit: q

### k9s
- Open: Space k k
- Quit: q

### Claude (claudecode.nvim)
- Toggle panel (right float): Space a c
- Focus: Space a f
- Send selection: Space a s
- Close: Ctrl+q in panel or Space a q

## 🐞 Debugging
- Continue: F5
- Step Over: F10
- Step Into: F11
- Step Out: Shift+F11
- Toggle breakpoint: F9

## 🧰 Mason
- Open: :Mason
- Logs: :MasonLog

---
Layering:
- Kitty tabs → projects
- tmux windows → workflows per project
- tmux panes → terminals / editors / tools
- Neovim splits → code, tests, aux panels
