#!/bin/bash
# Installs Fan Control from an unpacked release archive:
#   - the fanctld LaunchDaemon (needs root; it writes to the SMC)
#   - FanControl.app in /Applications
#   - the fanctl CLI in /usr/local/bin
#
# Usage: ./install.sh
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

# This script sits at the root of a release archive, next to FanControl.app and
# a scripts/ directory. In a repo checkout it lives inside scripts/ instead, so
# none of the paths below would resolve — say so rather than failing obscurely.
if [[ ! -d "$DIR/scripts" ]]; then
    echo "error: install.sh is the installer shipped inside a release archive." >&2
    echo "In a repo checkout, build and install with: make install" >&2
    exit 1
fi

APP_SRC="$DIR/FanControl.app"
APP_DST="/Applications/FanControl.app"
CLI_SRC="$DIR/bin/fanctl"
CLI_DST="/usr/local/bin/fanctl"

# Check the archive is complete before asking for a password — nobody should be
# prompted for credentials only to be told the download was truncated.
for required in "$APP_SRC" "$CLI_SRC" "$DIR/scripts/install-daemon.sh"; do
    if [[ ! -e "$required" ]]; then
        echo "error: $required is missing — unpack the whole archive first" >&2
        exit 1
    fi
done

# Everything below writes outside the user's home, so re-run under sudo rather
# than failing halfway through with a permission error.
if [[ $EUID -ne 0 ]]; then
    echo "Fan Control needs administrator rights to install its root daemon."
    exec sudo "$0" "$@"
fi

"$DIR/scripts/install-daemon.sh"

echo "Installing $APP_DST"
rm -rf "$APP_DST"
cp -R "$APP_SRC" "$APP_DST"

# The archive arrives from the internet, so macOS quarantines everything in it
# and refuses to launch the app. Clearing that flag here is the point of running
# an installer: the decision to trust this build was made when you ran it.
xattr -dr com.apple.quarantine "$APP_DST" 2>/dev/null || true

echo "Installing $CLI_DST"
mkdir -p "$(dirname "$CLI_DST")"
install -m 755 "$CLI_SRC" "$CLI_DST"
xattr -dr com.apple.quarantine "$CLI_DST" 2>/dev/null || true

echo
echo "Done. Start the menu bar app with:"
echo "  open $APP_DST"
echo
echo "To have it start at login: System Settings → General → Login Items."
echo "To remove everything again: ./uninstall.sh"
