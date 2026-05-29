// core.ts — Pure functions, no I/O. All side effects flow through Ports.
//
// Engineering principle: contracts before code. Each command takes a Config
// and Ports record and returns a structured result. The shell (cli.ts)
// translates these results to argv/exit-codes.

import type { Config, Ports, ProcessResult } from './types.ts';
import { HermesDeployError } from './types.ts';

export interface StatusReport {
  readonly installed: boolean;
  readonly installSentinel: string;
  readonly gateway: 'active' | 'inactive' | 'failed' | 'unknown';
  readonly modelProvider: Config['modelProvider'];
  readonly modelKeyReadable: boolean;
  readonly skillCount: number | null;
  readonly conversationDb: boolean;
}

export interface DoctorFinding {
  readonly severity: 'ok' | 'warn' | 'error';
  readonly check: string;
  readonly detail?: string;
}

export interface DoctorReport {
  readonly findings: readonly DoctorFinding[];
  readonly ok: boolean;
}

// ── status ──────────────────────────────────────────────────────────────────

export async function status(cfg: Config, ports: Ports): Promise<StatusReport> {
  const [installed, gateway, modelKeyReadable, skillCount, conversationDb] = await Promise.all([
    ports.fs.exists(cfg.installSentinel),
    ports.proc.systemctlIsActive('hermes-gateway.service'),
    ports.secrets.isReadable(cfg.modelKeyFile),
    ports.fs.countEntries(`${cfg.homeDir}/.hermes/skills`).catch(() => null),
    ports.fs.exists(`${cfg.homeDir}/.hermes/conversations.db`),
  ]);

  return {
    installed,
    installSentinel: cfg.installSentinel,
    gateway,
    modelProvider: cfg.modelProvider,
    modelKeyReadable,
    skillCount,
    conversationDb,
  };
}

// ── doctor ──────────────────────────────────────────────────────────────────

export async function doctor(cfg: Config, ports: Ports): Promise<DoctorReport> {
  const findings: DoctorFinding[] = [];

  // 1. Install sentinel
  const installed = await ports.fs.exists(cfg.installSentinel);
  findings.push({
    severity: installed ? 'ok' : 'error',
    check: 'hermes-install completed',
    detail: installed ? cfg.installSentinel : `missing sentinel: ${cfg.installSentinel}`,
  });

  // 2. Hermes binary exists
  const binExists = await ports.fs.exists(cfg.hermesBin);
  findings.push({
    severity: binExists ? 'ok' : 'error',
    check: 'hermes binary present',
    detail: cfg.hermesBin,
  });

  // 3. Model key file readable
  const keyReadable = await ports.secrets.isReadable(cfg.modelKeyFile);
  findings.push({
    severity: keyReadable ? 'ok' : 'error',
    check: 'model API key readable',
    detail: cfg.modelKeyFile,
  });

  // 4. Gateway unit state
  const gateway = await ports.proc.systemctlIsActive('hermes-gateway.service');
  findings.push({
    severity: gateway === 'active' ? 'ok' : gateway === 'inactive' ? 'warn' : 'error',
    check: 'hermes-gateway unit',
    detail: gateway,
  });

  // 5. Defer to upstream `hermes doctor` for in-app checks
  if (binExists) {
    const r = await ports.proc.run(cfg.hermesBin, ['doctor'], { env: { HOME: cfg.homeDir } });
    findings.push({
      severity: r.exitCode === 0 ? 'ok' : 'warn',
      check: 'hermes doctor (upstream)',
      detail: r.exitCode === 0 ? 'pass' : (r.stderr || r.stdout).trim().split('\n')[0],
    });
  }

  const ok = findings.every((f) => f.severity !== 'error');
  return { findings, ok };
}

// ── upgrade ─────────────────────────────────────────────────────────────────

export async function upgrade(cfg: Config, ports: Ports): Promise<ProcessResult> {
  const binExists = await ports.fs.exists(cfg.hermesBin);
  if (!binExists) {
    throw new HermesDeployError('INSTALLER_FAILED', `hermes binary missing at ${cfg.hermesBin}`);
  }

  const updateResult = await ports.proc.run(cfg.hermesBin, ['update'], {
    env: { HOME: cfg.homeDir },
  });
  if (updateResult.exitCode !== 0) {
    throw new HermesDeployError('UPGRADE_FAILED', `hermes update exited ${updateResult.exitCode}`, updateResult);
  }

  // Restart gateway (requires sudo on most setups; cli shell handles auth)
  return ports.proc.run('systemctl', ['restart', 'hermes-gateway.service']);
}

// ── bootstrap (manual; systemd oneshot does the same in production) ────────

export async function bootstrap(cfg: Config, ports: Ports): Promise<void> {
  if (await ports.fs.exists(cfg.installSentinel)) {
    return; // idempotent — nothing to do
  }
  // We delegate to the upstream installer script the same way the systemd
  // oneshot does — that lives in index.nix's hermes-installer; here we
  // surface a clear error so the human knows to run it.
  throw new HermesDeployError(
    'INSTALLER_FAILED',
    'hermes not yet installed; run `sudo systemctl start hermes-install` to bootstrap',
  );
}
