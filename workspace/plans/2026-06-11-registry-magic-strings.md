# Registry-ize the Remaining Magic Strings

**Date**: 2026-06-11
**Status**: SPEC — stepwise-refined, ready for execution
**Depends on**: roles architecture (Charter v12.1, landed 2026-06-11)
**Principles applied**: schema as source of truth; contracts before code;
declarative over imperative; late binding; minimum-viable diffs with
per-commit verification; lints lock in every eliminated literal class.

## 0. The idea in one paragraph

The repo already has four registries — `domains/paths/paths.nix` (paths),
`domains/networking/routes.nix` (Caddy ports/routes),
`hwc.networking.hosts` (tailnet identity), and the flake `machines` table
(fleet membership). Several classes of literal still bypass them: raw
Tailscale IPs, hand-typed `*.ocelot-wahoo.ts.net` FQDNs, re-typed port
numbers, and duplicated syncthing identity/folder data. Each phase below
moves ONE class into a registry, with the same verification gate used in
the roles refactor (drv-hash equality, or nix-diff proof that the delta is
order-only / intentional), and ends by adding a charter lint so the class
cannot reappear.

## 1. Decisions (locked)

1. **Extend `hwc.networking.hosts`, do not invent a new registry.** It is
   the existing precedent for fleet identity and already has the alias →
   hostname map, `primary`, derived `fqdn`, and the `url` helper.
