{ lib, pkgs, config, osConfig ? {}, ...}:

let
  cfg = config.hwc.home.apps.librewolf or { enable = false; };
  theme = import ./parts/theme.nix { inherit lib config; };

  # Check if HM version supports profiles (unstable) or uses old API (24.05)
  hasProfiles = builtins.hasAttr "profiles" (config.programs.librewolf or {});

  # Palette validation (from remote)
  paletteName = lib.attrByPath [ "hwc" "home" "theme" "palette" ] null config;
  palettePath = if paletteName != null then ../../theme/palettes/${paletteName}.nix else null;
  paletteExists = palettePath == null || builtins.pathExists palettePath;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
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

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = config.programs.librewolf.enable or false;
        message = "programs.librewolf must remain enabled when hwc.home.apps.librewolf is set";
      }
    ];

    warnings = lib.optionals (paletteName != null && !paletteExists) [
      "Palette \"${paletteName}\" not found under domains/home/theme/palettes; falling back to deep-nord."
    ];
  };
}