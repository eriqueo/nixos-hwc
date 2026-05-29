// adapters.ts — Node-backed implementations of the Ports.
//
// Engineering principle: late binding / environment agnostic. Adapters are
// the only place that touches node:fs / node:child_process. Swap these for
// a different host or for tests without core changes.

import { access, readFile, readdir, constants } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import type { FilesystemPort, ProcessPort, ProcessResult, SecretsPort } from './types.ts';

export const fsAdapter: FilesystemPort = {
  async exists(path) {
    try {
      await access(path, constants.F_OK);
      return true;
    } catch {
      return false;
    }
  },
  async readFileOrNull(path) {
    try {
      return await readFile(path, 'utf8');
    } catch {
      return null;
    }
  },
  async countEntries(dir) {
    const entries = await readdir(dir);
    return entries.length;
  },
};

export const procAdapter: ProcessPort = {
  run(cmd, args, opts = {}) {
    return new Promise<ProcessResult>((resolve) => {
      const child = spawn(cmd, args, {
        env: { ...process.env, ...(opts.env ?? {}) },
        cwd: opts.cwd,
        stdio: ['ignore', 'pipe', 'pipe'],
      });
      let stdout = '';
      let stderr = '';
      child.stdout.on('data', (d: Buffer) => (stdout += d.toString()));
      child.stderr.on('data', (d: Buffer) => (stderr += d.toString()));
      child.on('error', (err: Error) => {
        resolve({ exitCode: 127, stdout, stderr: stderr + String(err) });
      });
      child.on('close', (code: number | null) => {
        resolve({ exitCode: code ?? 0, stdout, stderr });
      });
    });
  },

  async systemctlIsActive(unit) {
    const r = await this.run('systemctl', ['is-active', unit]);
    const out = r.stdout.trim();
    if (out === 'active') return 'active';
    if (out === 'inactive') return 'inactive';
    if (out === 'failed') return 'failed';
    return 'unknown';
  },
};

export const secretsAdapter: SecretsPort = {
  async isReadable(path) {
    try {
      await access(path, constants.R_OK);
      return true;
    } catch {
      return false;
    }
  },
};
