# Re-export from canonical location (lib/mkContainer.nix)
# Kept for backwards compatibility during DDD migration.
# New code should import directly from lib/mkContainer.nix
args: import ../../../../lib/mkContainer.nix args
