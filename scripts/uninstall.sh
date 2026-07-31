#!/bin/bash
# Removes everything install.sh put in place. Fans return to automatic control
# when the daemon stops.
#
# Usage: ./uninstall.sh
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ ! -d "$DIR/scripts" ]]; then
    echo "error: uninstall.sh is the uninstaller shipped inside a release archive." >&2
    echo "In a repo checkout, use: make uninstall" >&2
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
    echo "Removing Fan Control needs administrator rights."
    exec sudo "$0" "$@"
fi

"$DIR/scripts/uninstall-daemon.sh"

rm -rf "/Applications/FanControl.app"
rm -f /usr/local/bin/fanctl

echo "Fan Control removed."
