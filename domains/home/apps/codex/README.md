# codex

## Purpose
Installs the OpenAI Codex CLI (stock `pkgs.codex` by default, overridable via `package`), optional extra session env vars, creates the `~/.config/codex/` directory, links the shared hooks and renders `AGENTS.md`. Skills are not set here: Codex reads `~/.agents/skills`, which agent-harness links to the one skill set every runtime loads. Enable via `hwc.home.apps.codex.enable`.

## Boundaries
- ✅ Package selection with null-check assertion, `env` → `home.sessionVariables`, `codex/.keep` config-dir placeholder, shared hooks and `AGENTS.md`. `parts/package.nix` is an opt-in pin of the upstream 0.146.0 static-musl release binary for machines that set `package = pkgs.callPackage ./parts/package.nix { }`.
- ❌ Does not manage API keys/auth or any `config.toml` contents inside `~/.config/codex/`; the pinned package is NOT the default (server intentionally uses stock pkgs.codex).

## Structure
- `index.nix` — options (`enable`, `package`, `env`, `sharedConfigRepo`, `shareHarness`), install, config dir, hooks link, `AGENTS.md` render and hook trust activation, assertion.
- `hooks-trust.py` — records Codex trust for the shared `~/.codex/hooks.json` entries through the app-server API; beside `index.nix` so it runs by hand against a scratch `CODEX_HOME`.
- `parts/package.nix` — optional pinned codex 0.146.0 derivation from the upstream static-musl release tarball.

## Changelog
- 2026-10-01: Removed `sharedSkillSource`, `sharedSkills` and `workflowSkills`. The two allowlists gave Codex 9 of the shared skills, and hand copies filled the gap and went stale (13 dirs on hwc-laptop dated Aug 28–Sep 13). Codex now reads the whole agent-harness skill set at `~/.agents/skills`; `~/.codex/skills` keeps only Codex's `.system`. HM-only.

- 2026-09-22: Activation also records trust through an existing T3 `~/.codex_p`
  profile. Codex keys trust by the hooks path even when `hooks.json` and
  `config.toml` are symlinks to `~/.codex`, so trusting only the canonical path
  left the same three hooks disabled inside T3.
- 2026-09-17: Consume the Nix-pinned harness, include static standing instructions in AGENTS.md, and stop depending on state-repo merges for rendering.
- 2026-09-17: `shareHarness` (default follows `agent-harness.enable`) links `~/.codex/hooks.json` from the Nix-pinned harness, renders `~/.codex/AGENTS.md` with `codex-agents-render`, and records hook trust with `codex-hooks-trust`. Both run at activation. AGENTS.md is rendered, not committed: it is the Codex preamble, CLAUDE.md, standing instructions, and the PRIMER-DIGEST block, so it cannot drift from its sources and two hosts cannot conflict on it. A hand-written AGENTS.md found in place is kept once as `AGENTS.md.pre-render.bak`. Trust exists because Codex runs no hook until its hash is recorded in the host's config.toml, and that state is per host. `hooks-trust.py` asks the Codex app-server (`hooks/list`) and writes trust through it (`config/value/write`) for user hooks.json entries only; `codex-hooks-trust --check` is the read-only doctor path. Measured: the hash does not depend on Codex version. Do not run `herdr integration install codex` against the link; herdr's v8 entry is already in the shared file. HM-only → `hms`.
- 2026-09-17: Added `workflowSkills`, linking `stepwise-refinement`, `chestertons-fence`, `premortem` and `datax-sr-triage` into `~/.agents/skills`. claude-config's `codex-workflow-start.sh` and `principles-lint.sh` both name that path, but only hwc-laptop had it, built by hand. Codex threads served from hwc-server had none of the four. An existing hand-made entry on the laptop is moved aside with HM's `.backup` suffix. HM-only → `hms`.
- 2026-09-15: Exposed `project-closeout` so Codex can verify project goals and request an explicit worktree disposition independently of handoff. HM-only → `hms`.
- 2026-09-11: Exposed `dx2-evidence` as the explicit read-only Pi worker skill; `delegate` remains the Claude↔Codex cross-audit path. HM-only → `hms`.
- 2026-08-31: Exposed the shared `delegate` skill to Codex alongside Herdr and Project Director, enabling bounded native Claude Code, Codex, and DX1 workers from T3 sessions that lack Herdr pane context. HM-only → `hms`.
- 2026-08-31: Added `sharedSkillSource` plus the selected `herdr` and `project-director` skill symlinks under `~/.codex/skills`; Claude and Codex now consume one source rather than copied orchestration instructions. HM-only → `hms`.
- 2026-07-29: `parts/package.nix` bumped 0.101.0 → 0.146.0. Upstream flipped the x86_64-linux asset from dynamic `-gnu` to static-pie `-musl`, so the `-musl` URL + new sha256, the `mv` source rename, and dropping `autoPatchelfHook` + glibc/openssl/zlib/libcap inputs all moved together. 0.146 supports the gpt-5.6 Sol/Terra/Luna models. HM-only (laptop pin) → `hms`.
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
