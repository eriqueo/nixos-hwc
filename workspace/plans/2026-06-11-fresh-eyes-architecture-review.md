# Fresh-Eyes Architecture Review — 2026-06-11

Requested by Eric after the roles refactor: "this was all kinda ad hoc as I
learned both Linux and NixOS — look with fresh eyes for glaring holes in the
theory." Scope: magic strings / dynamic-naming lint, registry coverage,
domain-boundary coherence, and the §9 standing findings. Every item is a
small-diff proposal, ranked. Nothing here is a big-bang rewrite.

Verdict up front: the theory is sound. Domains/roles/machines layering,
namespace=folder, the paths/routes/hosts registries — these are the right
shapes, and v12.1 made them real. The holes are *adoption* holes: registries
that exist but aren't used everywhere, two boundary mistakes, and one domain
(backup) with three owners for the same job.

---

## Part 1 — Magic-string lint (ranked, small diffs each)

### 1.1 Hand-built tailnet URLs bypass the hosts registry  [HIGH, ~10 small diffs]

`hwc.networking.hosts` already has exactly the right design — `tailnetSuffix`,
a `servers` alias map, derived `fqdn`, and a `url` helper whose docstring even
says "never derive a cross-host address from the local hostname." But only the
reverseProxy module actually consumes it. Meanwhile these build
`https://hwc-server.ocelot-wahoo.ts.net…` by hand:

- `domains/automation/n8n/sys.nix:77,83,84` (N8N_HOST, EDITOR_BASE_URL, WEBHOOK_URL)
- `domains/notifications/index.nix:43` (webhook default)
- `domains/notifications/send/gotify/index.nix:164` (server URL default)
- `domains/business/website/index.nix:60,70` (calculator webhook defaults)
- `domains/home/core/shell/index.nix:102` (MCP endpoint default)
- `domains/lib/arr-config.nix:77` (webhook default arg)
- `domains/mail/health/index.nix:358` (example only — fine, but update with the sweep)

**Fix per file**: replace the literal with
`config.hwc.networking.hosts.url { port = …; path = "…"; }`. One commit per
domain, hash-verified (option *defaults* changing to the same string is a
no-op; prove with byte-identical drv hashes).

**Gotcha**: HM-lane modules (`home/core/shell`) can't see
`config.hwc.networking.hosts` — they need the guarded `osConfig` form, with
the current literal kept as the Law-1 fallback. That pattern already exists
(scraper precedent).

### 1.2 Ports inside those URL literals duplicate routes.nix  [HIGH, same sweep]

The literals above embed `:2443`, `:10000`, `:2586` — port facts that
routes.nix (and the gotify module's own `port` option) already own. When a
port moves, today you'd have to find these by grep. The 1.1 sweep should pull
the port from the owning option (`config.hwc.notifications.gotify.port`) or a
routes-registry lookup, not re-state the number.

**Proposed lint (§3.1)**: no `ocelot-wahoo.ts.net` literal outside
`domains/networking/hosts/` and `domains/secrets/parts/caddy.nix` (cert
filenames are genuinely file-path-bound):

```
rg -n 'ocelot-wahoo\.ts\.net' domains/ profiles/ machines/ --type nix \
  | rg -v 'networking/hosts|secrets/parts/caddy'
```

### 1.3 Tailscale IP literals  [MEDIUM, blocked on 2.1]

`100.114.232.124` (server) appears in:
- `machines/laptop/config.nix:192` (syncthing peer address), `:210` (NFS mount), `:356` (static hosts block)
- `domains/home/core/shell/index.nix:84` (ssh config hostname)
- `domains/home/core/shell/parts/aliases.nix:19` (ssh aliases; also `100.126.80.42` = xps, `:27` `100.115.126.41` = a camera)

These can't derive from MagicDNS names everywhere (NFS mounts and syncthing
want IPs at boot, before/independent of MagicDNS; the laptop's static-hosts
block exists precisely as a MagicDNS fallback). So the fix is not "use the
hostname" — it's a **fleet identity registry** (see 2.1) that owns the IPs
once, and these five sites read from it.

**Proposed lint (§3.1)** once 2.1 lands: no `100.x.y.z` literal outside the
registry:

```
rg -n '"100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.' domains/ profiles/ machines/ --type nix \
  | rg -v 'networking/hosts'
```

### 1.4 `Origin` header literal in routes.nix:237  [LOW]

Routes.nix itself hand-builds one FQDN (an Origin header). Fold into the 1.1
sweep — routes.nix may import the hosts registry (registry-reads-registry is
fine; routes already owns ports).

