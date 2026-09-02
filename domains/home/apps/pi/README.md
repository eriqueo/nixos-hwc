# hwc.home.apps.pi

pi coding agent (`@earendil-works/pi-coding-agent`) pinned at **v0.80.7**,
wired to DataX's **DX1** model as the `mycloud` provider and **DX2** as the
`dx2` provider. Declarative
replacement for the imperative `setup-pi.sh` install on datax-box
(`/home/projects/bin/pi` + hand-written `~/.pi/agent/*.json` + `.bashrc` PATH
edits).

## Structure

```
index.nix          # hwc.home.apps.pi — options + models.json/settings.json rendering
parts/package.nix  # pinned buildNpmPackage of the pi monorepo (vendored from
                   # nixpkgs; hwc-server's stable channel has no pi-coding-agent)
parts/guards.ts    # pi extension: tool_call guards, port of the Claude Code
                   # enforce-tools + write-guard PreToolUse hooks
parts/stop-guards.ts # pi extension: agent_end guards, port of ste100-guard and
                   # the self-caught channel of mistake-guard
parts/AGENTS.md    # global instructions → ~/.pi/agent/AGENTS.md
```

## Design decisions

- **Split config (immutable models / seeded settings).**
  `models.json` is a `home.file` store symlink — deterministic provider config,
  byte-identical across hosts, and pi never writes it. `settings.json` is
  **seeded then mutable** via `home.activation` (the tuxedo/freecad
  copy-if-absent pattern): pi rewrites it at runtime (`lastChangelogVersion`,
  trust decisions, UI prefs), so a store symlink would re-nag the changelog
  every launch and drop trust state. Nix provides the initial
  `defaultProvider`/`defaultModel`; pi owns it thereafter.
- **Secret never in the store.** `models.json` uses pi's shell-command
  indirection — `"apiKey": "!cat /run/agenix/pi-dx1-api-key"` — resolved at
  request time. The key lives in
  `domains/secrets/parts/home/pi-dx1-api-key.age` (default mount
  root:secrets 0440; eric reads via the `secrets` group). DX2 does the same
  off `domains/secrets/parts/infrastructure/dx2-api-key.age` →
  `/run/agenix/dx2-api-key`.
- **DX2 is a provider, not a second model.** A pi provider carries one
  `baseUrl` and one `apiKey`, and DX2 is served from its own proxy
  (`dx2.datax.to`) under its own key — so it cannot be a second entry in
  `mycloud.models`. `dx2.enable` is ON, unlike `deepseek.enable`, because the
  key is already provisioned.
- **Endpoint = the LiteLLM proxy, not the pod.** `dx1.baseUrl` is
  `https://dx1.datax.to/v1`. This is the same client-side entry point the
  DataX app uses; it survives DX1 moving between RunPod pods. Pointing at a
  pod-proxy URL directly is what broke this module once already (see
  changelog), so a `proxy.runpod.net` baseUrl now raises a warning.
