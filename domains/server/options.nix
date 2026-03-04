# domains/server/options.nix
# Server identity option — enables server workloads and path defaults

{ lib, ... }:
{
  options.hwc.server = {
    enable = lib.mkEnableOption "server workloads";
  };
}
