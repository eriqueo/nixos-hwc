# hwc.home.apps.pi

pi coding agent (`@earendil-works/pi-coding-agent`) pinned at **v0.80.7**,
wired to DataX's **DX2** model as a bounded worker lane. Declarative
replacement for the imperative `setup-pi.sh` install on datax-box
(`/home/projects/bin/pi` + hand-written `~/.pi/agent/*.json` + `.bashrc` PATH
edits).

## Structure

```
index.nix          # options, DX2-only routing, and bounded subagent configuration
parts/package.nix  # pinned buildNpmPackage of the pi monorepo (vendored from
                   # nixpkgs; hwc-server's stable channel has no pi-coding-agent)
parts/guards.ts    # pi extension: the Pi-only rule, refusing unbounded reads
                   # of large files
parts/AGENTS.md    # global instructions → ~/.pi/agent/AGENTS.md
                   # (hwc-hook-bridge.ts is claude-config pi/hook-bridge.ts,
                   # substituted in index.nix; it runs the shared hooks)
```

## Design decisions

- **Split config (immutable models / reconciled settings).**
  `models.json` is a `home.file` store symlink — deterministic provider config,
  byte-identical across hosts, and pi never writes it. `settings.json` is
  **seeded then mutable** via `home.activation` (the tuxedo/freecad
  copy-if-absent pattern): pi rewrites it at runtime (`lastChangelogVersion`,
  trust decisions, UI prefs), so a store symlink would re-nag the changelog
  every launch and drop trust state. Nix replaces only the routing keys on
  activation. Pi keeps unrelated runtime state.
- **Secret never in the store.** `models.json` uses pi's shell-command
  indirection — `"apiKey": "!cat /run/agenix/pi-dx1-api-key"` — resolved at
  request time. The key lives in
  `domains/secrets/parts/home/pi-dx1-api-key.age` (default mount
  root:secrets 0440; eric reads via the `secrets` group). DX2 uses that mount
  because its endpoint accepts the existing DataX credential.
- **Pi is the DX2 worker lane.** `models.json` declares only `dx2/llm`.
  `settings.json` selects only that model and enforces the same scope for native
  subagents. External Claude Code, Codex, and Cursor agent profiles are disabled.
  Project settings or a separately invoked binary remain explicit escape hatches.
- **DX2 reasoning levels match the endpoint.** The model advertises reasoning
  to pi and maps only `low`, `medium`, and `xhigh`, the values accepted by the
  DX2 API. Unsupported levels are hidden instead of producing retry loops.
  Pi's mutable `defaultThinkingLevel` can select a supported level; `Shift+Tab` or
  `--thinking` can select another supported level for a session.
- **Endpoint = the stable proxy, not the pod.** `dx2.baseUrl` is
  `https://dx2.datax.to/v1`. A `proxy.runpod.net` base URL raises a warning.
- **Subagent fan-out is bounded.** The auto-managed subagent config permits two
  concurrent children, four launches per run, eight launches per session, and
  two active asynchronous runs. Work above a limit is rejected or queued by
  the extension according to the limit's documented behavior.
