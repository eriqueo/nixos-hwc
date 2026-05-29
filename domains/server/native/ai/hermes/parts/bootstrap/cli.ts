// cli.ts — Inbound shell adapter. Parses argv, validates env-derived config,
// dispatches to core, formats output.
//
// Wired into PATH by index.nix as `hermes-deploy` via writeShellApplication
// which exports HERMES_HOME_DIR / HERMES_BIN / etc. before exec'ing node.

import { fsAdapter, procAdapter, secretsAdapter } from './adapters.ts';
import { bootstrap, doctor, status, upgrade } from './core.ts';
import type { Config, Ports } from './types.ts';
import { HermesDeployError } from './types.ts';

function loadConfig(): Config {
  const required = [
    'HERMES_HOME_DIR',
    'HERMES_BIN',
    'HERMES_INSTALL_SENTINEL',
    'HERMES_MODEL_PROVIDER',
    'HERMES_MODEL_KEY_FILE',
  ];
  const missing = required.filter((k) => !process.env[k]);
  if (missing.length > 0) {
    throw new HermesDeployError('CONFIG_INVALID', `Missing env vars: ${missing.join(', ')}`);
  }
  const provider = process.env.HERMES_MODEL_PROVIDER as Config['modelProvider'];
  if (!['anthropic', 'openai', 'nous-portal', 'openrouter'].includes(provider)) {
    throw new HermesDeployError('CONFIG_INVALID', `Unknown model provider: ${provider}`);
  }
  return {
    homeDir: process.env.HERMES_HOME_DIR!,
    hermesBin: process.env.HERMES_BIN!,
    installSentinel: process.env.HERMES_INSTALL_SENTINEL!,
    modelProvider: provider,
    modelKeyFile: process.env.HERMES_MODEL_KEY_FILE!,
  };
}

const ports: Ports = {
  proc: procAdapter,
  fs: fsAdapter,
  secrets: secretsAdapter,
};

const usage = `hermes-deploy — Hermes Agent control plane

Commands:
  status              Print install + gateway + skill stats (JSON)
  doctor              Run health checks (nixos + upstream hermes doctor)
  upgrade             hermes update + restart hermes-gateway.service
  bootstrap           Check install state; surface next step if not installed

The systemd oneshot 'hermes-install.service' performs the actual installation.
Use 'sudo systemctl start hermes-install' to (re-)run it.
`;

async function main(argv: string[]) {
  const cmd = argv[2];
  if (!cmd || cmd === '-h' || cmd === '--help') {
    process.stdout.write(usage);
    return 0;
  }

  const cfg = loadConfig();

  switch (cmd) {
    case 'status': {
      const r = await status(cfg, ports);
      process.stdout.write(JSON.stringify(r, null, 2) + '\n');
      return 0;
    }
    case 'doctor': {
      const r = await doctor(cfg, ports);
      for (const f of r.findings) {
        const marker = f.severity === 'ok' ? '✓' : f.severity === 'warn' ? '!' : '✗';
        process.stdout.write(`${marker} ${f.check}${f.detail ? ` — ${f.detail}` : ''}\n`);
      }
      return r.ok ? 0 : 1;
    }
    case 'upgrade': {
      const r = await upgrade(cfg, ports);
      process.stdout.write(r.stdout);
      process.stderr.write(r.stderr);
      return r.exitCode;
    }
    case 'bootstrap': {
      await bootstrap(cfg, ports);
      process.stdout.write('hermes already installed (sentinel present)\n');
      return 0;
    }
    default:
      process.stderr.write(`unknown command: ${cmd}\n\n${usage}`);
      return 2;
  }
}

main(process.argv).then(
  (code) => process.exit(code),
  (err) => {
    if (err instanceof HermesDeployError) {
      process.stderr.write(`[${err.code}] ${err.message}\n`);
      process.exit(1);
    }
    process.stderr.write(`unexpected error: ${err?.message ?? err}\n`);
    process.exit(2);
  },
);
