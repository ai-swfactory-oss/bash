#!/usr/bin/env bash
# Single-quoted jq programs and Markdown backticks are literal on purpose.
# shellcheck disable=SC2016
# Renders the npm packages from the per-platform builds.
#
#   scripts/stage.sh <builddir> <outdir>
#
# <builddir>/<platform>/{bash,COPYING} are the outputs of scripts/build.sh, one
# per platform in upstream.json.
# Result: <outdir>/bash            the launcher (bin, binaryPath(), upstreamVersion)
#         <outdir>/bash-<platform> one package per platform binary
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
manifest=${UPSTREAM_JSON:-$root/upstream.json}
built=${1:?usage: stage.sh <builddir> <outdir>}
out=${2:?usage: stage.sh <builddir> <outdir>}

scope=@ai-swfactory-oss
repo_url=https://github.com/ai-swfactory-oss/bash.git
upstream=$(jq -er '"\(.version).\(.patchlevel)"' "$manifest")
version=$(bash "$root/scripts/pkgver.sh")
read -r -a platforms <<<"$(jq -r '.platforms | join(" ")' "$manifest")"
release="https://github.com/ai-swfactory-oss/bash/releases/tag/v$version"

common='{
  license: "GPL-3.0-or-later",
  author: "ai-swfactory",
  homepage: "https://github.com/ai-swfactory-oss/bash#readme",
  bugs: { url: "https://github.com/ai-swfactory-oss/bash/issues" },
  repository: { type: "git", url: $repo },
  publishConfig: { registry: "https://npm.pkg.github.com" }
}'

notice() { # <package name> <binary line>
  cat "$root/packages/NOTICE.in"
  printf '\nThis package: %s %s, built from GNU bash %s with official patches 1 to %s.\n' \
    "$1" "$version" "$(jq -r .version "$manifest")" "$(jq -r .patchlevel "$manifest")"
  printf '%s\n\n' "$2"
  printf 'Corresponding source (GPL-3.0-or-later, section 6(d)): the GitHub release\n  %s\n' "$release"
  printf 'carries every file below with its GNU .sig, each verified against the GNU\n'
  printf 'signing key %s pinned in this repository, plus SOURCE-SHA256SUMS\n' "$(jq -r .signing_key "$manifest")"
  printf 'and build-scripts.tar.gz (the scripts, keys, workflow and manifest that built\n'
  printf 'this binary). The same files are available from https://ftp.gnu.org/gnu/bash/.\n\n'
  jq -r '.sources[] | "  \(.path | split("/") | last)"' "$manifest"
}

rm -rf "$out"
mkdir -p "$out"

optional='{}'
for platform in "${platforms[@]}"; do
  os=${platform%%-*}
  cpu=${platform#*-}
  name="$scope/bash-$platform"
  dir="$out/bash-$platform"
  case "$os" in
    linux) linkage="statically linked (musl), built in $(jq -r .builder.alpine "$manifest")" ;;
    darwin) linkage="linked against the macOS system libraries only, deployment target $(jq -r .builder.macos_deployment_target "$manifest")" ;;
  esac

  mkdir -p "$dir/bin"
  cp "$built/$platform/bash" "$dir/bin/bash"
  chmod 755 "$dir/bin/bash"
  cp "$built/$platform/COPYING" "$dir/LICENSE"
  notice "$name" "Binary: bin/bash, $linkage." >"$dir/NOTICE"
  {
    printf '# %s\n\n' "$name"
    printf 'GNU bash %s for `%s` / `%s`, built from the signed GNU source and official patches.\n\n' "$upstream" "$os" "$cpu"
    printf 'Do not install this package directly: install [`%s/bash`](https://github.com/ai-swfactory-oss/bash), which depends on it optionally and runs it.\n\n' "$scope"
    printf 'The binary is %s.\n\n' "$linkage"
    printf 'Provenance: `gh attestation verify bin/bash --repo ai-swfactory-oss/bash` (run in this package directory).\n\n'
    printf 'License: GPL-3.0-or-later (see `LICENSE`). The corresponding source is attached to %s (see `NOTICE`).\n' "$release"
  } >"$dir/README.md"

  jq -n --arg name "$name" --arg version "$version" --arg upstream "$upstream" \
    --arg os "$os" --arg cpu "$cpu" --arg repo "$repo_url" \
    "{
      name: \$name,
      version: \$version,
      description: \"GNU bash \(\$upstream) for \(\$os)-\(\$cpu) (used by @ai-swfactory-oss/bash)\",
      keywords: [\"bash\", \"shell\", \"gnu\"],
      os: [\$os],
      cpu: [\$cpu],
      files: [\"bin/bash\", \"LICENSE\", \"NOTICE\", \"README.md\"],
      preferUnplugged: true
    } + $common" >"$dir/package.json"

  optional=$(jq -c --arg n "$name" --arg v "$version" '. + {($n): $v}' <<<"$optional")
done

launcher="$out/bash"
mkdir -p "$launcher"
cp -R "$root/packages/bash/." "$launcher/"
cp "$built/${platforms[0]}/COPYING" "$launcher/LICENSE"
notice "$scope/bash" "This package holds no binary: it runs the one from $scope/bash-<platform>-<arch>." >"$launcher/NOTICE"
jq --arg version "$version" --arg repo "$repo_url" --argjson optional "$optional" \
  ". + {version: \$version, optionalDependencies: \$optional} + $common" \
  "$root/packages/bash/package.json" >"$launcher/package.json"
chmod 755 "$launcher/bin/bash.js"

echo "stage: $version -> $out"
ls -1 "$out"
