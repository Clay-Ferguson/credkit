#!/bin/bash

# Change to the directory where this script is located
cd "$(dirname "$(readlink -f "$0")")"

#######################################################################################
# CredKit - Secure Password Manager
#
# SECURITY-FIRST CREDENTIAL RETRIEVAL:
# This script provides secure, searchable access to GPG-encrypted credentials with 
# automatic clipboard integration. Designed for daily password access, securely, even if
# your screen is being shared/observed.
#
# WORKFLOW:
# 1. Prompts to install xclip dependency, if not present (Debian/Ubuntu systems)
# 2. Asks for password and then decrypts GPG encrypted credential file (creds.md.gpg)
# 3. Enters infinite loop for credential retrieval (user closes terminal to exit):
#    a. Prompts for search term to filter stored credentials
#    b. Displays matching entries (without revealing passwords)
#    c. Allows selection of desired credential entry
#    d. Sequentially copies service name, username (if present), and password to clipboard
#    e. Returns to step 3a for next credential lookup
#
# SECURITY FEATURES:
# • Memory-only operations - no cleartext ever written to disk
# • Comprehensive input validation with detailed error reporting
# • Cleanup on ANY script exit (normal, error, interrupt)
# • GPG decryption error handling with clear user feedback
# • Credential file format validation (ensures exactly 2 commas per credential line)
# • Core dump prevention and process hardening
# • Secure memory cleanup of sensitive variables on exit
#
# SECURITY LIMITATIONS:
# • Bash inherently stores variables in process memory - use on trusted systems only
# • Passwords briefly visible in process memory during execution
# • Terminal output could be logged - run in secure terminal only
#
# FILE FORMAT REQUIREMENTS:
# Credential lines must start with '>' and contain exactly 2 commas:
# >Service Name, username, password
# 
# Empty username/password fields are supported. Section headers with '#' are optional.
#
# DEPENDENCIES:
# • gpg (GNU Privacy Guard) - for decryption
# • xclip - for clipboard operations (user-prompted install on Debian/Ubuntu)
#######################################################################################

