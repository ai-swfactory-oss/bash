#!/usr/bin/env bash
# Named test: scripts/fetch.sh, which the build runs before it extracts,
# patches, compiles or publishes anything, refuses
#   - a source signed by a key other than the pinned fingerprint,
#   - a source whose content no longer matches its signature (tampered),
#   - a source with no signature file,
#   - a manifest whose patch count disagrees with its patchlevel,
# deleting the refused file each time, and accepts the same sources with good
# signatures by the pinned key, so the checks are not vacuous. Runs offline:
# the "mirror" is local files, signed with throwaway keys generated here.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
command -v gpg >/dev/null 2>&1 || { echo "signature-mismatch: gpg is not on PATH" >&2; exit 1; }
command -v gpgconf >/dev/null 2>&1 || { echo "signature-mismatch: gpgconf is not on PATH" >&2; exit 1; }

work=$(mktemp -d)
# Generating and signing with the throwaway keys starts a gpg-agent, whose
# socket lives in GNUPGHOME: keep that path short (macOS limits a socket path
# to 104 bytes, and $TMPDIR there is long), and stop the agent on exit.
GNUPGHOME=$(mktemp -d /tmp/gpg.XXXXXX)
export GNUPGHOME
chmod 700 "$GNUPGHOME"
trap 'gpgconf --homedir "$GNUPGHOME" --kill gpg-agent >/dev/null 2>&1 || true; rm -rf "$GNUPGHOME" "$work"' EXIT

# Two throwaway keys: "good" (pinned) and "other" (not pinned).
gpg --batch --quiet --passphrase '' --quick-gen-key 'good <good@example.invalid>' ed25519 sign never
gpg --batch --quiet --passphrase '' --quick-gen-key 'other <other@example.invalid>' ed25519 sign never
good=$(gpg --batch --with-colons --list-keys good@example.invalid | awk -F: '$1 == "fpr" { print $10; exit }')
gpg --batch --armor --export good@example.invalid >"$work/good.asc"

sign() { # <key> <file>
  gpg --batch --quiet --yes --local-user "$1@example.invalid" --detach-sign -o "$2.sig" "$2"
}

mkdir -p "$work/mirror/bash-9.9-patches" "$work/srcdir/bash-9.9"
printf 'fake\n' >"$work/srcdir/bash-9.9/README"
tar -czf "$work/mirror/bash-9.9.tar.gz" -C "$work/srcdir" bash-9.9
printf 'fake patch\n' >"$work/mirror/bash-9.9-patches/bash99-001"
sign good "$work/mirror/bash-9.9.tar.gz"

manifest() { # <patchlevel>
  jq -n --argjson l "$1" --arg k "$good" '{
    version: "9.9", patchlevel: $l, repack: 0, signing_key: $k,
    sources: [{path: "bash-9.9.tar.gz"}, {path: "bash-9.9-patches/bash99-001"}]
  }' >"$work/manifest.json"
}

expect_refusal() { # <case> <log pattern> [file that must be gone]
  set +e
  # fetch.sh verifies with gpgv against a keyring built from the key file given
  # here alone, so it trusts nothing in this GNUPGHOME.
  UPSTREAM_JSON="$work/manifest.json" UPSTREAM_BASE_URL="file://$work/mirror" UPSTREAM_KEY_FILE="$work/good.asc" \
    bash "$root/scripts/fetch.sh" "$work/out-$1" >"$work/$1.log" 2>&1
  local rc=$?
  set -e
  cat "$work/$1.log"
  [ "$rc" -ne 0 ] || { echo "signature-mismatch: $1: fetch accepted it" >&2; exit 1; }
  grep -q "$2" "$work/$1.log" || { echo "signature-mismatch: $1: the failure does not say '$2'" >&2; exit 1; }
  if [ -n "${3:-}" ] && [ -e "$work/out-$1/src/$3" ]; then
    echo "signature-mismatch: $1: $3 was left behind" >&2; exit 1
  fi
}

manifest 1
sign other "$work/mirror/bash-9.9-patches/bash99-001"
expect_refusal wrongkey 'signature check failed for bash-9.9-patches/bash99-001' bash99-001

sign good "$work/mirror/bash-9.9-patches/bash99-001"
printf 'tampered after signing\n' >>"$work/mirror/bash-9.9-patches/bash99-001"
expect_refusal tampered 'signature check failed for bash-9.9-patches/bash99-001' bash99-001

printf 'fake patch\n' >"$work/mirror/bash-9.9-patches/bash99-001"
rm -f "$work/mirror/bash-9.9-patches/bash99-001.sig"
expect_refusal nosig 'no signature for bash-9.9-patches/bash99-001' bash99-001

sign good "$work/mirror/bash-9.9-patches/bash99-001"
manifest 2
expect_refusal count '1 patches listed, patchlevel says 2'

manifest 1
UPSTREAM_JSON="$work/manifest.json" UPSTREAM_BASE_URL="file://$work/mirror" UPSTREAM_KEY_FILE="$work/good.asc" \
  bash "$root/scripts/fetch.sh" "$work/out-good"
cmp "$work/mirror/bash-9.9-patches/bash99-001" "$work/out-good/src/bash99-001"
grep -q ' bash99-001$' "$work/out-good/src/SOURCE-SHA256SUMS"

echo "signature-mismatch: OK"
