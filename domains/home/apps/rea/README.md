# hwc.home.apps.rea

## Purpose

REA (Reverse Engineer Anything, `morluto/rea`) on every machine: the `rea` CLI,
its MCP server registered for Claude Code, and its investigation skill in the
shared skill set. Pinned to the published `rea-agents` **6.3.0** release.

## Boundaries

- ✅ The pinned package, the Nix-provided analysis engines it can see
  (Ghidra 12 + JDK 21, Apktool, Binwalk, Unblob), the `~/.mcp.json` entry,
  the `reverse-engineer-anything` skill.
- ❌ `rea setup` / `rea update` (they edit agent configs and npm globals; both
  are Nix-owned here). Hopper and IDA (commercial, unconfigured). JADX
  decompilation (needs REA's headless-MCP jar, not nixpkgs `jadx`). A
  Chrome-family browser for website capture: install one on the host.
  Claude Code's MCP file itself → `apps/agent-harness/sys.nix`.

## Structure

```
index.nix          # home lane: `rea` in home.packages; skill → agent-harness extraSkills
sys.nix            # system lane: `rea mcp` entry → agent-harness userMcp.extraServers
parts/package.nix  # buildNpmPackage over the npm release; wrapper sets
                   # GHIDRA_INSTALL_DIR, JAVA_HOME, REA_BINWALK_COMMAND, REA_UNBLOB_COMMAND
parts/src/         # package.json + package-lock.json pinning rea-agents (the only inputs)
```

Both lanes are on by default in `profiles/base` (`hwc.home.apps.rea.enable`,
`hwc.system.apps.rea.enable`).

## Use

Ask Claude Code: "Understand how search works in `<app>`, show the evidence,
and build the same for `<project>`." From a shell:

```
rea --help
rea doctor --json                                   # engine readiness
rea analyze-javascript-application /path/to/app --json
```

## Updating

Edit `parts/src/package.json` to the new version, then in `parts/src/`:

```
npm install --package-lock-only --ignore-scripts
nix run nixpkgs#prefetch-npm-deps -- ./package-lock.json   # → npmDepsHash in parts/package.nix
```

## Changelog

- 2026-10-11: Created. rea-agents 6.3.0 from the npm release (no source build);
  wrapper wires nixpkgs Ghidra 12.0.4, OpenJDK 21, Apktool, Binwalk and
  Unblob. `sys.nix` registers `rea mcp` through the new agent-harness
  `userMcp.extraServers`; `index.nix` adds the bundled skill through the new
  `agent-harness.extraSkills`. Enabled fleet-wide in profiles/base.
