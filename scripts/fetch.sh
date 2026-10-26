#!/usr/bin/env bash
# Downloads the GNU bash source tarball and every official patch named in
# upstream.json, with their detached GPG signatures, and verifies each file's
# signature against the GNU maintainer key pinned in this repository: the
# fingerprint in upstream.json .signing_key (Chet Ramey), the public key in
# keys/. Nothing is fetched to decide what to trust: the key comes from the
# tree, and a signature counts only when gpgv reports VALIDSIG by exactly that
# fingerprint. Verification uses gpgv against a keyring built from the pinned
# key file alone (gpg --dearmor), so it needs no gpg-agent and no socket. A file whose signature is missing, bad, or by any other key is
# deleted and the script exits 1, so nothing unverified is extracted, patched,
# compiled or published. GNU publishes signatures, not checksums, for bash:
# the signature is the upstream-published integrity check.
#
#   scripts/fetch.sh <outdir>
#
# UPSTREAM_JSON overrides the manifest; UPSTREAM_BASE_URL overrides the GNU
# mirror (default https://ftp.gnu.org/gnu/bash); UPSTREAM_KEY_FILE and
# UPSTREAM_SIGNING_KEY override the key file and fingerprint (the tests sign
# their own fixture files with a throwaway key).
#
# Result: <outdir>/src/<file> and <outdir>/src/<file>.sig for every source,
#         flat (bash-5.3.tar.gz, bash53-001, ...), and
#         <outdir>/src/SOURCE-SHA256SUMS over the verified files (recorded for
#         the release, not trusted).
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
manifest=${UPSTREAM_JSON:-$root/upstream.json}
out=${1:?usage: fetch.sh <outdir>}
base=${UPSTREAM_BASE_URL:-https://ftp.gnu.org/gnu/bash}
key_file=${UPSTREAM_KEY_FILE:-$root/keys/chet-ramey.asc}
fingerprint=${UPSTREAM_SIGNING_KEY:-$(jq -er .signing_key "$manifest")}

[[ "$fingerprint" =~ ^[0-9A-F]{40}$ ]] || { echo "fetch: signing key '$fingerprint' is not a 40-hex fingerprint" >&2; exit 1; }
command -v gpg >/dev/null 2>&1 || { echo "fetch: gpg is not on PATH; every source must be signature-verified" >&2; exit 1; }
command -v gpgv >/dev/null 2>&1 || { echo "fetch: gpgv is not on PATH; every source must be signature-verified" >&2; exit 1; }

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# The patch count must match the patchlevel the package version claims.
patches=$(jq -r '[.sources[] | select(.path | test("/bash[0-9]+-[0-9]{3}$"))] | length' "$manifest")
patchlevel=$(jq -er .patchlevel "$manifest")
[ "$patches" = "$patchlevel" ] || { echo "fetch: $patches patches listed, patchlevel says $patchlevel" >&2; exit 1; }

# The keyring holds only the pinned key file's packets; gpg --dearmor and gpgv
# start no agent.
keys=$(mktemp -d)
trap 'rm -rf "$keys"' EXIT
keyring="$keys/pinned.gpg"
gpg --batch --homedir "$keys" --dearmor --output "$keyring" "$key_file"

mkdir -p "$out/src"
: >"$out/src/SOURCE-SHA256SUMS"
for path in $(jq -r '.sources[].path' "$manifest"); do
  name=$(basename "$path")
  file="$out/src/$name"
  echo "fetch: <- $base/$path"
  curl -fsSL --retry 3 --retry-delay 5 -o "$file" "$base/$path"
  if ! curl -fsSL --retry 3 --retry-delay 5 -o "$file.sig" "$base/$path.sig"; then
    echo "fetch: no signature for $path ($base/$path.sig)" >&2
    rm -f "$file" "$file.sig"
    exit 1
  fi

  status=$(gpgv --homedir "$keys" --status-fd 1 --keyring "$keyring" "$file.sig" "$file" 2>/dev/null || true)
  if ! grep -q "^\[GNUPG:\] VALIDSIG .*$fingerprint" <<<"$status"; then
    echo "fetch: signature check failed for $path (expected a valid signature by $fingerprint)" >&2
    printf '%s\n' "$status" | grep '^\[GNUPG:\]' >&2 || true
    rm -f "$file" "$file.sig"
    exit 1
  fi
  sum=$(sha256 "$file")
  printf '%s  %s\n' "$sum" "$name" >>"$out/src/SOURCE-SHA256SUMS"
  echo "fetch: $path signed by $fingerprint (sha256 $sum)"
done
