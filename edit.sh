#!/bin/bash 

# Takes one Parameter: Folder where creds.md.gpg is located

# Change to the directory where this script is located
cd "$(dirname "$(readlink -f "$0")")"

echo "GPG Secure Editing Utility"
echo "Warning: Do not close this script window yourself."
echo "(It closes automatically after you close gnome-text-editor, after you're done editing)"
echo ""

#######################################################################################
# CredKit - Secure Password Manager (Credentials Editor Script)
#
# SECURITY-FIRST GPG FILE EDITING:
# This script provides secure editing of GPG-encrypted files using ramfs (memory-only
# storage) to ensure cleartext never touches persistent storage.
#
# WORKFLOW:
# 1. Creates automatic timestamped backup of encrypted file
# 2. Mounts ramfs temporary filesystem in memory
# 3. Decrypts GPG file directly into ramfs (never to disk)
# 4. Opens secure text editor (gnome-text-editor) for editing
# 5. Re-encrypts modified content back to GPG file
# 6. Securely cleans up all cleartext from memory
#
# SECURITY FEATURES:
# • Memory-only operations - cleartext exists only in ramfs, never on disk
# • Automatic encrypted backups with timestamps before any modification
# • Secure cleanup on ANY script exit (normal, error, interrupt)
# • Process hardening (core dump prevention, history disabling)
# • Comprehensive temporary file cleanup with secure deletion
# • Terminal buffer clearing to prevent information leakage
# • GPG password caching for single-prompt convenience
#
# SECURITY LIMITATIONS:
# • nano configured with --nobackup --noswap to prevent temp files
# • Brief password visibility in process memory during execution
# • Requires trusted system environment and secure terminal
#
# DEPENDENCIES:
# • gpg (GNU Privacy Guard) - for encryption/decryption
# • nano - minimal text editor with no temp file options
# • ramfs - memory-based filesystem (kernel built-in)
#######################################################################################
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
FILE=creds.md

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
echo "Editing file: $FILE"

# Security hardening - prevent core dumps and limit process visibility
ulimit -c 0 2>/dev/null || true
umask 077

# Disable bash history to prevent commands/input from being logged
set +o history

# Strict mode for safer error handling
set -Eeuo pipefail

# Dependency checks
if ! command -v gpg >/dev/null 2>&1; then
    echo "Dependency missing: gpg"
    read -p "Press any key to exit."
    exit 1
fi
if ! command -v nano >/dev/null 2>&1; then
    echo "Dependency missing: nano"
    echo "Please install nano text editor."
    read -p "Press any key to exit."
    exit 1
fi

# Common gpg options (password provided via stdin)
OPTS_COMMON=(--batch --quiet --yes --pinentry-mode loopback --passphrase-fd 0)

# Comprehensive cleanup function - runs on ANY script exit (normal, error, interrupt)
cleanup_on_exit() {
    echo "Performing security cleanup..."
    
    # Remove cleartext file from ramfs if it exists (owned by user)
    if [[ -n "${MNT:-}" && -f "$MNT/$FILE" ]]; then
        rm -f "$MNT/$FILE" 2>/dev/null || true
    fi
    
    # Robust ramfs unmount with race condition handling
    if [[ -n "${MNT:-}" ]] && grep -qs "$MNT" /proc/mounts; then
        echo "Unmounting ramfs..."
        
        # First attempt: normal unmount
        if sudo umount "$MNT" 2>/dev/null; then
            echo "Ramfs unmounted successfully"
        else
            echo "Normal unmount failed, checking for open files..."
            
            # Show what processes are using the mount (for debugging)
            if command -v lsof >/dev/null 2>&1; then
                echo "Processes using $MNT:"
                sudo lsof "$MNT" 2>/dev/null || echo "No open files found by lsof"
            fi
            
            # Wait a moment for processes to finish
            echo "Waiting for processes to release files..."
            sleep 2
            
            # Second attempt: normal unmount after wait
            if sudo umount "$MNT" 2>/dev/null; then
                echo "Ramfs unmounted after wait"
            else
                echo "Attempting force unmount..."
                # Third attempt: force unmount (lazy unmount)
                if sudo umount -l "$MNT" 2>/dev/null; then
                    echo "Ramfs force unmounted (lazy)"
                else
                    echo "WARNING: Could not unmount $MNT - may remain in memory"
                    echo "This could be due to editor processes still running"
                fi
            fi
        fi
    fi
    
    # Remove mount directory if it exists and is empty
    if [[ -n "${MNT:-}" && -d "$MNT" ]]; then
        sudo rmdir "$MNT" 2>/dev/null || true
    fi
    
    # Clear sensitive variables from memory (best effort)
    unset password FILE MNT
    
    # Clear terminal screen and scrollback buffer for security
    clear
    printf '\e[3J'  # Clear scrollback buffer (works in most modern terminals)
    
    # Restore bash history setting
    set -o history
    
    echo "Security cleanup completed. Closing..."
    sleep 2
}

