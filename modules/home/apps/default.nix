# nixos-hwc/modules/home/apps/default.nix
#
# HOME APPS AGGREGATOR (v6) - UI-only app configs behind toggles.
# No environment.systemPackages or systemd.services here.

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.home.apps;
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.home.apps = {
    enable = lib.mkEnableOption "Enable Home-layer app configs";

    kitty.enable     = lib.mkEnableOption "Kitty terminal (HM)";
    thunar.enable    = lib.mkEnableOption "Thunar (HM)";
    waybar.enable    = lib.mkEnableOption "Waybar UI (HM)";
    hyprland.enable  = lib.mkEnableOption "Hyprland appearance (HM)";
    #betterbird.enable  = lib.mkEnableOption "bettterbird appearance (HM)";
    #chromium-ui.enable  = lib.mkEnableOption "chromium appearance (HM)";

    # Browser options
    browser = {
      firefox = lib.mkEnableOption "Firefox browser";
      chromium = lib.mkEnableOption "Chromium browser";
      librewolf = lib.mkEnableOption "LibreWolf browser";
    };

    # Application categories
    multimedia = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable multimedia applications";
      };
    };

    productivity = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable productivity applications";
      };
    };

    # future: betterbird.enable, firefox-ui.enable, chromium-ui.enable, etc.
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
    #==========================================================
    # DYNAMIC IMPORTS - Must be at top level
    #==========================================================
    imports = [
      ./kitty.nix
      ./thunar.nix
      ./waybar/default.nix
      ./hyprland/default.nix
    ];

  config = lib.mkIf cfg.enable {
  #============================================================================
  # VALIDATION
  #============================================================================
  assertions = [
    {
      assertion = !(config ? environment && config.environment ? systemPackages)
               && !(config ? systemd && config.systemd ? services);
      message   = "Home apps aggregator must not set system packages/services.";
    }
  ];

  #============================================================================
  # BROWSER CONFIGURATION
  #============================================================================
  # Firefox Home Manager integration
  programs.firefox.enable = cfg.browser.firefox;

  # Browser packages via Home Manager
  home.packages = with pkgs; []
    ++ lib.optionals cfg.browser.chromium [ chromium ]
    ++ lib.optionals cfg.browser.librewolf [ librewolf ]
    ++ lib.optionals cfg.multimedia.enable [
      vlc
      mpv
      pavucontrol
      obs-studio
    ]
    ++ lib.optionals cfg.productivity.enable [
      obsidian
      libreoffice
    ]
    ++ [
      # Fonts
      jetbrains-mono
      nerd-fonts.jetbrains-mono
      fira-code
      font-awesome
    ];

  #============================================================================
  # XDG PORTALS AND FONTS
  #============================================================================
  # XDG portal for file dialogs
  xdg.portal = {
    enable = true;
    wlr.enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gtk
    ];
  };

  # Font configuration
  fonts.fontconfig.enable = true;


  };
}
