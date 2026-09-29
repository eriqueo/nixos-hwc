# domains/data/syncthing/parts/datax-ignores.nix
#
# Ignore list for the 700_datax folder, shared by hwc-laptop and hwc-work (the
# only two peers since 2026-09-28). Syncthing never syncs .stignore, so both
# hosts must declare the same list or a checkout leaks through the one without.
#
# Only loose scripts and notes at the folder root sync. Git repos and the
# gauntlet trees stay per-host; GitHub is the cross-machine git transport.
[
  "// Declared in nixos-hwc domains/data/syncthing/parts/datax-ignores.nix."
  "// Git internals: two hosts mutating one .git through file sync corrupts it."
  "**/.git"
  "**/.git/**"
  "// Repo containers, legacy checkouts and the host-bound gauntlet trees."
  "/datax"
  "/jt-mcp"
  "/dx-mcp"
  "/datax-*"
  "/jt-mcp-*"
  "/dx-mcp-*"
  "/sr_gauntlet"
  "/dx1_gauntlet"
  "/gauntlets"
  "// Workspace helpers are a git repo (eriqueo/datax-tools); git carries them."
  "/tools"
  "// mint-ms-work-token.sh copies .env.local here; credentials never cross hosts."
  "/.secrets-backup"
  "**/node_modules"
  "**/.next"
  "**/.DS_Store"
  "**/.vscode/.history"
]
