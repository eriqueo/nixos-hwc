# modules/home/apps/betterbird/options.nix
{ lib, ... }:

{
  options.hwc.home.apps.betterbird = {
    enable = lib.mkEnableOption "Enable Betterbird (enhanced Thunderbird) with IMAP-only mode";

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

    unifiedFolders = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable unified folders and smart folders for Work/Personal views";
    };
  };
}