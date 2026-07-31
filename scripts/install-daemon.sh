#!/bin/bash
# Installs the fanctld LaunchDaemon. Run via `make install` (invokes sudo).
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "error: must run as root (use: make install)" >&2
    exit 1
fi

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLIST_SRC="$REPO_DIR/Resources/io.github.jbforge.fanctld.plist"
PLIST_DST="/Library/LaunchDaemons/io.github.jbforge.fanctld.plist"
INSTALL_PATH="/usr/local/libexec/fanctld"
LABEL="io.github.jbforge.fanctld"

# Runs both from a repo checkout and from an unpacked release archive, which
# ships prebuilt binaries in bin/ instead of a .build tree. A universal build
# lands somewhere different again from a plain one.
CANDIDATES=(
    "${FANCTLD_BIN:-}"
    "$REPO_DIR/bin/fanctld"
    "$REPO_DIR/.build/apple/Products/Release/fanctld"
    "$REPO_DIR/.build/release/fanctld"
)
BINARY=""
for candidate in "${CANDIDATES[@]}"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
        BINARY="$candidate"
        break
    fi
done

if [[ -z "$BINARY" ]]; then
    echo "error: no fanctld binary found — run 'make release' first. Looked in:" >&2
    for candidate in "${CANDIDATES[@]}"; do
        [[ -n "$candidate" ]] && echo "  $candidate" >&2
    done
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
# `install` carries extended attributes across, and macOS kills a quarantined
# binary on launch — launchd would never get the daemon started. Installing it
# is the point at which the download quarantine stops applying.
xattr -d com.apple.quarantine "$INSTALL_PATH" 2>/dev/null || true

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
