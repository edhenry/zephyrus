#!/usr/bin/env bash
set -Eeuo pipefail

# Debug mode: DEVINIT_DEBUG=1 or pass -v anywhere
if [[ "${DEVINIT_DEBUG:-0}" == "1" ]] || printf '%s ' "$@" | grep -q -- ' -v '; then
  set -x
fi

trap 'echo "❌ Error on line $LINENO (exit $?)"; exit 1' ERR

# ---- args
PROJECT_TYPE="${1:-}"; shift || true
# remove -v if present
if [[ "${PROJECT_TYPE}" == "-v" ]]; then PROJECT_TYPE="${1:-}"; shift || true; fi
PROJECT_NAME="${1:-}"

if [[ -z "${PROJECT_TYPE}" || -z "${PROJECT_NAME}" ]]; then
  cat <<USAGE
Usage: devinit [-v] <type> <project-name>
Types: python | node | go | rust | terraform | quarto | generic
USAGE
  exit 1
fi

# ---- paths
TEMPLATE_DIR="${DEV_TEMPLATES:-$HOME/Downloads/nvim_polyglot_bundle_v2/project-templates}"
PROJECT_ROOT="${DEV_ROOT:-$HOME/dev}"
PROJECT_DIR="$PROJECT_ROOT/$PROJECT_NAME"

echo "🧰 Templates: $TEMPLATE_DIR"
echo "📂 Project:   $PROJECT_DIR"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

if ! command -v git >/dev/null 2>&1; then echo "⚠️ git not found"; fi
git init -q || true

copy() { [[ -f "$TEMPLATE_DIR/$1" ]] && cp "$TEMPLATE_DIR/$1" . && echo "→ copied $1"; }

# ---- per-type scaffolding
case "$PROJECT_TYPE" in
  python)
    echo "🐍 Python: $PROJECT_NAME"
    copy "pyproject.toml" || true
    if ! command -v python3 >/dev/null 2>&1; then
      echo "❌ python3 not found"; exit 2
    fi
    echo "→ creating venv"
    python3 -m venv .venv
    # ensure activate exists
    if [[ ! -s .venv/bin/activate ]]; then echo "❌ venv activate missing"; exit 3; fi
    echo "→ installing ruff + black (may take a moment)"
    # keep pip quiet about version checks; be resilient offline
    export PIP_DISABLE_PIP_VERSION_CHECK=1
    set +e
    source .venv/bin/activate
    python -m pip install -U pip >/dev/null 2>&1
    python -m pip install -U ruff black
    rc=$?
    deactivate
    set -e
    if (( rc != 0 )); then echo "⚠️ pip install returned $rc (continuing)"; fi
    ;;
  node)
    echo "🟦 Node: $PROJECT_NAME"
    copy ".eslintrc.cjs"; copy ".prettierrc.json"; copy "package.json"
    if [[ -f package.json ]]; then
      echo "→ npm install"
      npm install
    fi
    ;;
  go)
    echo "🦫 Go: $PROJECT_NAME"
    command -v go >/dev/null 2>&1 && go mod init "$PROJECT_NAME" >/dev/null 2>&1 || true
    copy ".golangci.yml"
    ;;
  rust)
    echo "🦀 Rust: $PROJECT_NAME"
    command -v cargo >/dev/null 2>&1 && cargo init --vcs git . >/dev/null || true
    ;;
  terraform)
    echo "🌍 Terraform: $PROJECT_NAME"
    copy ".tflint.hcl"
    cat > versions.tf <<'TF'
terraform {
  required_version = ">= 1.0.0"
}
TF
    ;;
  quarto)
    echo "📚 Quarto: $PROJECT_NAME"
    copy "pyproject.toml"
    mkdir -p content
    printf "# %s\n" "$PROJECT_NAME" > content/index.qmd
    ;;
  generic|*)
    echo "📁 Generic: $PROJECT_NAME"
    ;;
esac

printf "# %s\n" "$PROJECT_NAME" > README.md

# ---- open in neovim + tmux (no nesting)
SESSION="proj-$PROJECT_NAME"
echo "✅ Ready. Launching Neovim…"

if [[ -n "${TMUX:-}" ]]; then
  # Option A: own session per project
  tmux has-session -t "$SESSION" 2>/dev/null || tmux new-session -ds "$SESSION" -c "$PROJECT_DIR" "nvim ."
  tmux switch-client -t "$SESSION"
  # Option B (alternative): use a new window in the current session
  # tmux new-window -c "$PROJECT_DIR" -n "$PROJECT_NAME" "nvim ."; tmux select-window -t ":$PROJECT_NAME"
else
  exec tmux new-session -As "$SESSION" -c "$PROJECT_DIR" "nvim ."
fi

