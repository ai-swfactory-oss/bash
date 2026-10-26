#!/usr/bin/env bash
# The single-quoted node and bash programs are literal on purpose.
# shellcheck disable=SC2016
# Named test, per platform: installs the packed tarballs into a scratch project,
# as a consumer would, and checks that binaryPath() resolves to an executable
# bash that reports upstreamVersion, runs bash 4+ features, and links the way
# the build promises (static on linux: ldd reports it static and readelf -d
# lists no NEEDED entries; system libraries only on darwin).
#
#   scripts/smoke.sh <tgzdir> <platform>      e.g. dist/tgz linux-x64
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
tgz=$(cd "${1:?usage: smoke.sh <tgzdir> <platform>}" && pwd)
platform=${2:?usage: smoke.sh <tgzdir> <platform>}
upstream=$(jq -er '"\(.version).\(.patchlevel)"' "$root/upstream.json")
version=$(bash "$root/scripts/pkgver.sh")

launcher="$tgz/ai-swfactory-oss-bash-$version.tgz"
native="$tgz/ai-swfactory-oss-bash-$platform-$version.tgz"

# Read tarball contents into files first: `tar ... | grep -q` under pipefail
# fails when grep exits early and tar hits the closed pipe.
scan=$(mktemp -d)
for f in "$launcher" "$native"; do
  test -f "$f" || { echo "smoke: missing $f" >&2; exit 1; }
  tar -xzOf "$f" package/package.json >"$scan/package.json"
  if jq -e '.scripts // {} | keys | any(test("install"))' "$scan/package.json" >/dev/null; then
    echo "smoke: $f declares an install script" >&2; exit 1
  fi
  tar -xzOf "$f" package/NOTICE >"$scan/NOTICE"
  grep -q 'Corresponding source' "$scan/NOTICE" || { echo "smoke: $f NOTICE does not point at the corresponding source" >&2; exit 1; }
done

work=$(mktemp -d)
cd "$work" || exit 1
printf '{"name":"smoke","version":"1.0.0","private":true}\n' >package.json
npm install --no-audit --no-fund "$launcher" "$native"

echo "== binaryPath(), upstreamVersion and --version"
node -e '
  const { execFileSync } = require("node:child_process");
  const fs = require("node:fs");
  const bash = require("@ai-swfactory-oss/bash");
  const [expected] = process.argv.slice(1);
  if (bash.upstreamVersion !== expected) throw new Error(`upstreamVersion ${bash.upstreamVersion} != ${expected}`);
  const bin = bash.binaryPath();
  if (!fs.statSync(bin).isFile()) throw new Error(`${bin} is not a file`);
  fs.accessSync(bin, fs.constants.X_OK);
  const printed = execFileSync(bin, ["-c", "echo $BASH_VERSION"], { encoding: "utf8" }).trim();
  if (printed !== `${expected}(1)-release`) throw new Error(`${bin} reports ${printed}, expected ${expected}(1)-release`);
  console.log(bin, printed);
' "$upstream"

bin=$(node -p 'require("@ai-swfactory-oss/bash").binaryPath()')

echo "== bash 4+ features"
got=$("$bin" -c '
  declare -A colour=([sky]=blue [grass]=green)
  mapfile -t lines < <(printf "%s\n" one two three)
  s="it'"'"'s"
  printf "%s|%s|%s|%s\n" "${colour[grass]}" "${#lines[@]}" "${lines[2]}" "${s@Q}"
')
expected="green|3|three|'it'\\''s'"
[ "$got" = "$expected" ] || { echo "smoke: got [$got], expected [$expected]" >&2; exit 1; }
echo "$got"

echo "== linkage"
case "$platform" in
  linux-*)
    # Decide from what ldd prints, not its exit status: for a static-PIE
    # binary (Alpine's default) glibc's ldd prints "statically linked" and
    # exits 0; for a non-PIE static binary it prints "not a dynamic
    # executable" and exits 1.
    ldd "$bin" >ldd.txt 2>&1 || true
    cat ldd.txt
    if ! grep -qE 'statically linked|not a dynamic executable' ldd.txt; then
      echo "smoke: $bin is dynamically linked (ldd lists libraries)" >&2; exit 1
    fi
    readelf -d "$bin" >readelf.txt 2>&1 || true
    if grep -q 'NEEDED' readelf.txt; then
      cat readelf.txt; echo "smoke: $bin has NEEDED entries in its dynamic section" >&2; exit 1
    fi
    echo "readelf -d: no NEEDED entries"
    ;;
  darwin-*)
    otool -L "$bin" >otool.txt
    cat otool.txt
    if tail -n +2 otool.txt | grep -vqE '^[[:space:]]+(/usr/lib/|/System/Library/)'; then
      echo "smoke: $bin loads a library outside the system" >&2; exit 1
    fi
    ;;
esac

echo "smoke: $platform OK"
