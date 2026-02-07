{ lib, pkgs, config, ... }:

let
  cfg = config.hwc.home.apps.librewolf or { enable = false; };
  theme = import ./parts/theme.nix { inherit lib config; };

  # Check if HM version supports profiles (unstable) or uses old API (24.05)
  hasProfiles = builtins.hasAttr "profiles" (config.programs.librewolf or {});
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf cfg.enable {
    programs.librewolf = {
      enable = true;
      package = pkgs.librewolf;

      # Use profiles API if available (HM unstable), otherwise use old settings API (HM 24.05)
    } // lib.optionalAttrs hasProfiles {
      profiles.hwc = {
        isDefault = true;

        settings = lib.mkMerge [
          (import ./parts/behavior.nix { inherit lib pkgs config; })
          (import ./parts/appearance.nix { inherit lib pkgs config; })
        ];

        userChrome  = theme.userChrome;
        userContent = theme.userContent;
      };
    } // lib.optionalAttrs (!hasProfiles) {
      # Fallback for HM 24.05: use old settings format
      settings = lib.mkMerge [
        (import ./parts/behavior.nix { inherit lib pkgs config; })
        (import ./parts/appearance.nix { inherit lib pkgs config; })
      ];
    };

    home.sessionVariables = {
      MOZ_ENABLE_WAYLAND = "1";
    };
  };
}