- **One skill set, three runtimes.** `skillPaths` defaults to
  `~/.claude/skills`, which agent-harness links to `agentSkills`, the same set
  Claude and Codex (`~/.agents/skills`) read, so there is no second copy to
  drift. It stays on the Claude root: the merge below is append-only, so a
  second root would load every skill twice; the agent-harness doctor fails on
  any Pi skill path that is not the set. It lands in the `skills`
  array of settings.json. The skill list is merged **append-only at every activation** (jq + `cmp`,
  the same shape as claude-code's gate-hook heal) rather than seeded. Seeding
  alone would never reach a machine whose settings.json already exists.
- **Guards are hooks, not instructions, and they are Claude's hooks.**
  `hwc-hook-bridge.ts` sends each Pi event to claude-config's
  `codex/hook-bridge.py --runtime pi`, which runs the hooks `settings.json`
  registers for the same Claude tool name. `tool_call` fires before execution
  and `{ block: true }` means the call never runs; an `ask` confirms with a UI
  and blocks headless. A Stop block arrives on `agent_settled` (not
  `agent_end`, after which Pi may still retry or compact) and becomes a
  follow-up turn, at most two. The Stop guards read a Claude-format projection
  of the current branch. `parts/guards.ts` keeps the one Pi-only rule, the
  64 KB read limit. DX2 follows prose rules less reliably, so rules worth
  keeping belong in hooks, not in AGENTS.md.
- **AGENTS.md is short on purpose.** `contextFile` → `parts/AGENTS.md` is
  deliberately shorter than `~/.claude/CLAUDE.md` and is *not* a copy of it.
  Always-loaded instruction volume degrades compliance across every rule, and
  DX2 has less headroom for that than Claude. It carries only what cannot be
  enforced mechanically (the shared hooks, guards.ts) or loaded on demand — skills, and the
  per-repo `CLAUDE.md` that pi already discovers from cwd and its ancestors.
  Its content is small-model-shaped: halt condition, quote-the-output-before-claiming,
  read narrowly, no JSON-literal tool args. Those four map to observed worker
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
  skill tree path, the hook bridge and the read guard.
- **A Stop block is a follow-up, not a rejection.** Pi 0.80.7 cannot reject a
  finished turn, so the user sees the answer first, then the correction turn.
  That is the one behavioural difference from a Claude Code Stop hook.
- **Frontier models run in their native harnesses.** Pi's enabled model ring has
  only DX2. Claude Code and Codex retain their native subscription logins.

## Updating pi

```
nix flake prefetch github:earendil-works/pi/vX.Y.Z        # → src.hash
curl -sLO https://raw.githubusercontent.com/earendil-works/pi/vX.Y.Z/package-lock.json
nix run nixpkgs#prefetch-npm-deps -- ./package-lock.json  # → npmDepsHash
```
Bump `version` + both hashes in `parts/package.nix`.

## Changelog

- 2026-10-01: Removed the hand ports now that the shared hooks run: `parts/stop-guards.ts` and `stopGuards.enable` are gone, and `parts/guards.ts` keeps only the 64 KB read limit (grep/sed, destructive-git and rebuild confirmation, write-guard and the workspace-guard exec now come from the shared hooks). Policy change: Pi's Stop check is now the shared ste100 answer-length rule (block over 900 words), not the old 30-word sentence port; a headless Pi run now also blocks on enforce-tools' advisory asks (secrets and Caddy route edits).

- 2026-10-01: `hookBridge.enable` installs claude-config's `pi/hook-bridge.ts` as `hwc-hook-bridge.ts`, with the pinned python and `codex/hook-bridge.py` substituted. Pi now runs every shared Claude hook (the bridge reads settings.json) instead of four hand ports; a bridge failure blocks bash/write/edit. Measured 0.24 s per PreToolUse call. Live: `pi -p` was denied `grep` by the shared enforce-tools.

- 2026-10-01: `~/.claude/skills` is now the agent-harness one skill set (harness + adopted cloudflare skills, without the `skills/synced/` claude.ai copies Pi used to load twice). `skillPaths` is unchanged; its description says why.

- 2026-09-30: `guards.ts` runs the shared `workspace-guard.sh` (agent workspace S2) on bash, write and edit calls, with `HWC_HOOK_RUNTIME=pi`. It is not ported, so Claude, Codex and Pi apply one rule set. An armed deny blocks only with a UI; no-UI runs are allowed and logged.

- 2026-09-17: Build Pi's global context from the Nix-pinned harness and its shared standing instructions.

- 2026-09-11: Made Pi the bounded DX2 worker lane. Removed DX1, DeepSeek, and
  frontier models from Nix-owned routing. Added strict DX2 subagent scope,
  disabled external frontier profiles, and capped concurrency and fan-out.
  Activation now reconciles routing while preserving Pi-owned runtime state.
- 2026-09-08: Declared DX2 as a reasoning model and mapped its supported
  `low`, `medium`, and `xhigh` thinking levels. Unsupported levels are hidden;
  Pi's existing `medium` default now reaches DX2 as `reasoning_effort`.
- 2026-09-08: DX2 now reads `/run/agenix/pi-dx1-api-key`, matching the live
  endpoint's accepted credential, and uses the endpoint's advertised `llm`
  model slug (`dx2/llm`). Removed the superseded dedicated DX2 secret after
  the live Pi probe passed.
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
