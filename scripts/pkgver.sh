#!/usr/bin/env bash
# Prints the npm package version for upstream.json: <version>.<patchlevel>
# (bash 5.3 with patch 20 is 5.3.20), or <that>-r.<repack> when this
# repository re-packs the same upstream source.
set -euo pipefail
manifest=${UPSTREAM_JSON:-$(cd "$(dirname "$0")/.." && pwd)/upstream.json}
jq -er '"\(.version).\(.patchlevel)" as $v | if (.repack // 0) > 0 then "\($v)-r.\(.repack)" else $v end' "$manifest"
