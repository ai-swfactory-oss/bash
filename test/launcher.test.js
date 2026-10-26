'use strict';

// Named tests over the staged launcher package (BASH_LAUNCHER_DIR, the output of scripts/stage.sh): binaryPath()
// throws a typed error naming the os and cpu when no binary is published for them, and a different one when a binary
// is published but its platform package is not installed.

const assert = require('node:assert/strict');
const path = require('node:path');
const { test } = require('node:test');

const dir = process.env.BASH_LAUNCHER_DIR;
if (dir === undefined) throw new Error('set BASH_LAUNCHER_DIR to the staged launcher package (scripts/stage.sh output)');
const launcher = require(path.resolve(dir, 'index.js'));

test('on an unsupported platform, binaryPath() throws UnsupportedPlatformError naming the os and cpu', () => {
  assert.throws(
    () => launcher.binaryPath('win32', 'x64'),
    (error) =>
      error instanceof launcher.UnsupportedPlatformError &&
      error.name === 'UnsupportedPlatformError' &&
      error.platform === 'win32' &&
      error.arch === 'x64' &&
      /os win32 and cpu x64/.test(error.message)
  );
});

test('on a supported platform whose package is not installed, binaryPath() throws PlatformPackageMissingError', () => {
  const [platform, arch] = launcher.supportedPlatforms[0].split('-');
  assert.throws(
    () => launcher.binaryPath(platform, arch),
    (error) =>
      error instanceof launcher.PlatformPackageMissingError &&
      error.packageName === `@ai-swfactory-oss/bash-${platform}-${arch}` &&
      error.platform === platform &&
      error.arch === arch
  );
});

test('the launcher names every platform bash is built for', () => {
  assert.deepEqual([...launcher.supportedPlatforms].sort(), ['darwin-arm64', 'darwin-x64', 'linux-arm64', 'linux-x64']);
});

test('upstreamVersion is <version>.<patchlevel>, with no re-pack suffix', () => {
  assert.match(launcher.upstreamVersion, /^\d+\.\d+\.\d+$/);
});
