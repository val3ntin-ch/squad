#!/usr/bin/env bash
# Install squad for the current user: links bin/squad into ~/.local/bin.
# Run from a clone of the repository. Re-run after 'git pull' is not needed;
# the link points at the clone.
set -euo pipefail

here=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
bindir="${SQUAD_BIN_DIR:-$HOME/.local/bin}"

chmod +x "$here/bin/squad"
mkdir -p "$bindir"
ln -sf "$here/bin/squad" "$bindir/squad"
echo "Linked $bindir/squad -> $here/bin/squad"

case ":$PATH:" in
  *":$bindir:"*) ;;
  *) echo "Add $bindir to your PATH, for example:"
     echo "  echo 'export PATH=\"$bindir:\$PATH\"' >> ~/.zshrc" ;;
esac

echo "Next: 'squad doctor' to check requirements, 'squad config' to set your default team."
