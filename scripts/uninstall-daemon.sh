#!/bin/bash
# Removes the fanctld LaunchDaemon and restores automatic fan control.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "error: must run as root (use: make uninstall)" >&2
    exit 1
fi

LABEL="io.github.jbforge.fanctld"

echo "Stopping daemon (fans return to automatic control on shutdown)..."
launchctl bootout system/"$LABEL" 2>/dev/null || true

rm -f "/Library/LaunchDaemons/$LABEL.plist"
rm -f /usr/local/libexec/fanctld
rm -f /var/run/fanctld.sock
rm -rf "/Library/Application Support/fanctld"

echo "fanctld uninstalled."
