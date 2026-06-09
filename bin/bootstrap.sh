#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_DEPS=false

# Parse flags
for arg in "$@"; do
  case "$arg" in
    --deps) INSTALL_DEPS=true ;;
    *) echo "Unknown flag: $arg"; exit 1 ;;
  esac
done

echo "[Zephyrus] Bootstrapping from ${REPO}"
echo

# --- Install system dependencies (opt-in) ---
if $INSTALL_DEPS; then
  echo "[1/6] Installing system dependencies..."
  OS="$(uname -s)"

  if [[ "$OS" == "Darwin" ]]; then
    if ! command -v brew &>/dev/null; then
      echo "  [ERROR] Homebrew not found. Install from https://brew.sh"
      exit 1
    fi
    echo "  Running: brew bundle --file=${REPO}/Brewfile"
    brew bundle --file="${REPO}/Brewfile" --no-lock
  elif [[ "$OS" == "Linux" ]]; then
    if command -v apt-get &>/dev/null; then
      echo "  Installing apt packages..."
      sudo apt-get update -qq
      xargs -a "${REPO}/deps/apt-packages.txt" sudo apt-get install -y -qq
    else
      echo "  [WARN] apt not found. Install packages from deps/apt-packages.txt manually."
    fi
    # lazygit (not in apt)
    if ! command -v lazygit &>/dev/null; then
      echo "  Installing lazygit..."
      LAZYGIT_VERSION=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | grep -Po '"tag_name": "v\K[^"]*')
      curl -Lo /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
      tar xf /tmp/lazygit.tar.gz -C /tmp lazygit
      sudo install /tmp/lazygit /usr/local/bin/lazygit
      rm -f /tmp/lazygit /tmp/lazygit.tar.gz
    fi
  else
    echo "  [WARN] Unsupported OS: $OS. Install dependencies manually."
  fi
  echo
else
  echo "[1/6] Skipping dependency install (use --deps to enable)"
  echo
fi

# --- Link config assets ---
echo "[2/6] Linking config assets..."

mkdir -p "${HOME}/.config/kitty" "${HOME}/.config/tmux"

# nvim: symlink the directory (not into it)
if [ -d "${HOME}/.config/nvim" ] && [ ! -L "${HOME}/.config/nvim" ]; then
  echo "  Backing up existing nvim config to ~/.config/nvim.bak"
  mv "${HOME}/.config/nvim" "${HOME}/.config/nvim.bak"
fi
ln -sfn "${REPO}/nvim" "${HOME}/.config/nvim"
echo "  Linked nvim/ -> ~/.config/nvim"

# tmux: symlink config file and bin directory
ln -sf "${REPO}/tmux/tmux.conf" "${HOME}/.config/tmux/tmux.conf"
ln -sfn "${REPO}/tmux/bin" "${HOME}/.config/tmux/bin"
echo "  Linked tmux/tmux.conf -> ~/.config/tmux/tmux.conf"
echo "  Linked tmux/bin/ -> ~/.config/tmux/bin"

# kitty: symlink config files
ln -sf "${REPO}/kitty/kitty.conf" "${HOME}/.config/kitty/kitty.conf"
ln -sf "${REPO}/kitty/theme.conf" "${HOME}/.config/kitty/theme.conf"
ln -sf "${REPO}/kitty/font.conf" "${HOME}/.config/kitty/font.conf"
echo "  Linked kitty configs -> ~/.config/kitty/"

# zephyrus module config
ln -sfn "${REPO}/zephyrus" "${HOME}/.config/zephyrus"
echo "  Linked zephyrus/ -> ~/.config/zephyrus"

echo

# --- Clone kitty-themes if missing ---
echo "[3/6] Checking kitty-themes..."
KITTY_THEMES="${REPO}/kitty/kitty-themes"
if [ ! -d "$KITTY_THEMES" ]; then
  echo "  Cloning kitty-themes..."
  git clone --depth 1 https://github.com/dexpota/kitty-themes.git "$KITTY_THEMES"
else
  echo "  kitty-themes already present"
fi
echo

# --- Install tmux TPM if missing ---
echo "[4/6] Checking tmux TPM..."
TPM_DIR="${HOME}/.tmux/plugins/tpm"
if [ ! -d "$TPM_DIR" ]; then
  echo "  Cloning TPM..."
  git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
  echo "  After starting tmux, press prefix + I to install plugins"
else
  echo "  TPM already installed"
fi
echo

# --- Install Command Center ---
echo "[5/6] Installing Command Center..."

mkdir -p "${HOME}/.zephyrus/state"

if command -v uv &>/dev/null; then
    echo "  Using uv for package management"

    if [ ! -d "${REPO}/.venv" ]; then
        uv venv "${REPO}/.venv" --python python3
        echo "  Created virtual environment at ${REPO}/.venv"
    fi

    source "${REPO}/.venv/bin/activate"
    uv pip install -e "${REPO}/daemon" -e "${REPO}/cli" -e "${REPO}/mcp-server" -e "${REPO}/tui"

elif command -v pip3 &>/dev/null; then
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
echo

# --- PATH and final instructions ---
echo "[6/6] PATH setup & reminders..."

BIN_DIR="${REPO}/bin"
if [[ ":${PATH}:" != *":${BIN_DIR}:"* ]]; then
    echo "  Add this to your shell profile (.bashrc / .zshrc):"
    echo "    export PATH=\"${BIN_DIR}:\$PATH\""
else
    echo "  ${BIN_DIR} already in PATH"
fi

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