2. **IPs are data, not DNS.** The registry stores each machine's Tailscale
   IP verbatim. Consumers that deliberately use IPs (syncthing addresses,
   NFS device, static hosts map) keep using IPs — read from the registry —
   because their reason is "works when MagicDNS is down/at boot"
   (Chesterton's fence holds; only the *location* of the literal moves).
3. **HM-lane fallbacks centralize in `domains/lib/hm.nix`.** Law 1 means
   HM modules need literal fallbacks for `osConfig = {}`. Instead of
   scattering the server IP across HM files as fallbacks, add ONE helper
   (`hmLib.fleet osConfig`) whose defaults are the only HM-side literals.
   The lint then whitelists exactly one file.
4. **Option defaults are not violations.** A module declaring its own
   `port = mkOption { default = 8096; }` is the producer — that is the
   registry entry for that service. The violation is a *consumer*
   re-typing `8096`/`localhost:8096` instead of reading the option (or
   routes.nix for proxy-side ports).
5. Verification per commit: `nix eval` drvPath for affected machines; if
   hashes move, `nix-diff` + set-equality check; standalone HM lanes must
   stay byte-identical wherever only fallback plumbing changed.

## 2. Phase R0 — inventory freeze + contract (1 commit)

- Re-run and commit the inventory (rg patterns below) as
  `workspace/plans/registry-inventory-2026-06.txt` so progress is diffable.
- Write the extended registry contract in `domains/networking/hosts/index.nix`
  BEFORE migrating any consumer (contracts before code):

```nix
servers = mkOption {
  type = types.attrsOf (types.submodule {
    options = {
      hostname    = mkOption { type = types.str; };          # tailnet host
      ip          = mkOption { type = types.nullOr types.str; default = null; };  # Tailscale IP
      syncthingId = mkOption { type = types.nullOr types.str; default = null; };
    };
  });
};
# derived (existing fqdn/url keep working):
ip   = derived alias -> ip      (assert non-null on access path)
```

- Migration note: `servers` changes type from `attrsOf str` — update the
  2–3 existing readers (`fqdn` derivation, `url`, reverseProxy) in the
  same commit. Blast radius: `rg -n 'hosts\.(servers|fqdn|url)' domains machines profiles`.
- Seed values: main = hwc-server (100.114.232.124, syncthing H3EVGHN-…),
  xps (100.126.80.42), laptop (5UCUDT4-…), phone (syncthing-only entry:
  ROLZBPO-… — decide at execution whether phone is a `servers` entry or a
  separate `peers` attrset; phone has no tailnet service role, so `peers`
  is cleaner).
- Lint target for the phase suite (added in R5):
  `rg -n '100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.' --type nix domains profiles machines --glob '!domains/networking/hosts/**'` → empty
  (the 100.64.0.0/10 CGNAT range Tailscale uses).

## 3. Phase R1 — Tailscale IP consumers (1 commit per consumer group)

Six sites, three risk tiers:

- **R1a (trivial, NixOS lane)**: `machines/laptop/config.nix` —
  syncthing device address, `networking.hosts` static map (derive the
  alias list from routes.nix later — R4 — but the IP from the registry
  now). `machines/server/config.nix` syncthing devices read syncthingId
  from the registry.
- **R1b (recursion fence)**: laptop NFS mount
  `fileSystems."/home/eric/600_shared".device`. The existing comment says
  the literal avoids infinite recursion (fileSystems → paths → users →
  rpcbind). Reading `config.hwc.networking.hosts.ip.main` is a DIFFERENT
  option subtree than hwc.paths, so it likely does not recurse — but
  verify by eval. If it recurses, keep the literal with an
  `# HWC-EXCEPTION(R1): recursion fence` annotation and whitelist in the
  lint. Do not force it.
- **R1c (HM lane)**: shell ssh matchBlocks default + `server`/`xps`
  ssh aliases + frigate `cameras` alias → read via `hmLib.fleet osConfig`
  (guarded, fallback literals live only in domains/lib/hm.nix).
  Acceptance: standalone HM drv unchanged (fallbacks equal today's
  literals); HM-as-module drv may change only if a literal was stale.

## 4. Phase R2 — tailnet FQDN literals (2 commits: NixOS lane, HM lane)

15 files contain `ocelot-wahoo` (inventory in R0). Classes:

- **NixOS lane** (notifications gotify serverUrl, business estimator
  comment, secrets/caddy cert decls, arr-config, routes.nix internals):
  replace with `config.hwc.networking.hosts.url { server = "main"; … }`
  or `fqdn.main`. routes.nix and hosts/index.nix are the registry — they
  may keep the suffix; everything else derives. Watch the secrets/caddy
  pair: cert paths are generated — check `domains/secrets/parts/lib.nix`
  before touching (Chesterton).
- **HM lane** (machines/server/home.nix mail-health webhook,
  mail/health/index.nix, n8n sys.nix shell MCP URL, shell/index.nix):
  `hmLib.fleet` gains `urlMain = port: path: …` building from the same
  fallback constants. The mail-health webhook URL currently lives in
  machines/server/home.nix per Law 16 — deriving it from the helper
  removes the hostname from the machine file too.
- Acceptance test for the whole phase: change `tailnetSuffix` to a dummy
  value, eval all 5 toplevels, confirm zero remaining references to the
  old suffix outside the registry + hm.nix fallbacks (then revert).
- Lint: `rg -n 'ocelot-wahoo' --type nix . --glob '!domains/networking/hosts/**' --glob '!domains/lib/hm.nix'` → empty.

## 5. Phase R3 — port cross-references (1 audit commit + n fix commits)

- Audit: for every `localhost:NNNN` / `127.0.0.1:NNNN` / `:NNNN` literal
  in a CONSUMER position, find the producing option and read it instead.
  Known hits from the roles refactor: business/sys.nix mqtt webhookUrl
  re-types n8n's 5678 (`config.hwc.automation.n8n.port`); monitoring
  alertmanager receivers re-type hwc-notify 11600 and gotify-bridge 9095;
  gotify serverUrl re-types 2586.
- Producers keep their defaults (decision 4). routes.nix stays the
  registry for proxy-facing ports; verify new routes read service options
  rather than re-typing (spot-check 3 routes).
- Lint (heuristic, accepting some curation): a script lint in
  `workspace/nixos/` comparing `rg -o 'localhost:[0-9]+'` hits against a
  whitelist file — start with the whitelist equal to the post-fix state so
  regressions fail, then shrink it opportunistically.

## 6. Phase R4 — syncthing folder map + static hosts derivation (2 commits)

- The 8-folder syncthing map is duplicated verbatim in laptop+server
  config (modulo server's extra inbox-mobile + per-folder device lists).
  Move the folder *table* to a shared data location (suggest: option
  default in `domains/data/syncthing/`, machine files keep only genuine
  one-offs like inbox-mobile and device membership) — same pattern as the
  backup-defaults slim from Phase A of the roles refactor.
- `networking.hosts` static map on laptop (`sonarr.local` etc.): derive
  the name list from routes.nix entries + registry IP, or delete if
  `.local` names are vestigial (check shell history/configs for usage
  before deleting — blast radius).

## 7. Phase R5 — lints + charter v12.2 (1 commit)

- Add the R0/R2/R3 lints to CHARTER.md §3.1 under a new "Law 17:
  Registry-derived identity" (or fold into Law 3's spirit — decide at
  execution; a new law is cleaner since Law 3 is paths-specific).
- Law text sketch: "Network identity (IPs, tailnet FQDNs, cross-service
  ports, sync device IDs) is read from its registry
  (hwc.networking.hosts, routes.nix, producing module options). Literal
  fallbacks for Law-1 contexts live only in domains/lib/hm.nix.
  HWC-EXCEPTION required anywhere else."
- Version bump + version-history entry + profiles/CLAUDE/AGENTS touch-ups.

## 8. Explicitly out of scope

- Personal identity strings (emails, git userName) — Law 4's v12 note
  already blesses literals-as-standard; revisit only if a third consumer
  class appears.
- Renaming the tailnet or changing any actual IP/port value — this plan
  moves literals, never changes them (byte-equal rendered configs except
  where a stale literal is FOUND, which gets its own flagged commit).
- Waybar CSS de-hardcode (separate backlog item; sectionA-D tokens exist).

## 9. Execution order + effort

R0 (contract) → R1a/b/c → R2 → R3 → R4 → R5. Each phase independently
shippable; stop-points after any phase leave the repo consistent. Rough
size: R0–R1 one session; R2 one session (15 files, mechanical with the
acceptance test); R3–R5 one session. Server rebuild required at the end
(gotify/mail URLs re-derived); follow the server-verification prompt from
the roles handoff.
