{ lib, pkgs, config, ... }:

let
  cfg = config.hwc.home.apps.librewolf or { enable = false; };
  theme = import ./parts/theme.nix { inherit lib config; };
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

      profiles.hwc = {
        isDefault = true;

        settings = lib.mkMerge [
          (import ./parts/behavior.nix { inherit lib pkgs config; })
          (import ./parts/appearance.nix { inherit lib pkgs config; })
        ];

        userChrome  = theme.userChrome;
        userContent = theme.userContent;
      };
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
