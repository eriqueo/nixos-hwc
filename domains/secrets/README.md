# Secrets Domain

## Purpose
- Single source of truth for agenix declarations and the read-only facade consumed by other domains.

## Boundaries
- Namespaces: `hwc.secrets.*` for toggles/hardening, `hwc.secrets.api.*` for decrypted paths exposed to consumers.
- No secret values live in Nix; declarations point to encrypted files kept outside the repo.

## Structure
```
domains/secrets/
├── index.nix            # Aggregator (imports declarations, API, emergency, hardening)
├── declarations/        # Generated age.secrets declarations
│   ├── index.nix        # Aggregates caddy + generated
│   ├── caddy.nix        # caddy-cert/caddy-key OPTIONS
│   └── generated.nix    # ALL non-caddy mounts, generated from parts/**.age
├── parts/               # Encrypted .age files organized by domain (+ helpers)
│   ├── lib.nix          # Pure generator: walks parts/**.age → recipients + mounts
│   ├── caddy.nix        # caddy-cert/caddy-key MOUNTS (runtime hostname selection)
│   ├── caddy/           # TLS certificates
│   ├── home/            # Email, OAuth, scraper credentials
│   ├── infrastructure/  # Database, VPN, camera credentials
│   ├── services/        # Service API keys and passwords
│   └── system/          # User passwords, SSH keys, backups
├── secrets-api.nix      # Stable path facade → `hwc.secrets.api.*`
├── emergency.nix        # Recovery account/password wiring
├── hardening.nix        # Firewall/SSH/fail2ban/audit toggles under `hwc.secrets.hardening.*`
└── vaultwarden/         # Self-hosted Bitwarden password manager (hwc.secrets.vaultwarden.*)
    └── index.nix
```

## How It Fits Together
1. **Generator** (`lib.nix`): a pure, `builtins`-only function that `readDir`-walks `parts/**` for `*.age` (excluding `caddy/`) and emits BOTH the recipient rules (for `secrets.nix`) and the `age.secrets` mounts (for `declarations/generated.nix`). The directory tree of `.age` files is the single source of truth. Secret name = the path under the category dir with subdir segments prefixed, joined by `-`, base name truncated at the first `.`, and `_`→`-` (e.g. `jellyfin/admin-password.age` → `jellyfin-admin-password`).
2. **Declarations** (`declarations/generated.nix`): mounts every secret with `mode=0440 owner=root group=secrets` by default, overridden per-name only for the handful that differ (the `mountOverrides` map). `caddy.nix` + `parts/caddy.nix` stay hand-written because the caddy certs are selected by hostname at runtime.
3. **Recipients** (`secrets.nix`): generated via `lib.nix`'s `mkRecipients`; everything is readable by `everyone` (all hosts + eric). Only the four caddy rules are hand-written.
4. **API Facade** (`index.nix`): maps decrypted paths to `config.hwc.secrets.api.*` so consumers never touch `age.secrets.*` directly.
5. **Emergency** (`emergency.nix`): opt-in recovery credentials and wiring for lockout scenarios.
6. **Hardening** (`hardening.nix`): opt-in firewall/SSH/audit/fail2ban settings; guarded by `hwc.secrets.hardening.*` options.

## Managing Secrets
- **Add a secret**: drop the encrypted `<name>.age` into `parts/<category>/`, then run `sudo agenix -r -i /etc/age/keys.txt` from the repo root. The generator auto-recipients and auto-mounts it — no edits to `secrets.nix` or any declaration file. (Non-default ownership/mode → add one line to `mountOverrides` in `generated.nix`.)
- **Verify consistency**: `bash workspace/system/secrets-parity.sh` asserts every `.age` has a rule + mount and counts match.
- Keep host identity paths configured via `age.identityPaths` (set in `index.nix`) so decryption works at build time.

## Consumer Guidance
- System lane modules read from `hwc.secrets.api.*` and must avoid declaring secrets themselves.
- Permission model: secrets are owned by `root:secrets` with mode `0440` as defined in declaration files.
- Follow Charter Law 3 for paths—mounts and service configs should reference `config.hwc.paths.*`, not hardcoded locations.

