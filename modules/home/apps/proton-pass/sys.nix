# ProtonPass • System lane
# System-level configuration (co-located but imported by system profiles)
{ lib, config, pkgs, ... }:

let
  cfg = config.features.protonPass;
in
{
  imports = [ ./options.nix ];
  
  config = lib.mkIf cfg.enable {
    # System packages for ProtonPass dependencies
    environment.systemPackages = with pkgs; [
      # Any system-level dependencies if needed
    ];
    
    # No system services needed for ProtonPass desktop client
  };
}