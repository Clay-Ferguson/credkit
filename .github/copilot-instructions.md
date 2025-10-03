# CredKit - AI Coding Agent Instructions

## Project Overview
CredKit is a security-focused bash password manager that prioritizes minimalism over features. The entire system consists of three bash scripts using only standard Linux utilities (GPG, xclip, nano, ramfs). **Never suggest adding dependencies, web interfaces, databases, or complex frameworks** - this goes against the core security philosophy.

**Universal Linux Compatibility**: CredKit works on all major Linux distributions (Debian, Ubuntu, RHEL, Fedora, Arch, SUSE, Alpine, etc.) using only POSIX-compliant utilities and standard Linux tools. Only difference: Debian/Ubuntu get convenience xclip install prompts, others require manual xclip installation.

## Architecture & Security Model
- **Memory-only operations**: Cleartext passwords exist only in ramfs (never on disk)
- **GPG encryption**: All credentials stored in `creds.md.gpg` using symmetric encryption
- **Automatic backups**: Every edit creates timestamped backup in `bak/` directory
- **Single point of entry**: All scripts change to their own directory using `cd "$(dirname "$(readlink -f "$0")")"`

## Core Scripts & Workflows

**Data Folder Requirement**: All scripts now require a data folder argument (e.g., `./choose-pass.sh ~/my-passwords`) to separate credential data from script files. This enables safe version control while keeping sensitive data isolated.

### `choose-pass.sh` - Daily Use Script
- **Usage**: `./choose-pass.sh <data-folder>` - searches `<data-folder>/creds.md.gpg`
- **Primary workflow**: Search → Select → Copy to clipboard sequentially
- **Prompts to install xclip** on Debian/Ubuntu systems only
- **Error handling**: Uses `trap catch_errors ERR` pattern for abort-on-error
- **Memory array loading**: `readarray -t creds <<<"$(gpg_output)"` from captured GPG output
- **Clipboard security**: Auto-clears clipboard on exit and again after 10 seconds

### `edit.sh` - Secure Editor Core
- **Usage**: `./edit.sh <data-folder>` - edits `<data-folder>/creds.md.gpg`
- **Ramfs workflow**: Mount `/mnt/ram` → Decrypt → Edit → Encrypt → Cleanup
- **Password caching**: Single GPG password prompt per session via stdin (`--passphrase-fd 0`)
- **Editor integration**: Uses `nano` text editor for secure, no-temp-file editing
- **Trap-based cleanup**: `trap cleanup_on_exit EXIT` ensures comprehensive memory cleanup
- **Backup creation**: `./bak/$FILE.gpg-$(date +"%s")` before any modification

### `edit-pass.sh` - Convenience Wrapper
- **Usage**: `./edit-pass.sh <data-folder>` - wrapper that calls `edit.sh <data-folder>`
- Simple wrapper that validates data folder and calls the core editor - maintain this pattern for new utilities.

## Critical Patterns & Conventions

### File Format (markdown-based)
```markdown
# Section Headers (optional)
>Service Name, username, password
```
- Credential lines **must** start with `>`
- Exactly two commas (three fields) - validated with `tr -cd ',' | wc -c`
- Sections with `#` headers for organization
- **All fields are trimmed**: Service names, usernames, and passwords have leading/trailing whitespace removed (via `xargs`)

### Security Hardening Pattern (Applied to ALL scripts)
```bash
set -Eeuo pipefail              # Strict mode with error propagation
ulimit -c 0 2>/dev/null || true # Prevent core dumps
umask 077                       # Restrict file permissions
set +o history                  # Disable bash history during execution
```

### Error Handling Pattern
```bash
trap cleanup_on_exit EXIT       # Always runs cleanup
trap catch_errors ERR;
catch_errors() {
   echo "***** ERROR *****. Script aborting";
   read -p "Press any key to exit."
   exit 1;
}
```

### GPG Security Patterns
- **Interactive mode**: `OPTS_COMMON=(--batch --quiet --yes --pinentry-mode loopback --passphrase-fd 0)`
- **Password via stdin**: `printf '%s' "$password" | gpg "${OPTS_COMMON[@]}"`
- **Fallback to interactive**: If loopback fails, retry without `--pinentry-mode`
- **Backup before decrypt**: `cp -a $FILE.gpg "./bak/$FILE.gpg-$(date +"%s")"`

### Memory Security Patterns
- **Ramfs management**: Check mount with `grep -qs "$MNT" /proc/mounts`
- **Secure cleanup**: Clear variables with `unset`, clear terminal with `printf '\e[3J'`
- **File cleanup**: User-owned files with `rm -f`, ramfs with `sudo umount`

## Development Guidelines

### What to Maintain
- Bash-only implementation (no Python, Node.js, etc.)
- Standard Linux utilities only (GPG, xclip, mount, etc.)
- Directory-relative script execution
- Memory-only cleartext handling
- Automatic backup creation

### What Never to Add
- Network connectivity or cloud features
- Complex dependencies or package managers
- Persistent cleartext storage
- Web interfaces or GUI frameworks
- Database systems

### When Modifying Scripts
1. Test the complete workflow: encrypt → decrypt → edit → re-encrypt
2. Verify ramfs cleanup with `mount | grep ramfs`
3. Check backup creation in `bak/` directory
4. Test error conditions (wrong GPG password, missing xclip, etc.)

## Key Files & Structure
- `creds.md.gpg`: The encrypted credential store (never commit cleartext)
- `_creds.md`: Example/template file showing proper format
- `bak/`: Automatic timestamped backups (`creds.md.gpg-<epoch>`)
- `.gitignore`: Prevents ALL credential files (`*.md.gpg`, `*_creds.*`) from commits

## Development & Testing Workflow
1. **Format validation**: Scripts validate exactly 2 commas per credential line
2. **Dependency checks**: User-prompted xclip install (Debian/Ubuntu), manual elsewhere
3. **Complete workflow test**: encrypt → decrypt → edit → re-encrypt → verify backups
4. **Security verification**: `mount | grep ramfs` (should be empty after cleanup)
5. **Error scenarios**: Wrong GPG password, malformed credential lines, missing dependencies

## Architecture Decisions
- **Why ramfs over tmpfs**: Guaranteed memory-only (tmpfs can swap to disk)
- **Why stdin for GPG password**: Avoids argv/environment exposure
- **Why nano**: Secure text editor that creates no temporary files, preventing data leakage  
- **Why immediate backup creation**: Protects against encrypt/decrypt failures during editing