## Changelog
- 2026-07-22: Added `sr-gauntlet-claude-oauth` (`parts/services/sr-gauntlet/claude-oauth.age`) — a dedicated long-lived Claude Code subscription token (`claude setup-token`) for the SR Gauntlet's headless agent, after 5 straight `401` failures from it relying on Eric's rotating interactive `~/.claude/.credentials.json`. Plaintext is a single env line `CLAUDE_CODE_OAUTH_TOKEN=<token>` so it drops straight into the unit's `EnvironmentFile`. Standard `root:secrets / 0440`, recipients = everyone (encrypted directly with `age` to the four recipient keys — server/xps/laptop/eric; no full rekey). Consumed only by `domains/automation/sr-gauntlet` (paired with an isolated `CLAUDE_CONFIG_DIR` so the on-disk interactive creds don't shadow it). Verified: `age -d` on hwc-server yields the env line; the token authenticated a live headless `claude -p`.
- 2026-07-19: Rotated `cloudflare-api-key` — the old token was orphaned (visible in no dashboard token list, User or Account, so it could not be edited to add permissions). Replaced with a new account-owned token (`cfat_…`) carrying the old zone scopes plus **Zone → Analytics → Read** (needed for GraphQL threat/traffic analytics; first consumer: the heartwoodcraft.me retirement investigation). Same secret name/path, recipients = everyone (encrypted directly with `age`, no full rekey). Note: `agenix -e` with `EDITOR="cp src"` silently produced an empty payload — verify with `age -d | wc -c` after any scripted edit.
- 2026-07-07: Notification unification — removed `parts/services/slack-webhook-url.age` (the `$env.SLACK_WEBHOOK_URL` n8n injection is gone; no active workflow used it). Dropped its `mountOverrides` entry in `declarations/generated.nix`. The `nanoclaw-slack-*` + `slack-signing-secret` secrets are untouched (nanoclaw bot / Slack app, not the notification path).
- 2026-07-06: Gotify decommission — removed all `gotify-*` secrets from parts/services/ (admin password, per-app taxonomy tokens, host/app tokens). Declarations were auto-generated from the parts/ walk, so no declaration edits needed.
- 2026-07-06: vaultwarden image pinned to 1.35.4 (Law 15 v12.4 critical tier: password vault).
- 2026-07-05: Law 12 burn-down — restructured headings to the required contract (`## Purpose` / `## Boundaries` / `## Structure`); content unchanged, headings renamed/split from the old Scope-&-Boundary/Layout form.
- 2026-06-18: Added `datax-monitor-fb-email` + `datax-monitor-fb-key` — the Firebase service-account client email + private key (`\n`-escaped) for the `datax-monitor` dashboard (`domains/business/datax-monitor`). Standard `root:secrets / 0440`, recipients = everyone. Read at service start by the `read_secret` wrapper into `FIREBASE_CLIENT_EMAIL` / `FIREBASE_PRIVATE_KEY` (the app un-escapes `\n`). `FIREBASE_PROJECT_ID` (`jt-supercharged-db`) is not secret — set as a literal unit env. OpenSearch enrichment **reuses** the existing `opensearch-{host,user,pw}` (same as dxlog) — no new OpenSearch secret. Encrypted directly to the `everyone` recipient set, so adding them did NOT trigger a full `agenix -r` rekey (two-file diff). Values replicate exactly what the working `~/projects/datax-monitor/.env` already uses (verified by a live 542-execution ingest).
- 2026-06-17: Added `github-flake-token` — a scoped read+write fine-grained GitHub PAT (Contents:rw on `eriqueo/{todui,khalt,workbench}`) whose plaintext is a single `access-tokens = github.com=…` line. Standard `root:secrets / 0440`, recipients = everyone. Consumed at **eval time** via `nix.extraOptions = "!include /run/agenix/github-flake-token"` (`profiles/base/sys.nix`) so the root `nixos-rebuild` evaluator can fetch the three private app flake inputs (`github:eriqueo/<app>`). Encrypted directly to the `everyone` recipient set, so adding it did NOT trigger a full `agenix -r` rekey (one-file diff). Replaces the old `git+file:///600_apps/<app>` local-clone inputs — see memory `feedback_app_dev_build_pattern`.
- 2026-06-15: Added `cloudflare-api-key` — the scoped Cloudflare **API token** (`CLOUDFLARE_API_TOKEN`) used by `wrangler` to deploy the `hwc-mcp-gateway` Worker non-interactively (no OAuth login). Standard `root:secrets / 0440`, recipients = everyone. Consumed at deploy time only via a `direnv` `.envrc` in `~/600_apps/hwc-mcp-gateway` that exports it from `/run/agenix/cloudflare-api-key` (eric reads it through the `secrets` group). Not used by any running service.
- 2026-06-15: Added `hwc-gateway-clientid` + `hwc-gateway-secret` — Cloudflare Access **service-token** credentials the `hwc-mcp-gateway` Worker uses to reach the `*-origin.heartwoodcraft.me` MCP origins. Standard `root:secrets / 0440`, recipients = everyone. Values are stored **bare** (the raw `<id>.access` / 64-char secret) — NOT prefixed with the `CF-Access-Client-Id:` / `CF-Access-Client-Secret:` header name, because the Worker (`src/api.ts`) sets those header names itself. Not consumed by any host service; mounted only for durable storage + `wrangler secret put` piping. Adding them triggered a full `agenix -r` rekey (all 110 `.age` re-encrypted to the same recipient set — plaintext unchanged, verified against live mounts).
- 2026-06-12: Added `discord-webhook-nightly-builds` (webhook for the #nightly-builds Discord channel). Standard `eric:secrets / 0440`, recipients = everyone, `owner=eric` override in `generated.nix`. Consumed by the `discord-nightly-builds` notify channel.
- 2026-06-09: Annotated `declarations/caddy.nix` with HWC-EXCEPTION(Law 10) — the hand-written caddy cert cluster is the documented exception, not a violation.
- 2026-06-08: **Generation refactor.** Replaced the hand-maintained `secrets.nix` (107 rules) and the four `declarations/{services,home,infrastructure,system}.nix` files (~91 mounts) with a single filesystem-driven generator (`lib.nix`). `secrets.nix` 166→52 lines; declarations → `generated.nix` (16-entry `mountOverrides`). Migrated the inline `age.secrets` from hermes + lead-scout into the generated layer. Deleted 26 orphan `.age` (the dead `parts/server/` duplicate tree, `borg-remote-ssh-key`, and 3 mount-less `services/{ntfy-user,youtube-db-url,youtube-videos-db-url}`). Fixed the 2 `hwc-xps` caddy certs from `[xps eric]`→`everyone`, and rekeyed the 6 remaining single-recipient blobs (opensearch-*, market-intelligence-*, jobtread-grant-key) so every host can decrypt everything. Parity proven byte-for-byte (hwc-server unchanged; laptop/xps gain only hermes/datax mounts). Added `workspace/system/secrets-parity.sh`.
- 2026-06-02: Reissued the server Caddy TLS cert for the new tailnet name. Renamed `caddy/hwc.ocelot-wahoo.ts.net.{crt,key}.age` → `caddy/hwc-server.ocelot-wahoo.ts.net.{crt,key}.age` (recipients = everyone) and updated `parts/caddy.nix` to select them. New cert generated via `tailscale cert hwc-server.ocelot-wahoo.ts.net` (CN/SAN = `hwc-server.ocelot-wahoo.ts.net`); the old `hwc.*` cert was dropped. `hwc-xps.*` certs are unchanged.
- 2026-05-31: Added 3 secrets for the upcoming hwc-notify + hwc-leads services — `discord-webhook-hwc-alerts`, `discord-webhook-hwc-leads`, `hwc-leads-hmac-secret`. Standard `eric:secrets / 0440` pattern; recipients = everyone.
- 2026-03-26: Added Vaultwarden self-hosted password manager module
- 2026-05-28: Added opensearch-{host,user,pw,app-id} for dxlog (DataX OpenSearch CLI). Standard `mode=0440 root:secrets` pattern; consumed by `domains/home/apps/dxlog` via a wrapper that reads `/run/agenix/opensearch-*` and exports `DXLOG_*` env vars at invocation time
