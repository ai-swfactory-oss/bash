/** The bash version this package runs, `<version>.<patchlevel>` (e.g. 5.3.20), without any -r.N re-pack suffix. */
export declare const upstreamVersion: string;

/** The `<os>-<cpu>` platforms a binary is published for. */
export declare const supportedPlatforms: readonly string[];

/** No bash binary is published for this os and cpu. */
export declare class UnsupportedPlatformError extends Error {
  readonly name: 'UnsupportedPlatformError';
  readonly platform: string;
  readonly arch: string;
}

/** A binary is published for this os and cpu, but its platform package is not installed. */
export declare class PlatformPackageMissingError extends Error {
  readonly name: 'PlatformPackageMissingError';
  readonly platform: string;
  readonly arch: string;
  readonly packageName: string;
}

/** Name of the platform package that carries the binary for this os and cpu (default: this process's). */
export declare function platformPackage(platform?: string, arch?: string): string;

/**
 * Absolute path of the bash binary for this os and cpu (default: this process's). Spawn it directly with the script
 * as an argument. Throws UnsupportedPlatformError when no binary is published for them, and
 * PlatformPackageMissingError when one is but its package is not installed.
 */
export declare function binaryPath(platform?: string, arch?: string): string;
