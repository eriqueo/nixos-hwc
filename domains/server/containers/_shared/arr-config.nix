# Re-export from canonical location (lib/arr-config.nix)
# Kept for backwards compatibility during DDD migration.
# New code should import directly from lib/arr-config.nix
args: import ../../../../lib/arr-config.nix args
