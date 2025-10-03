# CredKit - Secure Bash Password Manager

A minimalist, security-focused password manager built entirely with bash scripts and standard Linux utilities. 

The goal is to be able to securely edit your passwords file as a text file. As well as to offer a password-picker utility that lets you pick a password to be put in your clipboard, without your password ever being diaplayed on your screen. 

CredKit is your lightweight toolkit for managing credentials securely on any Linux system. The goal is that by using only these core operating system tools that the number of attack vectors for breaking into your passwords file is significantly reduced compared to using any other piece of software. 

## Why CredKit?

### Security Through Simplicity

CredKit is designed around a core security principle: minimize the attack surface. No web interfaces, no databases, no network calls—just two bash scripts (`edit-pass.sh`, and `choose-pass.sh`) that use trusted Linux tools:

- GPG for encryption/decryption
- xclip for clipboard management
- nano for secure text editing
- ramfs for in-memory file operations

Key advantages:

- No network connectivity: passwords never leave your machine
- Minimal code: fewer potential vulnerabilities
- Standard tools only: well-tested, widely-audited utilities
- No persistent cleartext: never stores decrypted data on disk
- Memory-only editing: edits happen entirely in RAM
- Automatic backups: timestamped encrypted backups before each edit

## How It Works

Passwords live in a GPG-encrypted markdown file (`creds.md.gpg`). Retrieval decrypts directly into memory (no temp files). Editing uses a ramfs so cleartext lives only in RAM while you edit, then re-encrypts.

## Scripts Overview

### choose-pass.sh — Password Retrieval
Daily-use script: search and copy credentials to your clipboard.

Features:
- Search by service name (i.e. website)
- Prompts to install xclip on Debian/Ubuntu; on other distros, install manually
- Copies service, username, and password sequentially to clipboard
- Memory-only decryption (no decrypted temp files)
- Clipboard auto-clearing: cleared on exit and again after 10 seconds

### edit-pass.sh — Password Management
Convenience wrapper that calls the secure editor.

### edit.sh — (called indirectly, not run by directly users)
Core editing with maximum security:
- Mounts a ramfs (in-memory filesystem) for editing
- Creates automatic timestamped backups (encrypted)
- Cleans up memory after editing
- Opens with nano editor (no temp files created)

## Getting Started

Prerequisites:
- Linux system with bash
- GPG installed
- nano text editor (usually pre-installed on Linux)

Installation:
1) Clone the repo
2) Create your initial `creds.md` in the format below
3) Encrypt it: `gpg -c creds.md`
4) Remove the cleartext: `rm creds.md`
5) Make scripts executable: `chmod +x *.sh`

### Password File Format Example

File: `creds.md`

```markdown
# Personal Accounts
>Facebook, john.doe@example.com, myFacebookPassword123
>Gmail, john.doe@gmail.com, SecureGmailPass456

# Work Accounts
>Office 365, john.doe@company.com, WorkEmailPass321
>GitHub, johndoe, GitHubDevPass987

# Banking
>Bank of Example, johndoe123, BankingSecure2023
```

Format rules:
- Credential lines start with `>`
- Exactly three fields separated by commas: `>Service Name, username, password`
- Section headers with `#` are optional
- Any lines not starting with `>` are simply ignored by the pass word picker script (`choose-pass.sh`)

## Usage

### Editing passwords:
```bash
./edit-pass.sh
```
- Enter your GPG password when prompted
- Edit in nano (use Ctrl+X to save and exit)
- File is automatically re-encrypted and cleaned up

### Retrieving passwords:
```bash
./choose-pass.sh
```
- Enter a search term (or leave blank to show all)
- Select an entry
- Service name, username, and password will be copied to the clipboard sequentially

## Security Considerations
# CredKit — Minimal Bash Password Manager

A tiny, security-focused password manager that uses three bash scripts and standard Linux tools.

- No accounts, no sync, no network
- Everything stays on your machine
- Decrypts only in memory; edits happen in RAM

[Developer Notes (technical details)](./developer_notes.md)

## Compatibility & Requirements

**Linux Distribution Support:**
CredKit works on all major Linux distributions including:
- **Debian-based**: Ubuntu, Debian, Linux Mint, Pop!_OS, etc. (with xclip install prompt)
- **Red Hat-based**: RHEL, CentOS, Fedora, Rocky Linux, etc. (manual xclip install)
- **Arch-based**: Arch Linux, Manjaro, EndeavourOS, etc. (manual xclip install)
- **SUSE**: openSUSE, SLES (manual xclip install)
- **Other**: Alpine, Void, Gentoo, etc. (manual xclip install)

**What you need:**
- Any Linux distribution with bash
- GPG (GNU Privacy Guard)
- nano text editor (usually pre-installed)
- xclip clipboard utility:
  - Debian/Ubuntu: User-prompted automatic installation
  - Other distros: Manual installation required

## Quick start
1) Clone the repo and make scripts executable:
```bash
chmod +x *.sh
```
2) Create your data directory and credential file:
```bash
# Create data directory (separate from script directory)
mkdir -p ~/my-passwords

# Create creds.md following the format below in your data directory
# (see Password file format section)

# Encrypt the initial cleartext `creds.md` in the data directory. 
# gpg automatically defauts to name `creds.md.gpg` as output file, 
# and then we remove the cleartext and will never need to store cleartext again.
cd ~/my-passwords
gpg -c creds.md && rm creds.md
```
3) Use the scripts with your data directory:
```bash
# From the CredKit directory
./choose-pass.sh ~/my-passwords
./edit-pass.sh ~/my-passwords
```

## Use it

**IMPORTANT**: All scripts now require a data folder argument to separate your credential data from the script files.

Retrieve credentials:
```bash
./choose-pass.sh /path/to/your/data
```
- Searches credentials in `/path/to/your/data/creds.md.gpg`
- Search, select, and the script will copy service → username → password to clipboard
- Clipboard is cleared on exit and again after 10 seconds

Edit credentials:
```bash
./edit-pass.sh /path/to/your/data
```
- Edits credentials in `/path/to/your/data/creds.md.gpg`
- Opens a secure editor session in RAM; saves re-encrypt back to `creds.md.gpg`

