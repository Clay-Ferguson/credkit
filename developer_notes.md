# CredKit Developer Notes
 
This document captures the technical and security design details of CredKit, for developers.

## Architecture Overview

CredKit consists of three bash scripts using only standard Linux utilities:
- choose-pass.sh — daily credential retrieval
- edit-pass.sh — wrapper to start secure editing
- edit.sh — secure editor executing edits entirely in RAM

**Data Folder Architecture**: All scripts require a data folder argument to separate credential data from script files. The credential file (`creds.md.gpg`) must be located in the specified data directory, not in the script directory. This enables safe version control of scripts while keeping sensitive data separate.

Key tools:
- GPG for encryption/decryption
- xclip for clipboard
- nano for secure text editing
- ramfs for in-memory filesystem

No additional dependencies; no network features; no databases.

## Platform Compatibility

CredKit is designed for universal Linux compatibility using only POSIX-compliant utilities and standard Linux tools. All major Linux distributions are supported:

**Fully Compatible Distributions:**
- Debian-based: Ubuntu, Debian, Linux Mint, Pop!_OS, Elementary OS, etc.
- Red Hat-based: RHEL, CentOS, Fedora, Rocky Linux, AlmaLinux, etc.
- Arch-based: Arch Linux, Manjaro, EndeavourOS, Artix Linux, etc.
- SUSE-based: openSUSE Leap/Tumbleweed, SLES
- Independent: Alpine Linux, Void Linux, Gentoo, Slackware, etc.

**Distribution-Specific Features:**
- Debian/Ubuntu systems: Convenience prompt for automatic xclip installation
- All other systems: Manual xclip installation with clear instructions provided

**Core Dependencies (universally available):**
- bash shell (standard on all Linux)
- gpg (GNU Privacy Guard) - encryption/decryption
- nano text editor - secure editing (usually pre-installed)
- ramfs filesystem - memory-only storage (kernel feature)
- Standard utilities: sudo, mount, umount, grep, etc.

## Security Model & Guarantees

- Memory-only handling of secrets:
  - Retrieval: decrypt directly into process memory; no decrypted temp files
  - Editing: decrypt/edit in ramfs; re-encrypt on save and remove plaintext
- No persistent cleartext on disk
- Backups are encrypted (timestamped copies of `*.gpg`)
- Defense-in-depth: strict mode, traps, history disabled, terminal scrollback cleared

## Implementation Details

### Strict Mode and Hardening
- `set -Eeuo pipefail` ensures failures abort the script and run cleanup
- `ulimit -c 0` disables core dumps; `umask 077` restricts default perms
- History disabled during execution via `set +o history`, restored on exit

### Clipboard Safety (choose-pass.sh)
- Clipboard is cleared on exit, and again after 10 seconds (hardcoded)
- Copying uses `printf %s | xclip` (avoids `echo` pitfalls)

### GPG Usage
- Loopback pinentry with passphrase via stdin:
  - `--pinentry-mode loopback --passphrase-fd 0`
  - Avoids exposing passphrase in argv or env, and avoids `sudo` for gpg
- Fallback to interactive pinentry if loopback fails (edit.sh)
- Non-interactive flags: `--batch --quiet --yes`

### Ramfs Editing (edit.sh)
- Mount: `sudo mount -t ramfs -o size=1m ramfs /mnt/ram`
- Ownership: mount directory chowned to current user to avoid `sudo` for file ops
- Editing: `nano /mnt/ram/<file>` blocks until closed (no temp files created)
- Cleanup on exit (EXIT trap):
  - Delete plaintext file from ramfs
  - Unmount ramfs and remove the mount directory
  - Clear sensitive variables
  - Clear screen and scrollback buffer

### Backups
- Prior to edits, copy `<file>.gpg` to `$DATA_FOLDER/bak/<file>.gpg-<epoch>`
- Backups remain encrypted

### Input Validation (choose-pass.sh)
- Only credential lines beginning with `>` are processed
- Each credential line must contain exactly two commas (three fields)
- Section headers starting with `#` are ignored

### Dependency Handling
- Retrieval: prompts to install `xclip` on Debian/Ubuntu; otherwise instructs user
- Editor: checks presence of `gpg` and `nano` and exits with guidance if missing

## Edge Cases & Error Handling
- Wrong GPG passphrase: clear message and abort; cleanup still runs
- Empty decrypted file: abort with message to avoid silent data loss
- Invalid credential format: abort with line number and redacted message
- Selection input validated (numeric range or quit)

## Operational Notes
- Use on trusted systems only; secrets exist in process memory while running
- Consider adjusting ramfs size (`size=1m`) if your file grows
- `choose-pass.sh` preserves leading/trailing spaces in passwords

## Development Guidelines
- Bash-only; standard Linux tools only
- No network features, databases, or complex frameworks
- Keep scripts minimal and readable
- Test: decrypt → edit → save → re-encrypt; verify backups and cleanup

## Future Improvements (optional)
- Configurable clipboard timeout (currently hardcoded at 10s)
- Editor selection via env var
- Additional health checks (available disk space for backups)

## Threat model

This section clarifies what CredKit aims to protect and against whom.

### Assets
- Encrypted credential store (`creds.md.gpg`)
- Decrypted credentials in memory during use
- Clipboard contents during retrieval
- Backups of the encrypted store in `$DATA_FOLDER/bak/`

### Trusted computing base (TCB) & assumptions
- The host OS, kernel, and hardware are trusted and uncompromised
- The user’s account and sudo password are not known to attackers
- GPG is properly installed and not tampered with
- Local terminal is trusted (no hostile logging beyond typical scrollback)
- No untrusted users with root access on the same machine

### Attacker capabilities considered
- Casual/local user-level compromise after the fact (e.g., reading leftover files)
- Accidental leakage via shell history or terminal scrollback
- Application crashes or interrupts during operation
- Clipboard snooping after workflow finishes

### Out of scope (not fully mitigated)
- Active malware with root privileges (can read memory, tamper with gpg, intercept keystrokes)
- Physical attacks while the session is unlocked (shoulder surfing, cameras, live RAM extraction)
- Keyloggers or hostile terminal multiplexers
- Compromise of the user’s GPG passphrase outside of CredKit (phishing, reuse)
- Clipboard access by other processes during the active session window

### Mitigations in CredKit
- No decrypted temp files: retrieval decrypts directly into memory; editing occurs in ramfs
- Cleanup on exit: plaintext files deleted; ramfs unmounted; scrollback cleared; variables unset
- Strict mode and traps: failures abort reliably and run cleanup
- Encrypted backups only, with timestamps
- Clipboard cleared on exit and again after 10 seconds
- GPG passphrase provided via stdin with loopback pinentry (avoids argv/env exposure)

### Residual risks
- Secrets exist in process memory while running (Bash/GPG/nano processes)
- Clipboard may be read by other processes during the 10s window
- nano does not create temp files by default, eliminating this attack vector
- If the host is compromised (especially with root), memory scraping and input interception are possible

### Operational guidance
- Use only on trusted machines; keep OS and GPG updated
- Lock your screen if stepping away; close sessions promptly
- Prefer isolated terminals; avoid logging terminals or remote sessions when possible
- Keep strong, unique GPG passphrases and back up the encrypted store and the `$DATA_FOLDER/bak/` folder safely