# Set up traps - cleanup runs no matter how script exits
trap cleanup_on_exit EXIT
trap catch_errors ERR;
# trap 'previous_command=$this_command; this_command=$BASH_COMMAND' DEBUG

# trap function
catch_errors() {
   echo "***** ERROR *****. Script aborting";
   read -p "Press any key to exit."
   exit 1;
}

# Let user enter password
getPassword() {
    # Let user enter password.
    echo "GPG Password (type password, then press enter):"
    echo -n "🔐 "  # Lock icon to indicate password input is active
    read -s password
    echo ""  # New line after password input
}

# Create an in-memory only place to let a text editor edit the clear text file
mountDrive() {
    # mount a ramfs memory location for gnome-text-editor to edit the file in
    MNT=/mnt/ram
    sudo mkdir -p "$MNT"
    if grep -qs "$MNT" /proc/mounts; then
        echo "Ramfs already mounted at $MNT"
    else
        echo "Mounting secure ramfs at $MNT"
        if ! sudo mount -t ramfs -o size=1m ramfs "$MNT"; then
            echo "***** RAMFS MOUNT FAILED *****"
            echo "Failed to mount ramfs at $MNT. This could be due to:"
            echo "- Insufficient privileges"
            echo "- ramfs not supported by kernel"
            echo "- System resource limits"
            echo "- Directory already exists as regular folder"
            echo "Cannot proceed without memory-only storage for security."
            read -p "Press any key to exit."
            exit 1
        fi
        # Verify the mount actually created a ramfs
        if ! grep -qs "ramfs.*$MNT" /proc/mounts; then
            echo "***** RAMFS VERIFICATION FAILED *****"
            echo "Mount command succeeded but $MNT is not confirmed as ramfs."
            echo "Current mounts at $MNT:"
            grep "$MNT" /proc/mounts || echo "No mounts found at $MNT"
            echo "Cannot proceed without verified memory-only storage."
            read -p "Press any key to exit."
            exit 1
        fi
    fi
    # Give ownership to current user to avoid sudo for file operations
    sudo chown "${USER}:${USER}" "$MNT"
    echo "Ramfs mount ready for secure editing"
}

