# bash

[![update](https://github.com/ai-swfactory-oss/bash/actions/workflows/update.yml/badge.svg)](https://github.com/ai-swfactory-oss/bash/actions/workflows/update.yml)
[![build](https://github.com/ai-swfactory-oss/bash/actions/workflows/build.yml/badge.svg)](https://github.com/ai-swfactory-oss/bash/actions/workflows/build.yml)

[GNU bash](https://www.gnu.org/software/bash/) as npm packages: a **native binary per platform, built here from the signed GNU source and official patches**, updated and published automatically to GitHub Packages. There is no download at install time and there are no install scripts. GNU publishes bash as source only, so unlike the shfmt or kustomize wrappers these binaries are our builds; the build is attested and the complete corresponding source is attached to every release.

| Package | What |
|---|---|
| `@ai-swfactory-oss/bash` | Thin: the `bash` bin, and `binaryPath()` / `upstreamVersion` for Node. Depends optionally on the four platform packages, pinned exactly. |
| `@ai-swfactory-oss/bash-linux-x64` | `bin/bash`, static (musl), built in the pinned Alpine image |
| `@ai-swfactory-oss/bash-linux-arm64` | the same for arm64 |
| `@ai-swfactory-oss/bash-darwin-x64` | `bin/bash`, linked against the macOS system libraries only |
| `@ai-swfactory-oss/bash-darwin-arm64` | the same for arm64 |

## Install

GitHub Packages needs the scope line in your project's `.npmrc` (`@ai-swfactory-oss:registry=https://npm.pkg.github.com`) and a `read:packages` token in your user `~/.npmrc`, even for public packages; see the [shfmt wrapper](https://github.com/ai-swfactory-oss/shfmt#install) for details. Then:

```sh
npm install --save-dev @ai-swfactory-oss/bash
npx bash --version
```

From Node, spawn the binary directly, **with the script as an argument**. A `#!/bin/bash` shebang, or a script run by another tool, still reaches the system bash (3.2 on macOS).

```js
const { spawnSync } = require('node:child_process');
const { binaryPath, upstreamVersion } = require('@ai-swfactory-oss/bash');

spawnSync(binaryPath(), ['scripts/build.sh'], { stdio: 'inherit' });
```

`binaryPath()` throws `UnsupportedPlatformError` or `PlatformPackageMissingError` as in the other wrappers. `upstreamVersion` is `<version>.<patchlevel>`, for example `5.3.20`. `$BASH_VERSION` is then `5.3.20(1)-release`.

## How the binary is made, and how to check it

1. **Sources.** `upstream.json` lists `bash-5.3.tar.gz` and every official patch (`bash53-001` …). Each one must carry a GNU signature that verifies against Chet Ramey's key. The fingerprint `7C0135FB088AAF6C66C650B9BB5869F064EA74AB` is pinned in `upstream.json`, and the public key is in `keys/`; neither is fetched at run time.

   GNU publishes signatures, not checksums, for bash, so the signature is the integrity check. `scripts/fetch.sh` deletes and refuses any file whose signature is missing, bad, or made by any other key, before anything is extracted or compiled. The named test `test/signature-mismatch.sh` proves each refusal. The sha256 of every verified file is recorded in `SOURCE-SHA256SUMS`.
2. **Build** (`scripts/build.sh`). It applies the patches in order (`patch -p0`) and checks that `patchlevel.h` agrees, then configures with `--without-bash-malloc --disable-nls`.
   - linux: built inside the Alpine image pinned by digest in `upstream.json`, with `--enable-static-link`. It is checked to have no dynamic section.
   - darwin: built with the pinned `MACOSX_DEPLOYMENT_TARGET`. It is checked to load only `/usr/lib` and `/System` libraries.
   - Readline is bash's bundled copy.
3. **Provenance.** Every published tarball and binary carries a GitHub build-provenance attestation. Check one with `gh attestation verify node_modules/@ai-swfactory-oss/bash-linux-x64/bin/bash --repo ai-swfactory-oss/bash`. The attestation states which workflow run built the binary, from which commit.

## Corresponding source (GPL-3.0-or-later)

Every GitHub release `v<version>` carries:
- the bash tarball, every applied patch, their `.sig` files, and `SOURCE-SHA256SUMS`;
- `build-scripts.tar.gz`: the manifest, keys, scripts and workflows that built the binaries.

That is the complete corresponding source, together with the scripts that control compilation. Each package's `NOTICE` names the release, the pinned signing key, and every source file (GPLv3 section 6(d)).

**Releases are never deleted while their package version is served.** No workflow here deletes releases.

## Versions

- The package version is `<bash version>.<patchlevel>`: bash 5.3 with patch 20 is `5.3.20`.
- A re-pack (a build fix with the same sources) is `<that>-r.<n>`, set with `"repack": <n>`. It is published with the dist-tag `latest`.

## Workflows

| Workflow | When | What |
|---|---|---|
| `update` | Daily; monthly keepalive | New official patches for the pinned version are added to `upstream.json`, with `patchlevel` raised, in a pull request that `build` tests (signature-verified fetch included). A new bash minor fails the run, so `failures` opens an issue for a manual bump. A missing release for main's version re-runs the publish. |
| `build` | Push to `main` touching the build inputs; manual; called by `update` | Named signature test; signature-verified fetch; fetch; build on four runners; stage; launcher tests; pack once; smoke-test the packed tarballs on four runners. On push or manual publish it attests, publishes (platforms first) and creates the release with the source. |
| `pr` | Every pull request | `build` without publishing. |
| `failures` | After `update`/`build` on `main` | Keeps one `build-failure` issue in sync. |

## License

- The scripts and workflows in this repository are **MIT** (see [`LICENSE`](LICENSE)).
- The **npm packages are GPL-3.0-or-later**, the licence of GNU bash. Each package ships the GPL text as `LICENSE`, and a `NOTICE`.

This project is not affiliated with the GNU project or the Free Software Foundation.
