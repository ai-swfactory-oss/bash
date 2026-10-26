#!/usr/bin/env bash
# Builds bash from the verified sources (the output of scripts/fetch.sh) on the
# machine it runs on, and checks how the result links.
#
#   scripts/build.sh <fetchdir> <outdir>
#
# - linux: run inside the pinned Alpine (musl) image (build.yml does that);
#   links fully static (--enable-static-link). With no termcap library
#   installed, bash uses its own bundled termcap; readline is bash's bundled
#   copy. The result must have no dynamic section.
# - darwin: links against the system only (fully static is impossible on
#   macOS), with termcap from the macOS SDK's ncurses (configure --with-curses;
#   the build fails rather than fall back to the bundled termcap); the result
#   may load nothing outside /usr/lib and /System.
#   MACOSX_DEPLOYMENT_TARGET comes from upstream.json.
#
# Patches are applied in order with patch -p0, as GNU publishes them, and the
# resulting patchlevel.h must state the patchlevel upstream.json claims. bison
# must be on PATH: a patch may change parse.y, and the parser is regenerated.
#
# Result: <outdir>/bash (stripped), <outdir>/COPYING (GPL-3.0 text from the tarball)
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
manifest=${UPSTREAM_JSON:-$root/upstream.json}
fetched=$(cd "${1:?usage: build.sh <fetchdir> <outdir>}" && pwd)
mkdir -p "${2:?usage: build.sh <fetchdir> <outdir>}"
out=$(cd "$2" && pwd)

version=$(jq -er .version "$manifest")
patchlevel=$(jq -er .patchlevel "$manifest")
work=$(mktemp -d)
tar -xzf "$fetched/src/bash-$version.tar.gz" -C "$work"
src="$work/bash-$version"
cd "$src"

for patch in $(jq -r '.sources[].path | select(test("/bash[0-9]+-[0-9]{3}$"))' "$manifest"); do
  echo "build: applying $(basename "$patch")"
  patch -p0 -s --batch <"$fetched/src/$(basename "$patch")"
done
grep -qE "^#define PATCHLEVEL $patchlevel\$" patchlevel.h ||
  { echo "build: patchlevel.h does not say PATCHLEVEL $patchlevel" >&2; exit 1; }

case "$(uname -s)" in
  Linux)
    ./configure --enable-static-link --without-bash-malloc --disable-nls
    ;;
  Darwin)
    MACOSX_DEPLOYMENT_TARGET=$(jq -er .builder.macos_deployment_target "$manifest")
    export MACOSX_DEPLOYMENT_TARGET
    # Link the macOS system ncurses (/usr/lib/libncurses), never bash's bundled
    # termcap. The SDK comes from the system xcrun with any toolchain override
    # cleared, so a nix shell (whose own xcrun and SDK carry no ncurses) and a
    # GitHub macOS runner resolve the same Apple SDK.
    [ -x /usr/bin/xcrun ] || { echo "build: /usr/bin/xcrun is missing (install the Xcode command line tools)" >&2; exit 1; }
    sdk=$(env -u SDKROOT -u DEVELOPER_DIR /usr/bin/xcrun --sdk macosx --show-sdk-path) ||
      { echo "build: xcrun --sdk macosx --show-sdk-path failed" >&2; exit 1; }
    [ -e "$sdk/usr/lib/libncurses.tbd" ] || { echo "build: the macOS SDK $sdk has no usr/lib/libncurses.tbd" >&2; exit 1; }
    ncurses_include="$work/ncurses-include"
    mkdir -p "$ncurses_include"
    for header in curses.h ncurses.h ncurses_dll.h term.h termcap.h unctrl.h; do
      [ -e "$sdk/usr/include/$header" ] || { echo "build: the macOS SDK $sdk has no usr/include/$header" >&2; exit 1; }
      ln -s "$sdk/usr/include/$header" "$ncurses_include/$header"
    done
    echo "build: system ncurses from $sdk"
    ./configure --without-bash-malloc --disable-nls --with-curses \
      CPPFLAGS="-I$ncurses_include" LDFLAGS="-L$sdk/usr/lib"
    termcap_lib=$(sed -n 's/^TERMCAP_LIB[[:space:]]*=[[:space:]]*//p' Makefile)
    case "$termcap_lib" in
      -lncurses | -lcurses) echo "build: termcap library $termcap_lib" ;;
      *) echo "build: configure did not select the system ncurses (TERMCAP_LIB = '$termcap_lib'); refusing to fall back to the bundled termcap" >&2; exit 1 ;;
    esac
    ;;
  *) echo "build: unsupported build OS $(uname -s)" >&2; exit 1 ;;
esac
make -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"
strip bash
cp bash "$out/bash"
cp COPYING "$out/COPYING"
chmod 755 "$out/bash"

# Outputs go to files before they are searched: an early-exiting reader in a
# pipe fails the writer under pipefail.
case "$(uname -s)" in
  Linux)
    readelf -d "$out/bash" >"$work/linkage.txt" 2>&1 || true
    if grep -q 'NEEDED' "$work/linkage.txt"; then
      cat "$work/linkage.txt" >&2
      echo "build: bash is dynamically linked" >&2; exit 1
    fi
    ;;
  Darwin)
    otool -L "$out/bash" >"$work/linkage.txt"
    cat "$work/linkage.txt"
    if tail -n +2 "$work/linkage.txt" | grep -vqE '^[[:space:]]+(/usr/lib/|/System/Library/)'; then
      echo "build: bash loads a library outside the system" >&2; exit 1
    fi
    ;;
esac

"$out/bash" --version >"$work/version.txt"
first=$(sed -n 1p "$work/version.txt")
echo "$first"
case "$first" in
  *"version $version.$patchlevel(1)-release"*) ;;
  *) echo "build: bash --version does not report $version.$patchlevel(1)-release" >&2; exit 1 ;;
esac
echo "build: $out/bash OK"
