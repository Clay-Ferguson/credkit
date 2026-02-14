#!/bin/bash

# Change to the directory where this script is located
cd "$(dirname "$(readlink -f "$0")")"

#######################################################################################
# CredKit - Desktop Shortcut Installer
#
# Creates and installs a .desktop file so that 'choose-pass.sh' appears in the
# Ubuntu application launcher. The user can then right-click the icon and add it
# to the desktop dock/favorites.
#
# USAGE:
#   ./install-choose-pass.sh <data-folder>
#
# EXAMPLE:
#   ./install-choose-pass.sh ~/my-passwords
#
# The <data-folder> is the path to your credential data directory (the same one
# you pass to choose-pass.sh). It will be baked into the desktop shortcut so the
# app launches with the correct data folder every time.
#######################################################################################

set -Eeuo pipefail
ulimit -c 0 2>/dev/null || true
umask 077
set +o history

SCRIPT_DIR="$(pwd)"
DESKTOP_FILE_NAME="credkit-choose-pass.desktop"
APPLICATIONS_DIR="$HOME/.local/share/applications"

# ── Validate arguments ──────────────────────────────────────────────────────────
if [ $# -ne 1 ]; then
    echo "***** USAGE ERROR *****"
    echo "Usage: $0 <data-folder>"
    echo ""
    echo "Example: $0 /home/user/passwords"
    echo ""
    echo "The <data-folder> is the same path you use when running choose-pass.sh."
    exit 1
fi

DATA_FOLDER="$(readlink -f "$1")"

if [ ! -d "$DATA_FOLDER" ]; then
    echo "***** DATA FOLDER ERROR *****"
    echo "Data folder does not exist: $DATA_FOLDER"
    echo ""
    echo "Please create the data folder or provide a valid path."
    exit 1
fi

# ── Validate required files exist ────────────────────────────────────────────────
if [ ! -f "$SCRIPT_DIR/choose-pass.sh" ]; then
    echo "***** ERROR *****"
    echo "choose-pass.sh not found in: $SCRIPT_DIR"
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/password-icon.png" ]; then
    echo "***** ERROR *****"
    echo "password-icon.png not found in: $SCRIPT_DIR"
    exit 1
fi

# ── Create applications directory if needed ──────────────────────────────────────
mkdir -p "$APPLICATIONS_DIR"

# ── Write the .desktop file ─────────────────────────────────────────────────────
cat > "$APPLICATIONS_DIR/$DESKTOP_FILE_NAME" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=CredKit
Comment=Secure password manager - search and copy credentials
Exec=bash -c 'cd "$SCRIPT_DIR" && ./choose-pass.sh "$DATA_FOLDER"'
Icon=$SCRIPT_DIR/password-icon.png
Terminal=true
Categories=Utility;Security;
StartupNotify=false
EOF

chmod 644 "$APPLICATIONS_DIR/$DESKTOP_FILE_NAME"

# ── Refresh the desktop database so the launcher picks up the new entry ─────────
if command -v update-desktop-database &>/dev/null; then
    update-desktop-database "$APPLICATIONS_DIR" 2>/dev/null || true
fi

echo ""
echo "Desktop shortcut installed successfully."
echo ""
echo "  File:        $APPLICATIONS_DIR/$DESKTOP_FILE_NAME"
echo "  Launches:    $SCRIPT_DIR/choose-pass.sh $DATA_FOLDER"
echo "  Icon:        $SCRIPT_DIR/password-icon.png"
echo ""
echo "You can now find 'CredKit' in your application launcher."
echo "Right-click the icon to add it to your dock/favorites."
