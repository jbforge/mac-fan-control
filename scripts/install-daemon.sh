#!/bin/bash
# Installs the fanctld LaunchDaemon. Run via `make install` (invokes sudo).
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "error: must run as root (use: make install)" >&2
    exit 1
fi

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BINARY="$REPO_DIR/.build/release/fanctld"
PLIST_SRC="$REPO_DIR/Resources/io.github.jbforge.fanctld.plist"
PLIST_DST="/Library/LaunchDaemons/io.github.jbforge.fanctld.plist"
INSTALL_PATH="/usr/local/libexec/fanctld"
LABEL="io.github.jbforge.fanctld"

if [[ ! -x "$BINARY" ]]; then
    echo "error: $BINARY not found — run 'make release' first" >&2
    exit 1
fi

echo "Stopping existing daemon (if any)..."
launchctl bootout system/"$LABEL" 2>/dev/null || true
# bootout is asynchronous — wait for the job to fully disappear before
# replacing the binary and re-bootstrapping.
for _ in $(seq 1 50); do
    launchctl print system/"$LABEL" >/dev/null 2>&1 || break
    sleep 0.2
done

echo "Installing $INSTALL_PATH"
mkdir -p /usr/local/libexec
install -m 755 -o root -g wheel "$BINARY" "$INSTALL_PATH"

echo "Installing $PLIST_DST"
install -m 644 -o root -g wheel "$PLIST_SRC" "$PLIST_DST"

echo "Starting daemon..."
launchctl bootstrap system "$PLIST_DST"

sleep 1
if launchctl print system/"$LABEL" >/dev/null 2>&1; then
    echo "fanctld installed and running. Log: /Library/Logs/fanctld.log"
else
    echo "warning: daemon did not stay running — check /Library/Logs/fanctld.log" >&2
    exit 1
fi
