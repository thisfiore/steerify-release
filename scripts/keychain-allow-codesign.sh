#!/bin/zsh
# Once per Mac: let codesign (and Apple tools) use the Developer ID key without a password prompt.
# macOS asks "codesign wants to access key … in your keychain" on every signature otherwise,
# and "Always Allow" does not stick for keys imported without codesign in their partition list.
# Run it yourself (it asks for your login password; nothing is stored):
#   scripts/keychain-allow-codesign.sh
set -e
KC=~/Library/Keychains/login.keychain-db
security find-identity -v -p codesigning | grep -q "Developer ID Application" || { echo "no Developer ID Application cert in the login keychain" >&2; exit 1; }
read -rs "PW?Login keychain password: "; echo
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PW" "$KC" >/dev/null
unset PW
echo "done: codesign can use your signing keys without asking"
