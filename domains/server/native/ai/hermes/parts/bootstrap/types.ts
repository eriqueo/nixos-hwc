// types.ts — Ports (interfaces) the core depends on. Adapters implement these.
//
// Engineering principle (hexagonal): core knows nothing about node:fs or
// node:child_process. Swapping adapters (e.g. for tests, or for a different
// host) must not require changes inside core.ts.

export interface Config {
  readonly homeDir: string;
  readonly hermesBin: string;
  readonly installSentinel: string;
  readonly modelProvider: 'anthropic' | 'openai' | 'nous-portal' | 'openrouter';
  readonly modelKeyFile: string;
}

export interface ConfigParseError {
  readonly kind: 'CONFIG_INVALID';
  readonly missing: string[];
}

export interface ProcessResult {
  readonly exitCode: number;
  readonly stdout: string;
  readonly stderr: string;
}

export interface ProcessPort {
  run(cmd: string, args: string[], opts?: { env?: Record<string, string>; cwd?: string }): Promise<ProcessResult>;
  systemctlIsActive(unit: string): Promise<'active' | 'inactive' | 'failed' | 'unknown'>;
}

export interface FilesystemPort {
  exists(path: string): Promise<boolean>;
  readFileOrNull(path: string): Promise<string | null>;
  countEntries(dir: string): Promise<number>;
}

export interface SecretsPort {
  isReadable(path: string): Promise<boolean>;
}

export interface Ports {
  readonly proc: ProcessPort;
  readonly fs: FilesystemPort;
  readonly secrets: SecretsPort;
}

export class HermesDeployError extends Error {
  constructor(
    public readonly code:
      | 'CONFIG_INVALID'
      | 'INSTALLER_FAILED'
      | 'SECRET_UNREADABLE'
      | 'UPGRADE_FAILED'
      | 'UNIT_NOT_FOUND',
    message: string,
    public readonly detail?: unknown,
  ) {
    super(message);
    this.name = 'HermesDeployError';
  }
}
