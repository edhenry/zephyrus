#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"

echo "[Zephyrus] Bootstrapping from ${REPO}"
echo

# --- Link core config assets ---
echo "[1/4] Linking core assets..."

mkdir -p "${HOME}/.config/kitty" "${HOME}/.config/nvim" "${HOME}/.config/zephyrus"

ln -sf "${REPO}/zephyrus"               "${HOME}/.config/zephyrus"
ln -sf "${REPO}/nvim"                   "${HOME}/.config/nvim"

echo "  Linked zephyrus/, nvim/ to ~/.config/"

# --- Install Command Center ---
echo
echo "[2/4] Installing Command Center..."

mkdir -p "${HOME}/.zephyrus/state"

# Check for uv (preferred) or pip
if command -v uv &>/dev/null; then
    INSTALLER="uv"
    echo "  Using uv for package management"

    # Create venv if it doesn't exist
    if [ ! -d "${REPO}/.venv" ]; then
        uv venv "${REPO}/.venv" --python python3
        echo "  Created virtual environment at ${REPO}/.venv"
    fi

    # Install all three packages in dev mode
    source "${REPO}/.venv/bin/activate"
    uv pip install -e "${REPO}/daemon" -e "${REPO}/cli" -e "${REPO}/mcp-server" -e "${REPO}/tui"

elif command -v pip3 &>/dev/null; then
    INSTALLER="pip3"
    echo "  Using pip3 for package management"

    if [ ! -d "${REPO}/.venv" ]; then
        python3 -m venv "${REPO}/.venv"
        echo "  Created virtual environment at ${REPO}/.venv"
    fi

    source "${REPO}/.venv/bin/activate"
    pip3 install -e "${REPO}/daemon" -e "${REPO}/cli" -e "${REPO}/mcp-server" -e "${REPO}/tui"

else
    echo "  [WARN] Neither uv nor pip3 found. Install Python packages manually."
    echo "         pip install -e daemon/ -e cli/ -e mcp-server/ -e tui/"
fi

# --- Add bin/ to PATH ---
echo
echo "[3/4] PATH setup..."

BIN_DIR="${REPO}/bin"
if [[ ":${PATH}:" != *":${BIN_DIR}:"* ]]; then
    echo "  Add this to your shell profile (.bashrc / .zshrc):"
    echo "    export PATH=\"${BIN_DIR}:\$PATH\""
else
    echo "  ${BIN_DIR} already in PATH"
fi

# --- Integration instructions ---
echo
echo "[4/4] Integration reminders:"
echo
echo "  Kitty — add to kitty.conf:"
echo "    map ctrl+shift+h launch --type=overlay --title 'Zephyrus Cheats' --cwd=current --env ZE_CHALK=1 sh -lc '~/.config/zephyrus/overlays/kitty/cheat_overlay.sh'"
echo
echo "  Neovim — add to your plugin loader (lazy.nvim):"
echo "    { dir = '${REPO}/nvim-plugin', lazy = false },"
echo
echo "  Quick start:"
echo "    zeph up                  # start the command center"
echo "    zeph push 'My task'      # add a task"
echo "    zeph ls                  # list tasks"
echo "    zeph status              # check status"
echo "    zeph-tui                 # open TUI dashboard"
echo "    zeph down                # shut down"
echo
echo "[Zephyrus] Bootstrap complete."
