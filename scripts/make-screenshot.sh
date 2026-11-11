#!/bin/bash
# Regenerates docs/example.png: runs the built app against a throwaway home folder
# filled with example dotfiles and snapshots, so no real config ends up in the image.
# Usage: scripts/make-screenshot.sh [light|dark]   (run ./build.sh first)
set -euo pipefail
cd "$(dirname "$0")/.."

THEME="${1:-dark}"
BIN="build/CLITool.app/Contents/MacOS/CLITool"
[ -x "$BIN" ] || { echo "Run ./build.sh first" >&2; exit 1; }

DEMO="$(mktemp -d)"
trap 'rm -rf "$DEMO"' EXIT

cat > "$DEMO/.zshrc" <<'ZSHRC'
# ~/.zshrc — example config

export EDITOR="nvim"
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"

# History
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY HIST_IGNORE_DUPS

# Aliases
alias ll='ls -lah'
alias gs='git status'
alias reload='source ~/.zshrc'

# Load local overrides if present
if [[ -f "$HOME/.zshrc.local" ]]; then
  source "$HOME/.zshrc.local"
fi

for dir in "$HOME/bin" "$HOME/go/bin"; do
  case ":$PATH:" in
    *":$dir:"*) ;;
    *) export PATH="$dir:$PATH" ;;
  esac
done

# Pure prompt (https://github.com/sindresorhus/pure)
fpath+=("/opt/homebrew/share/zsh/site-functions")
autoload -U promptinit; promptinit
prompt pure
ZSHRC
printf 'eval "$(/opt/homebrew/bin/brew shellenv)"\n' > "$DEMO/.zprofile"
printf '[user]\n\tname = Example User\n\temail = user@example.com\n' > "$DEMO/.gitconfig"
printf 'set -g mouse on\n' > "$DEMO/.tmux.conf"

# Seed a few snapshots for ~/.zshrc.
KEY="$(printf '%s' "$DEMO/.zshrc" | tr '/' '_' | sed 's/^_*//')"
SNAPS="$DEMO/Library/Application Support/CLITool/Snapshots/$KEY"
mkdir -p "$SNAPS"
A="11111111-1111-4111-8111-111111111111"
B="22222222-2222-4222-8222-222222222222"
C="33333333-3333-4333-8333-333333333333"
cp "$DEMO/.zshrc" "$SNAPS/$A.txt"
grep -v "pure\|promptinit\|site-functions" "$DEMO/.zshrc" > "$SNAPS/$B.txt"
head -12 "$DEMO/.zshrc" > "$SNAPS/$C.txt"
size() { wc -c < "$1" | tr -d ' '; }
cat > "$SNAPS/index.json" <<JSON
[
  {"id": "$A", "date": "2026-11-11T17:42:10Z", "note": "Before save", "automatic": true, "bytes": $(size "$SNAPS/$A.txt")},
  {"id": "$B", "date": "2026-11-11T17:30:02Z", "note": "Before installing pure", "automatic": false, "bytes": $(size "$SNAPS/$B.txt")},
  {"id": "$C", "date": "2026-11-09T09:05:44Z", "note": "Fresh machine setup", "automatic": false, "bytes": $(size "$SNAPS/$C.txt")}
]
JSON

mkdir -p docs
CFFIXED_USER_HOME="$DEMO" CLITOOL_SCREENSHOT="$PWD/docs/example.png" "$BIN" -theme "$THEME"
echo "Wrote docs/example.png"
