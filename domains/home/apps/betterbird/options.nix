# modules/home/apps/betterbird/options.nix
{ lib, ... }:

{
  options.hwc.home.apps.betterbird = {
    enable = lib.mkEnableOption "Enable Betterbird (enhanced Thunderbird)";

    maildirIntegration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Link existing Maildir to Thunderbird LocalFolders for unified access";
    };

    protonBridgeIntegration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Pre-configure Proton Bridge accounts with certificate integration";
    };

    vimKeybindings = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable vim-like keybindings (requires tbkeys-lite addon)";
    };
  };
}