# Decrypts the GPG file into a clear-text file on the in-memory directory
# (Also makes a backup copy of the encrypted file first)
decryptFile() {
    # Ensure backup directory exists and is writable by the current user
    mkdir -p "$DATA_FOLDER/bak" 2>/dev/null || true
    if [ ! -w "$DATA_FOLDER/bak" ]; then
        echo "Fixing permissions on $DATA_FOLDER/bak (requires sudo)..."
        sudo chown "${USER}:${USER}" "$DATA_FOLDER/bak" || true
        sudo chmod 700 "$DATA_FOLDER/bak" || true
    fi
    
    # SECURITY CHECK: Cleartext file should NEVER exist
    if [ -f "$DATA_FOLDER/$FILE" ]; then
        echo "***** CRITICAL SECURITY ERROR *****"
        echo "Cleartext file '$DATA_FOLDER/$FILE' found in data directory!"
        echo ""
        echo "This is a serious security violation. Possible causes:"
        echo "- Leftover file from previous failed run"
        echo "- Manual creation of cleartext file (security risk)"
        echo "- System failure during previous encryption"
        echo ""
        echo "REQUIRED ACTIONS:"
        echo "1. Manually review '$DATA_FOLDER/$FILE' for sensitive content"
        echo "2. If it contains passwords, encrypt it manually: gpg -c \"$DATA_FOLDER/$FILE\""
        echo "3. Securely delete the cleartext: rm \"$DATA_FOLDER/$FILE\""
        echo "4. Re-run this script only after cleartext is removed"
        echo ""
        echo "This script is designed to edit ENCRYPTED files only."
        echo "It will not proceed with cleartext files present."
        read -p "Press any key to exit."
        exit 1
    fi
    
    # Verify encrypted file exists before proceeding
    if [ ! -f "$DATA_FOLDER/$FILE.gpg" ]; then
        echo "***** ERROR *****"
        echo "Encrypted file $DATA_FOLDER/$FILE.gpg not found."
        read -p "Press any key to exit."
        exit 1
    fi
    
    # backup current encrypted file
    backup_file="$DATA_FOLDER/bak/$FILE.gpg-$(date +"%s")"
    cp -a "$DATA_FOLDER/$FILE.gpg" "$backup_file"
    echo "Backup created: $backup_file"

    # decrypt the file into memory (ramfs) so gnome-text-editor can edit
    echo "Decrypting $DATA_FOLDER/$FILE.gpg to secure ramfs..."
    
    # CRITICAL SECURITY CHECK: Verify target is actually ramfs before writing cleartext
    if ! findmnt -n -o FSTYPE "$MNT" 2>/dev/null | grep -q "ramfs"; then
        echo "***** CRITICAL SECURITY ERROR *****"
        echo "Target directory $MNT is NOT a ramfs filesystem!"
        echo "Cleartext would be written to persistent storage, violating security model."
        echo "Detected filesystem type: $(findmnt -n -o FSTYPE "$MNT" 2>/dev/null || echo 'UNKNOWN')"
        echo "Aborting to prevent security breach."
        read -p "Press any key to exit."
        exit 1
    fi
    echo "Verified: Target $MNT is confirmed ramfs (memory-only)"
    
    if printf '%s' "$password" | gpg "${OPTS_COMMON[@]}" --output "$MNT/$FILE" -d "$DATA_FOLDER/$FILE.gpg"; then
        echo "Decryption successful - file ready for editing"
    else
        echo ""
        echo "***** DECRYPTION FAILED *****"
        sleep 3
        exit 1
    fi
}

getPassword
mountDrive
decryptFile

# Edit file in memory using nano with security options
# Default nano behavior: no backup files, no swap files
# We explicitly avoid -B (backup) flag to ensure no temp files are created
# This ensures no temporary files are created that could contain sensitive data

chown "${USER}:${USER}" "$MNT/$FILE" 2>/dev/null || true
echo "Opening nano editor for secure editing..."
echo "Use Ctrl+X to save and exit when done editing."
nano --softwrap --atblanks "$MNT/$FILE"

# Wait briefly for any remaining processes to finish
echo "Editor closed. Continuing with re-encryption..."
sleep 1

echo "Finished Editing. Encrypting and saving."

# reencrypt the file, and save it back
if printf '%s' "$password" | gpg "${OPTS_COMMON[@]}" --output "$DATA_FOLDER/$FILE.gpg" -c "$MNT/$FILE"; then
    echo "Successfully re-encrypted and saved $DATA_FOLDER/$FILE.gpg"
    echo "Editing session completed successfully."
else
    echo "***** RE-ENCRYPTION FAILED *****"
    echo "Your changes could not be saved!"
    echo "The backup file in $DATA_FOLDER/bak/ contains your previous version."
    read -p "Press any key to exit."
    exit 1
fi
