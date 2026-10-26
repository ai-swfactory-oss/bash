#!/usr/bin/env bash
# The repository's validate command (.panoptic.json "validate": "bash scripts/validate.sh"),
# run by `claude-factory work commit` on the gate host. It runs the same path
# the PR CI runs (build.yml), for the gate host's own platform, signature
# checks included:
#
#   1. gpg and gpgv must be on PATH (every source is signature-verified, with
#      gpgv against a keyring built from the pinned key, no agent involved;
#      without them nothing can be trusted, so validate fails naming them);
#   2. shellcheck over every shell script;
#   3. named test test/signature-mismatch.sh: a source signed by another key,
#      a tampered source, a source with no signature and a patch count that
#      disagrees with patchlevel are each refused; good signatures pass;
#   4. scripts/fetch.sh from ftp.gnu.org: every file must carry a GNU
#      signature by the key fingerprint pinned in upstream.json, or it is
#      deleted and validate fails;
#   5. scripts/build.sh natively on the gate host (darwin: bison from
#      `brew --prefix bison`, read only; nothing is installed);
#   6. scripts/stage.sh, then named tests test/launcher.test.js over a launcher
#      staged for all four platforms (the other three binaries are stand-ins:
#      the launcher tests never run them);
#   7. stage for the gate host only, npm pack every package once;
#   8. named test scripts/smoke.sh for the gate host's platform: install the
#      packed tarballs into a scratch project, binaryPath(), $BASH_VERSION,
#      bash 4+ features, linkage, NOTICE, no install script.
#
# The other three platforms' build and smoke run in CI (pr.yml, build.yml).
# Needs network, gpg, gpgv, gpgconf, bash, jq, tar, gzip, curl, patch, make, a C compiler,
# bison (darwin: Homebrew's), node, npm and shellcheck.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
# The gate reports only the exit status; keep the full output for diagnosis.
mkdir -p build
exec > >(tee build/validate.log) 2>&1
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "== gpg"
command -v gpg >/dev/null 2>&1 ||
  { echo "validate: gpg is not on PATH; the GNU signatures cannot be verified, so nothing is built" >&2; exit 1; }
command -v gpgv >/dev/null 2>&1 ||
  { echo "validate: gpgv is not on PATH; the GNU signatures cannot be verified, so nothing is built" >&2; exit 1; }
command -v gpg gpgv
gpg --version >"$work/gpg-version.txt"
sed -n 1p "$work/gpg-version.txt"
gpgv --version >"$work/gpgv-version.txt"
sed -n 1p "$work/gpgv-version.txt"

case "$(uname -s)" in
  Darwin) os=darwin ;;
  Linux) os=linux ;;
  *) echo "validate: unsupported gate host OS $(uname -s)" >&2; exit 1 ;;
esac
case "$(uname -m)" in
  arm64 | aarch64) cpu=arm64 ;;
  x86_64 | amd64) cpu=x64 ;;
  *) echo "validate: unsupported gate host CPU $(uname -m)" >&2; exit 1 ;;
esac
host="$os-$cpu"
jq -e --arg p "$host" '.platforms | index($p) != null' upstream.json >/dev/null ||
  { echo "validate: no bash package is built for the gate host ($host)" >&2; exit 1; }

echo "== shellcheck"
shellcheck scripts/*.sh test/*.sh

echo "== named test: signature mismatch"
bash test/signature-mismatch.sh

echo "== fetch (GNU signatures verified against the pinned key)"
bash scripts/fetch.sh "$work/upstream"
cat "$work/upstream/src/SOURCE-SHA256SUMS"

echo "== build on the gate host ($host)"
mkdir -p "$work/built"
if [ "$os" = darwin ]; then
  command -v brew >/dev/null 2>&1 || { echo "validate: darwin needs Homebrew's bison (brew is not on PATH)" >&2; exit 1; }
  bison_prefix=$(brew --prefix bison)
  [ -x "$bison_prefix/bin/bison" ] || { echo "validate: Homebrew bison is not installed ($bison_prefix)" >&2; exit 1; }
  PATH="$bison_prefix/bin:$PATH" bash scripts/build.sh "$work/upstream" "$work/built/$host"
else
  bash scripts/build.sh "$work/upstream" "$work/built/$host"
fi

echo "== named tests: launcher (staged for every platform)"
mkdir -p "$work/all"
for platform in $(jq -r '.platforms | join(" ")' upstream.json); do
  mkdir -p "$work/all/$platform"
  cp "$work/built/$host/bash" "$work/built/$host/COPYING" "$work/all/$platform/"
done
bash scripts/stage.sh "$work/all" "$work/npm-all"
BASH_LAUNCHER_DIR="$work/npm-all/bash" node --test test/launcher.test.js

echo "== stage for the gate host and pack"
jq --arg p "$host" '.platforms = [$p]' upstream.json >"$work/host.json"
UPSTREAM_JSON="$work/host.json" bash scripts/stage.sh "$work/built" "$work/npm"
mkdir -p "$work/tgz"
for dir in "$work"/npm/*/; do
  npm pack "$dir" --pack-destination "$work/tgz" >/dev/null
done
ls -1 "$work/tgz"

echo "== named test: smoke on the gate host ($host)"
bash scripts/smoke.sh "$work/tgz" "$host"

echo "validate: OK"