---

## Part 2 — Conceptual findings

### 2.1 Fleet identity registry  [RECOMMEND: yes, in hosts registry — not the flake table]

Eric asked whether the flake machines table should own Tailscale IPs and
syncthing device IDs. Recommendation: **own them in
`hwc.networking.hosts.servers`** (turn the attr values into submodules:
`{ hostname, tailscaleIp ? null, syncthingId ? null }`), not in flake.nix.

Why not the flake table: the table is deliberately *thin* (channel + roles +
pkgs — Law 16's membership registry). IPs and device IDs are *network
identity* — they belong to the networking domain, are consumed by modules via
`config.*` (which flake-level data can't be without extra glue), and the
hosts registry is already "the ONE place" per its own docstring. Small diff:
extend the submodule type, keep `fqdn`/`url` derivation, add
`hwc.networking.hosts.ip.<alias>`. Then fix the five 1.3 sites. Two commits.

### 2.2 `domains/server/native/ai/` vs `domains/ai/` — boundary is NOT coherent  [MEDIUM]

`domains/ai/` holds agent/cloud/ollama/mcp/personas/profiles/tools.
`domains/server/native/ai/` holds brain-mcp, hermes, jobber-mcp, lead-scout,
llama-cpp, market-intelligence, persona-daemon — also AI. The split is
actually *deployment style* (server-native systemd services) vs *capability*
(AI), which violates the v12.1 rule that domains = capabilities and
machines/roles decide placement. llama-cpp next to ollama in two different
domains is the smell.

Also: `domains/server/containers/` now contains only `_shared` — the arr
stack etc. lives in `domains/media/`. `domains/server/` is close to empty of
meaning. **Proposal (one git-mv commit per service, hash-verified)**: fold
`server/native/ai/*` into `domains/ai/` (or `domains/business/` for
jobber-mcp/lead-scout if Eric considers them business capabilities);
`server/services/inbox-processor` → its capability domain; then retire
`domains/server/` and have the server *role* import from capability domains.
This finishes what v12.0 started when infrastructure/ was dissolved. Defer
to Eric on the jobber-mcp/lead-scout call.

### 2.3 GPU module: folder ≠ namespace (Law 2 violation)  [SMALL]

`domains/system/gpu/index.nix` declares `options.hwc.system.hardware.gpu`.
Law 2 says `domains/system/gpu/` ⇒ `hwc.system.gpu.*`. Either git-mv the
folder into `domains/system/hardware/gpu/` (smaller blast radius: zero
namespace consumers change — recommended) or rename the namespace (touches
~15 consumer files: media/ai/gaming modules assert on
`hwc.system.hardware.gpu.*`). Found while moving the CUDA cache (2026-06-11).

### 2.4 Backup domain: three owners for database dumps  [MEDIUM — decide before moving code]

Found while attempting the §10.1 "borg preBackupScript → data domain" item;
the move is deliberately NOT done because the domain has three overlapping
dump mechanisms:

1. `machines/server/config.nix` borg `preBackupScript` — pg_dumpall + CouchDB
   export to `/var/lib/backups` (ACTIVE, the real one).
2. `parts/database-hooks.nix` — pg/mysql/redis/docker dump machinery gated on
   `cfg.database.*.enable` — no machine sets any (DORMANT).
3. `parts/server-backup-scripts.nix` — container + per-DB pg dumps to
   `hwc.paths.hot/backups`, gated on plain `cfg.enable` (ACTIVE wherever
   backup is enabled — overlaps #1 for postgres, different location).

**Proposal**: pick one owner (suggest: promote #1's logic into the domain as
`hwc.data.backup.database.{postgresql,couchdb}.dumps` with dumpDir from
paths; delete #2 if Eric confirms it never shipped; gate #3 behind its own
flag instead of `cfg.enable`). Three small commits after Eric picks. The §9
smartd item below is the same disease.

### 2.5 smartd double-ownership (§9 standing)  [SMALL]

`domains/monitoring/alerts/index.nix:145` configures `services.smartd` when
`sources.smartd.enable`, AND `machines/server/config.nix:681` configures raw
`services.smartd`. The module even asserts the raw service is enabled —
codifying the split. **Proposal**: machine file keeps only device-specific
settings via the module's options (add a `devices`/`extraOptions` option to
alerts.sources.smartd); raw `services.smartd` block leaves the machine file.
Charter clarification: a domain module that wraps `services.X` owns
`services.X` — machines never touch the raw service when an hwc wrapper
exists. That's a one-line addition to Law 4's commentary.

### 2.6 gemini-cli deep osConfig access (§9 standing)  [SMALL, charter-only]

`apps/gemini-cli/index.nix` reads `osCfg.age.secrets.gemini-api-key.path`
through the lib helpers — guarded, safe, but outside Law 1's three
whitelisted patterns. Since it already uses `domains/lib/hm.nix` (`osCfgOr`),
the cheapest fix is charter-side: bless "guarded `age.secrets` *path* reads
via lib/hm.nix helpers" as whitelisted pattern #4. No code change.

### 2.7 Leftover SSH/secret cruft from today's password-auth work  [SMALL]

- agenix secret `user-ssh-public-key` is now consumed by nothing (the broken
  readFile lane was removed). Candidate for deletion from declarations +
  parts on the next secrets pass.
- The server's mutable `~/.ssh/authorized_keys` carries a second Termius key
  (`…zCjx`) that is NOT in the declarative set. Decide: add it to
  `hwc.system.users.user.ssh.keys` or treat it as stale and remove the
  mutable file after the server rebuild proves key auth via the declarative
  path. The decision is Eric's (it's a phone key).
- `jellyfin-api-key` agenix secret already exists in secrets.api — if
  declarative Jellyfin policy management is ever revived, wire `apiKeyFile`
  to it (the plaintext key deleted today never needed to exist).

### 2.8 kids RetroArch cores: HM list vs `hwc.gaming.retroarch.cores`  [SMALL]

`machines/kids/home.nix` installs `retroarch.withCores` (9 cores, HM lane);
the server uses `hwc.gaming.retroarch.cores` (8 cores, system lane, +sunshine).
Same intent, two vocabularies. **Proposal**: teach the gaming domain a
`cores`-driven HM half (gaming role already has home.nix lane) so kids
declares cores the same way the server does; machine keeps only the core
*list* if it differs. Defer until someone touches gaming again — low value,
nonzero risk.

### 2.9 The 6 imported-never-enabled apps — keep/delete recommendations

| App | Lines | Recommendation | Why |
|---|---|---|---|
| thunderbird | 25 | **delete** | Trivial to recreate with mkSimpleApp; redundant with betterbird |
| qutebrowser | 49 | **delete** | LibreWolf is the blessed browser; nothing references it |
| jellyfin-media-player | 45 | **delete** | Thin wrapper, recreate in minutes if wanted |
| mpv | 39 | **enable on desktop or delete** | Only one likely to be *missed* — a desktop without any video player is odd; if VLC/celluloid isn't installed elsewhere, enable it on the desktop role instead of deleting |
| betterbird | 71 + 5 parts | **Eric decides** | Real config investment (behavior/appearance/session/tools/profile parts). Keep only if a GUI mail client is still on the roadmap; mail role is aerc/neomutt today |
| transcript-formatter | 92 | **keep** | Unique pipeline logic (Ollama/Qwen → Obsidian), just received a Law-3 fix; hard to recreate. But enable it where it's actually used, or it rots |

Per Law 13 (dead code), the three "delete" rows should go in one commit once
Eric confirms.

---

## Part 3 — Proposed new §3.1 lints (after the fixes land)

1. **No tailnet-suffix literals** outside `domains/networking/hosts/` (+ caddy
   cert part) — command in 1.2.
2. **No tailnet IP literals** outside the hosts registry — command in 1.3,
   after 2.1.
3. **No raw `services.X` in machines/** when an `hwc.*` wrapper for X exists
   (mechanical approximation: `rg -n 'services\.(smartd|smartctl…)' machines/`
   seeded with the wrapped-service list; or prose-only as Law 4 commentary).

## Suggested order of execution

| # | Item | Size | Risk |
|---|---|---|---|
| 1 | 2.1 fleet identity registry (hosts submodules) | S | low |
| 2 | 1.3 IP literal sweep (5 sites) | S | low |
| 3 | 1.1+1.2+1.4 URL/port sweep (~10 sites, one commit per domain) | M | low (hash-verified no-ops) |
| 4 | 2.3 gpu folder git-mv | S | low |
| 5 | 2.5 smartd ownership + Law 4 commentary | S | low |
| 6 | 2.4 backup dump ownership (needs Eric's pick) | M | medium |
| 7 | 2.2 dissolve domains/server/ (needs Eric's jobber/lead-scout call) | M | medium |
| 8 | 2.9 app deletions (needs Eric's confirm) | S | low |
| 9 | 2.8 retroarch cores unification | S | low value — last |
