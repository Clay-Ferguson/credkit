#!/bin/bash

# Change to the directory where this script is located
cd "$(dirname "$(readlink -f "$0")")"

#######################################################################################
# CredKit - Secure Password Manager (Credentials editing Convenience Wrapper)
#
# SECURITY-FIRST CREDENTIAL EDITING:
# Simple wrapper that calls edit.sh to edit the main credential store (creds.md.gpg).
# Inherits all security features from the underlying edit.sh script.
#
# SECURITY FEATURES (inherited from edit.sh):
# • Memory-only editing via ramfs - no cleartext ever touches disk
# • Automatic encrypted backups before any modification
# • Secure cleanup on any exit condition
# • Process hardening and terminal buffer clearing
# • GPG error handling with clear user feedback
#
# USAGE:
# This is the primary way to edit your password store. Simply run:
#   ./edit-pass.sh
#
# The script will prompt for your GPG password and open the credential file
# in a secure text editor for modification.
#######################################################################################

# Security hardening - prevent core dumps and limit process visibility
ulimit -c 0 2>/dev/null || true
umask 077

# Disable bash history to prevent commands from being logged
set +o history

# Strict mode
set -Eeuo pipefail

# Cleanup function for wrapper
cleanup_wrapper() {
    # Clear any sensitive variables
    unset password
    
    # Clear terminal screen and scrollback buffer for security
    clear
    printf '\e[3J'  # Clear scrollback buffer
    
    # Restore bash history setting
    set -o history
}

# Check command line arguments
if [ $# -ne 1 ]; then
    echo "***** USAGE ERROR *****"
    echo "Usage: $0 <data-folder>"
    echo ""
    echo "Example: $0 /home/user/passwords"
    echo "  This will edit encrypted credentials at: /home/user/passwords/creds.md.gpg"
    echo ""
    echo "The data folder must exist and contain your encrypted credential file (creds.md.gpg)."
    exit 1
fi

DATA_FOLDER="$1"

# Validate data folder exists
if [ ! -d "$DATA_FOLDER" ]; then
    echo "***** DATA FOLDER ERROR *****"
    echo "Data folder does not exist: $DATA_FOLDER"
    echo ""
    echo "Please create the data folder or provide a valid path."
    echo "Example: mkdir -p \"$DATA_FOLDER\""
    exit 1
fi

echo "Using data folder: $DATA_FOLDER"

# Set up cleanup trap
trap cleanup_wrapper EXIT

# Execute the main editing script and check for errors
echo "Starting secure editing session..."
if ./edit.sh "$DATA_FOLDER"; then
    echo "Editing session completed successfully."
    exit 0
else
    edit_exit_code=$?
    echo "***** EDITING FAILED *****"
    echo "The secure editing session encountered an error."
    echo "Edit script returned exit code: $edit_exit_code"
    echo "Check the error messages above for details."
    read -p "Press any key to exit."
    exit "$edit_exit_code"
fi
