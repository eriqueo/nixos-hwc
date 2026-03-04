# Re-export from canonical location (lib/mkInfraContainer.nix)
# Kept for backwards compatibility during DDD migration.
# New code should import directly from lib/mkInfraContainer.nix
args: import ../../../../lib/mkInfraContainer.nix args
