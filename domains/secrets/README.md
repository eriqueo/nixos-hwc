# Secrets Domain

## Scope & Boundary
- Single source of truth for agenix declarations and the read-only facade consumed by other domains.
- Namespaces: `hwc.secrets.*` for toggles/hardening, `hwc.secrets.api.*` for decrypted paths exposed to consumers.
- No secret values live in Nix; declarations point to encrypted files kept outside the repo.

## Layout
```
domains/secrets/
├── index.nix            # Aggregator (imports declarations, API, emergency, hardening)
├── declarations/        # Data-only age.secrets declarations
│   ├── options.nix
│   ├── caddy.nix
│   ├── home.nix
│   ├── infrastructure.nix
│   ├── server.nix
│   └── system.nix
├── parts/               # Reusable fragments for declaration files
│   ├── caddy/
│   ├── home/
│   ├── infrastructure/
│   ├── networking/
│   ├── server/
│   └── system/
├── secrets-api.nix      # Stable path facade → `hwc.secrets.api.*`
├── emergency.nix        # Recovery account/password wiring
├── hardening.nix        # Firewall/SSH/fail2ban/audit toggles under `hwc.secrets.hardening.*`
├── options.nix          # Domain options
└── (encrypted *.age files live outside this tree)
```

## How It Fits Together
1. **Declarations** (`declarations/*.nix`): define `age.secrets.<name>` entries grouped by domain (home, system, server, infrastructure, caddy). No logic beyond declarations.
2. **Parts**: shared snippets imported by declaration files to avoid duplication.
3. **API Facade** (`secrets-api.nix`): maps decrypted paths to `config.hwc.secrets.api.*` so consumers never touch `age.secrets.*` directly.
4. **Emergency** (`emergency.nix`): opt-in recovery credentials and wiring for lockout scenarios.
5. **Hardening** (`hardening.nix`): opt-in firewall/SSH/audit/fail2ban settings; guarded by `hwc.secrets.hardening.*` options.

## Managing Secrets
- Add a secret by encrypting the value (age) and referencing it from the correct `declarations/<domain>.nix` file.
- Expose the path through `secrets-api.nix` (or reuse an existing entry) so modules consume `config.hwc.secrets.api.<name>` instead of `age.secrets.*`.
- Keep host identity paths configured via `age.identityPaths` (set in `index.nix`) so decryption works at build time.

## Consumer Guidance
- System lane modules read from `hwc.secrets.api.*` and must avoid declaring secrets themselves.
- Permission model: secrets are owned by `root:secrets` with mode `0440` as defined in declaration files.
- Follow Charter Law 3 for paths—mounts and service configs should reference `config.hwc.paths.*`, not hardcoded locations.
