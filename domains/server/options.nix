# domains/server/options.nix
# Server identity options for multi-server support
#
# Charter v10.3: Domain-level option definitions
# Enables explicit server identification instead of hostname-based detection

{ lib, ... }:
{
  options.hwc.server = {
    enable = lib.mkEnableOption "server workloads";

    role = lib.mkOption {
      type = lib.types.enum [ "primary" "secondary" ];
      default = "primary";
      description = ''
        Server role for service enablement defaults:
        - primary: All services enabled by default (main production server)
        - secondary: Core services only, override to enable more (backup/remote servers)
      '';
    };
  };
}