# Check command line arguments
if [ $# -ne 1 ]; then
    echo "***** USAGE ERROR *****"
    echo "Usage: $0 <data-folder>"
    echo ""
    echo "Example: $0 /home/user/passwords"
    echo "  This will look for encrypted credentials at: /home/user/passwords/creds.md.gpg"
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

# Validate encrypted credential file exists
if [ ! -f "$DATA_FOLDER/$FILE.gpg" ]; then
    echo "***** CREDENTIAL FILE ERROR *****"
    echo "Encrypted credential file not found: $DATA_FOLDER/$FILE.gpg"
    echo ""
    echo "Please ensure your encrypted credential file exists in the data folder."
    echo "If this is your first time, create $FILE in the data folder, then encrypt it:"
    echo "  gpg -c \"$DATA_FOLDER/$FILE\""
    exit 1
fi

echo "Using data folder: $DATA_FOLDER"

# Ensure xclip is available (prompt for installation on Debian/Ubuntu)
REQUIRED_PKG="xclip"
if ! command -v xclip >/dev/null 2>&1; then
    if command -v dpkg-query >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
        echo "Dependency missing: $REQUIRED_PKG (required for clipboard operations)"
        echo "Debian/Ubuntu detected. Would you like to install $REQUIRED_PKG automatically? (y/n)"
        read -r install_choice
        if [[ "$install_choice" == "y" || "$install_choice" == "Y" ]]; then
            echo "Installing $REQUIRED_PKG..."
            sudo apt-get --yes install "$REQUIRED_PKG"
        else
            echo "Installation cancelled. Please install $REQUIRED_PKG manually:"
            echo "  sudo apt-get install $REQUIRED_PKG"
            exit 1
        fi
    else
        echo "Dependency missing: $REQUIRED_PKG"
        echo "Please install it with your package manager (e.g., dnf/pacman)."
        exit 1
    fi
fi

# Ensure gpg is available
if ! command -v gpg >/dev/null 2>&1; then
    echo "Dependency missing: gpg"
    echo "Please install GnuPG (gpg) before using this tool."
    exit 1
fi

# Cleanup function - runs on ANY script exit (normal, error, interrupt)
cleanup_on_exit() {
    # No on-disk decrypted temp files are used; nothing to clean in /tmp
    
    # Clear sensitive arrays from memory (best effort)
    unset creds services usernames passwords filtered_entries
    unset selected_service selected_username selected_password
    unset service user password service_lower
    
    # Clear terminal screen and scrollback buffer for security
    clear
    printf '\e[3J'  # Clear scrollback buffer (works in most modern terminals)
    
    # Always clear clipboard on exit (best-effort)
    printf '' | xclip -selection clipboard 2>/dev/null || true

    # Restore bash history setting
    set -o history
}

# Security hardening - prevent core dumps and limit process visibility
ulimit -c 0 2>/dev/null || true
umask 077

# Disable bash history to prevent commands/input from being logged
set +o history

# Strict mode for safer error handling and to propagate ERR into functions
set -Eeuo pipefail

# Set up traps - cleanup runs no matter how script exits
trap cleanup_on_exit EXIT
trap catch_errors ERR;

# trap function
catch_errors() {
   echo "***** ERROR *****. Script aborting";
    echo "Tip: Check for invalid credential lines (must start with '>' and contain exactly 2 commas)."
   read -p "Press any key to exit."
   exit 1;
}

# Function to decrypt the file with proper error handling (memory-only)
decrypt_file() {
    local gpg_output
    
    # Loop until successful decryption
    while true; do
        echo "Decrypting $DATA_FOLDER/$FILE.gpg..."
        # Capture decrypted contents in-memory to ensure we detect gpg exit status
        if gpg_output=$(gpg -d --no-mdc-warning "$DATA_FOLDER/$FILE.gpg" 2>/dev/null); then
            # Decryption succeeded - populate array from captured output
            readarray -t creds <<<"$gpg_output"
            if [[ ${#creds[@]} -eq 0 ]]; then
                echo "***** WARNING *****"
                echo "Decryption succeeded but the file appears to be empty."
                read -p "Press any key to exit."
                exit 1
            fi
            echo "Decryption successful."
            break
        else
            echo ""
            echo "***** DECRYPTION FAILED *****"
            echo "Wrong password or file is corrupt. Please try again."
            echo "(Press Ctrl+C to exit)"
            echo ""
        fi
    done
}

# decrypt the encrypted file content right into an array in memory.
decrypt_file
clear

# Function to validate credential line format
validate_credential_line() {
    local line="$1"
    local line_number="$2"
    
    # Count commas in the line
    local comma_count=$(echo "$line" | tr -cd ',' | wc -c)
    
    if [ "$comma_count" -ne 2 ]; then
        echo "***** SYNTAX ERROR *****"
        echo "Line $line_number has invalid format: Expected exactly 2 commas, found $comma_count"
        echo "Problematic line: [REDACTED FOR SECURITY - may contain password]"
        echo "Correct format: >Service Name, username, password"
        read -p "Press any key to exit."
        exit 1
    fi
}

# Function to copy text to clipboard
copy_to_clipboard() {
    printf %s "$1" | xclip -selection clipboard
    read -p "In clipboard: $2"
}

# Main loop - keeps running until user closes terminal
while true; do
clear

# Reset arrays and counter for each search iteration
filtered_entries=()
services=()
usernames=()
passwords=()
counter=0

# Ask for search term
echo "Enter search (or Ctrl+C to exit):"
read -r search_term
search_term=$(echo "$search_term" | tr '[:upper:]' '[:lower:]')

# Process the file and find matching entries
line_number=0
for line in "${creds[@]}"; do
    line_number=$((line_number + 1))
    trimmedLine="$(echo -n "$line" | tr -d $'\n' | tr -d $'\r' )"
    
    # Handle section headers (for display purposes only)
    if [[ ${trimmedLine:0:2} == "# " ]]; then
        continue
    fi
    
    # Process credential lines
    if [[ ${line:0:1} == ">" ]]; then
        # Validate the line format before processing
        validate_credential_line "$line" "$line_number"
        
        IFS=',' read -r -a tok <<< "$line"

        # Extract fields; trim all whitespace from usernames and passwords
        service=$(echo -n "${tok[0]}" | tr -d $'\n' | tr -d $'\r')
        service="${service:1}"            # drop leading '>'
        service=$(echo "$service" | xargs) # trim surrounding spaces for display
        user=$(echo -n "${tok[1]}" | tr -d $'\n' | tr -d $'\r' | xargs)
        # Trim whitespace from password as well - spaces in passwords cause issues
        password=$(echo -n "${tok[2]}" | tr -d $'\n' | tr -d $'\r' | xargs)
        
        # Handle if username or password field doesn't exist
        [[ -z "$user" ]] && user="none"
        [[ -z "$password" ]] && continue
        
        # Filter by search term (case insensitive)
        service_lower=$(echo "$service" | tr '[:upper:]' '[:lower:]')
        
        if [[ -z "$search_term" || "$service_lower" == *"$search_term"* ]]; then
            counter=$((counter + 1))
            filtered_entries+=("$counter) $service [$user]")
            services+=("$service")
            usernames+=("$user")
            passwords+=("$password")
        fi
    fi
done

# Display filtered results
if [[ ${#filtered_entries[@]} -eq 0 ]]; then
    echo "No matching entries found."
    echo ""
    continue
fi

# If only one entry found, auto-select it
if [[ ${#filtered_entries[@]} -eq 1 ]]; then
    selection=1
else
    # Display multiple entries and ask for selection
    echo -e "\nMatching entries:"
    for entry in "${filtered_entries[@]}"; do
        echo "$entry"
    done

    # Ask user to select an entry
    echo -e "\nSelect entry:"
    read -r selection
fi

# Validate selection
if [[ "$selection" == "q" || "$selection" == "Q" ]]; then
    echo "Returning to search..."
    echo ""
    continue
fi

if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt ${#filtered_entries[@]} ]; then
    echo "Invalid selection."
    echo ""
    continue
fi

# Get the selected entry (adjust for zero-based indexing)
index=$((selection - 1))
selected_service="${services[$index]}"
selected_username="${usernames[$index]}"
selected_password="${passwords[$index]}"

echo -e "\nSelected: $selected_service"

# Copy each piece of information in sequence
copy_to_clipboard "$selected_service" "Site/Service name"

# Handle username - skip clipboard if blank or "none"
if [[ "$selected_username" == "none" || -z "$selected_username" ]]; then
    echo "Username: (none)"
else
    copy_to_clipboard "$selected_username" "Username"
fi

copy_to_clipboard "$selected_password" "Password"

# Always clear clipboard again after 10 seconds (best-effort)
(
    sleep 10
    printf '' | xclip -selection clipboard 2>/dev/null || true
) &
echo "Clipboard will be cleared again in 10s."

echo -e "\nCredential copied. Ready for next search.\n"

done  # End of main while loop