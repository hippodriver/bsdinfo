#!/bin/sh
# Install bsdinfo (GUI + TUI) for the current user, and register the XFCE menu
# entries.
#
# Usage:
#   PREFIX=/usr/local ./packaging/install.sh
#   ./packaging/install.sh                 # defaults to ~/.local
set -eu

PREFIX="${PREFIX:-$HOME/.local}"
BINDIR="$PREFIX/bin"
APPDIR="$PREFIX/share/applications"
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

echo "Building bsdinfo (release)..."
( cd "$ROOT" && nim c -d:release --out:bsdinfo src/bsdinfo.nim )

mkdir -p "$BINDIR" "$APPDIR"
install -m 755 "$ROOT/bsdinfo" "$BINDIR/bsdinfo"

for entry in bsdinfo.desktop bsdinfo-tui.desktop; do
  sed "s|^Exec=bsdinfo|Exec=$BINDIR/bsdinfo|" \
    "$ROOT/packaging/$entry" > "$APPDIR/$entry"
  chmod 644 "$APPDIR/$entry"
  echo "Installed $APPDIR/$entry"
done

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APPDIR" >/dev/null 2>&1 || true
fi

echo "Installed $BINDIR/bsdinfo"
echo "bsdinfo now appears in the XFCE application menu (category: System)."
