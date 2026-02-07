{ config, lib, ... }:

# domains/system/core/filesystem.nix
#
# Minimal filesystem materializer for HWC-managed directories.
# Only creates state/cache/log directories with proper ownership.
# Does NOT chown user home or mounted media paths (prevents destructive operations).
#
# Charter Reference: Law 9 (Filesystem Materialization Discipline)

let
  cfg = config.hwc.paths;

  # Only HWC-managed service directories - NOT user home or mounted storage
  hwcStateDirs = [
    "/var/lib/hwc"   # HWC state directory
    "/var/cache/hwc" # HWC cache directory
    "/var/log/hwc"   # HWC logs directory
  ];

  # Safe ownership - eric:users for HWC service directories
  owner = "eric";
  group = "users";
in
{
  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================

  config = lib.mkIf (config.hwc.system.core.enable or true) {
    # Create minimal bootstrap directories only
    # Does NOT create or chown:
    # - cfg.user.home (user manages this)
    # - cfg.hot.root (may be mounted filesystem)
    # - cfg.media.root (may be mounted filesystem)
    systemd.tmpfiles.rules = map (d:
      "d ${d} 0755 ${owner} ${group} -"
    ) hwcStateDirs;

    #========================================================================
    # VALIDATION
    #========================================================================

    assertions = [
      {
        assertion = lib.all (p: lib.hasPrefix "/" p) hwcStateDirs;
        message = "All hwc state/cache/log paths must be absolute";
      }
      {
        assertion = lib.hasPrefix "/" cfg.user.home;
        message = "hwc.paths.user.home must be absolute (filesystem materializer check)";
      }
    ];
  };
}
