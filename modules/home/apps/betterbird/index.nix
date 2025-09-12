# nixos-hwc/modules/home/betterbird/default.nix
#
# Home UI: Betterbird Email Client (Universal Config Domains)  
# Charter v5 compliant - Email client configuration with behavior/session/appearance domains
#
# DEPENDENCIES (Upstream):
#   - profiles/workstation.nix (imports via home-manager.users.eric.imports)
#
# USED BY (Downstream):
#   - Home-Manager configuration only
#
# USAGE:
#   Import this module in profiles/workstation.nix home imports
#   Universal domains: behavior.nix (filters/tags), session.nix (services), appearance.nix (styling)
#

{ lib, pkgs, config, ... }:
let
  # Import universal config domains
  behavior = import ./parts/behavior.nix { inherit lib pkgs config; };
  session = import ./parts/session.nix { inherit lib pkgs; };
  appearance = import ./parts/appearance.nix { inherit lib pkgs config; };

  homeDir = config.home.homeDirectory;
  profileBase = "${homeDir}/.thunderbird";  # Betterbird uses same profile structure
in
{
  #============================================================================
  # HOME PACKAGES (Email Ecosystem)
  #============================================================================
  home.packages = with pkgs; [
    thunderbird      # TODO: Switch to betterbird when available in nixpkgs
    protonmail-bridge
  ];

  #============================================================================
  # SESSION VARIABLES
  #============================================================================
  home.sessionVariables = {
    THUNDERBIRD_PROFILE = "default-release";  # Betterbird uses same profile system
  };

  #============================================================================
  # SYSTEMD SERVICES (Session Domain)
  #============================================================================
  systemd.user.services = session.services;

  #============================================================================
  # CONFIGURATION FILES (Behavior + Appearance)
  #============================================================================
  home.file = lib.mkMerge [
    (behavior.files profileBase)
    (appearance.files profileBase)
  ];
}