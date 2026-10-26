# @ai-swfactory-oss/bash

[GNU bash](https://www.gnu.org/software/bash/), built from the signed GNU source and official patches, as an npm package that runs a native binary for your platform. There is no download at install time and there are no install scripts.

Platforms: `linux-x64` and `linux-arm64` (static, musl), and `darwin-x64` and `darwin-arm64` (system libraries only). The binary comes from the matching optional dependency `@ai-swfactory-oss/bash-<platform>-<arch>`.

## Install

The package is on GitHub Packages. Put `@ai-swfactory-oss:registry=https://npm.pkg.github.com` in your project's `.npmrc`, and a `read:packages` token in your user `~/.npmrc`. Then:

```sh
npm install --save-dev @ai-swfactory-oss/bash
npx bash --version
```

## Use

```js
const { binaryPath, upstreamVersion } = require('@ai-swfactory-oss/bash');
// binaryPath(): absolute path to bash for this os and cpu. Spawn it with the script as an argument.
// upstreamVersion: "<version>.<patchlevel>", e.g. "5.3.20"
```

A `#!/bin/bash` shebang still reaches the system bash. Spawn `binaryPath()` explicitly.

`binaryPath()` throws `UnsupportedPlatformError` when no binary is published for this os and cpu. It throws `PlatformPackageMissingError` when one is published but its package was not installed.

## Source and licence

GPL-3.0-or-later. The complete corresponding source is attached to the GitHub release of each version: the bash tarball, the patches, their GNU signatures, and the build scripts. Each platform package's `NOTICE` names the release and lists those files and the pinned GNU signing key. Details: https://github.com/ai-swfactory-oss/bash#corresponding-source-gpl-30-or-later