- **One skill tree, two harnesses.** `skillPaths` defaults to
  `~/.claude/skills`; pi implements the Agent Skills standard and reads that
  tree directly, so there is no second copy to drift. It lands in the `skills`
  array of settings.json — the only Nix-owned key in an otherwise pi-owned
  file, so it is merged **append-only at every activation** (jq + `cmp`,
  the same shape as claude-code's gate-hook heal) rather than seeded. Seeding
  alone would never reach a machine whose settings.json already exists.
- **Guards are an extension, not instructions.** `parts/guards.ts` blocks
  grep/sed, confirms destructive git and `nixos-rebuild`, and refuses
  unbounded reads over 64 KB. `tool_call` fires before execution and
  `{ block: true }` means the call never runs — the model gets no vote. That
  matters more here than under Claude Code: DX1 follows prose rules less
  reliably, so rules worth keeping belong in the extension, not in AGENTS.md.
  Extensions in `~/.pi/agent/extensions/` are auto-discovered, so this needs
  no settings entry.
- **AGENTS.md is short on purpose.** `contextFile` → `parts/AGENTS.md` is
  deliberately shorter than `~/.claude/CLAUDE.md` and is *not* a copy of it.
  Always-loaded instruction volume degrades compliance across every rule, and
  DX1 has less headroom for that than Claude. It carries only what cannot be
  enforced mechanically (guards.ts) or loaded on demand — skills, and the
  per-repo `CLAUDE.md` that pi already discovers from cwd and its ancestors.
  Its content is DX1-shaped: halt condition, quote-the-output-before-claiming,
  read narrowly, no JSON-literal tool args. Those four map to the observed DX1
  failure modes (runaway loops, phantom tool calls, compaction→fabrication,
  tool call rendered as a code block).
- **Vendored package, not overridden.** hwc-server rides nixpkgs-stable
  (25.11) which lacks `pi-coding-agent`, so parts/package.nix carries the
  full derivation (based on nixpkgs' 0.80.2 expression, bumped to 0.80.7).

- **pi owns its packages; Nix owns its rules.** Extensions and skills that come
  from npm or git are installed with `pi install npm:<name>`, which writes the
  `packages` array in the pi-owned settings.json. Nix does not declare that
  array. Two writers on one list is how a declarative file and an imperative
  command fight, and pi's own updater (`pi update --all`) is the reason to let
  pi win. What Nix keeps is the part pi cannot re-derive: the model ring, the
  skill tree path, and the two guard extensions.
- **Two guard extensions, two switches.** `guards.enable` installs
  `parts/guards.ts`, which runs on `tool_call` and BLOCKS — the model gets no
  vote. `stopGuards.enable` installs `parts/stop-guards.ts`, which runs on
  `agent_end`. `agent_end` carries no result type in pi 0.80.7, so an extension
  cannot reject a turn there; it queues a correcting follow-up turn instead,
  with `pi.sendMessage(..., {triggerTurn:true, deliverAs:"followUp"})`. The user
  sees the finished answer first, then the correction turn. That is the one
  behavioural difference from a Claude Code Stop hook, and pi 0.80.7 offers no
  way to close it.
- **Claude in pi is not covered by the Claude plan.** Anthropic gates Pro/Max
  quota to its own clients. pi prints a warning at startup and bills a
  third-party harness per token as extra usage. So `enabledModels` puts
  `mycloud/dx1` first, and Claude Code stays the cheap way to run Claude.

## Updating pi

```
nix flake prefetch github:earendil-works/pi/vX.Y.Z        # → src.hash
curl -sLO https://raw.githubusercontent.com/earendil-works/pi/vX.Y.Z/package-lock.json
nix run nixpkgs#prefetch-npm-deps -- ./package-lock.json  # → npmDepsHash
```
Bump `version` + both hashes in `parts/package.nix`.

## Changelog

- 2026-09-01: Added the **DX2** provider — `dx2.enable` (on by default),
  `dx2.baseUrl` `https://dx2.datax.to/v1`, key via `!cat
  /run/agenix/dx2-api-key` off
  `domains/secrets/parts/infrastructure/dx2-api-key.age`. `dx2/dx2` joins the
  `enabledModels` ring; DX1 stays the default model. The pod-proxy warning now
  iterates over both DataX providers instead of naming dx1 twice.
- 2026-08-26: Daily-driver wave. Added `enabledModels` (Ctrl+P ring:
  `mycloud/dx1`, `anthropic/claude-opus-4-6`, `openai/gpt-5.3-codex`) and
  `deepseek.enable` (off by default — a missing agenix mount fails at request
  time, not at activation). Generalized the skills jq merge into `mergeList`,
  now shared by `skills` and `enabledModels`. Added `stopGuards.enable` with
  `parts/stop-guards.ts`. Extended `parts/guards.ts` with the write-guard port.
  Added the ASD-STE100 standing instruction and the look-before-you-destroy rule
  to `parts/AGENTS.md`. Packages installed imperatively and left pi-owned:
  `pi-mcp-adapter`, `pi-subagents`, `pi-web-access`, `pi-lens`.
- 2026-08-16: Added `contextFile` → `parts/AGENTS.md`.
- 2026-08-16: Added `skillPaths` (default `~/.claude/skills`, append-only jq
  merge into the pi-owned settings.json) and `guards.enable` with
  `parts/guards.ts`. Both verified live: `pi -p` reports the skills loaded,
  and a `grep`/`sed` bash call and a >64 KB unbounded read are blocked.
- 2026-08-16: `dx1.baseUrl` → `https://dx1.datax.to/v1` (LiteLLM proxy). The
  pod-proxy URL for `eanzbnhtt3ji8t` went dead when RunPod flagged a critical
  host error on that machine and DX1 migrated to an H100 pod on 2026-07-22;
  every pi request had been 404ing since. Verified against the new URL with
  the agenix key: `GET /v1/models` → 200 (`llm`, `dx1`), `POST
  /v1/chat/completions` → 200. Warning text generalized off the dead pod id.
- 2026-07-17: Created. Pinned v0.80.7; `mycloud`/`dx1` defaults (256k ctx /
  64k out, from lil-box); agenix-backed apiKey via `!cat` indirection; enabled
  fleet-wide in profiles/base/home.nix. `dx1.baseUrl` set to the RunPod
  pod-proxy URL for pod `eanzbnhtt3ji8t`. models.json immutable; settings.json
  seeded-writable (tuxedo pattern) so pi can persist its own runtime state.
