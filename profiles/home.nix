{ config, pkgs, lib, ... }:

{
  #==========================================================================
  # BASE SYSTEM - Critical for machine functionality
  #==========================================================================
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "hm-bak";

    users.eric = {
      imports = [ ../domains/home/index.nix ];
      home.stateVersion = "24.05";

      #==========================================================================
      # OPTIONAL FEATURES - Sensible defaults, override per machine
      #==========================================================================

      # --- Theme & Fonts (BASE) ---
      hwc.home.theme.palette = lib.mkDefault "gruv";
      hwc.home.fonts.enable = lib.mkDefault true;

      # --- Shell Environment (BASE) ---
      hwc.home.shell = {
        enable = lib.mkDefault true;
        modernUnix = lib.mkDefault true;
        git.enable = lib.mkDefault true;
        zsh = {
          enable = lib.mkDefault true;
          starship = lib.mkDefault true;
          autosuggestions = lib.mkDefault true;
          syntaxHighlighting = lib.mkDefault true;
        };
      };

      # --- Desktop Environment (Session-Critical) ---
      hwc.home.apps.hyprland.enable = lib.mkDefault true;   # Wayland compositor
      hwc.home.apps.waybar.enable = lib.mkDefault true;     # Status bar
      hwc.home.apps.swaync.enable = lib.mkDefault true;     # Notification daemon
      hwc.home.apps.kitty.enable = lib.mkDefault true;      # Terminal emulator

      # --- File Management ---
      hwc.home.apps.thunar.enable = lib.mkDefault true;     # GUI file manager
      hwc.home.apps.yazi.enable = lib.mkDefault true;       # TUI file manager

      # --- Web Browsers ---
      hwc.home.apps.chromium.enable = lib.mkDefault true;   # Chromium browser
      hwc.home.apps.librewolf.enable = lib.mkDefault true;  # Privacy-focused Firefox

      # --- Mail & Communication ---
      hwc.home.mail = {
        enable = lib.mkDefault true;
        # Optional overrides for Bridge (defaults are fine to omit)
        # bridge = {
        #   enable = true;        # defaults to true when a proton account exists
        #   logLevel = "warn";    # "error" | "warn" | "info" | "debug"
        #   extraArgs = [ ];
        #   environment = { };
        # };
      };
      hwc.home.apps.aerc.enable = lib.mkDefault true;           # TUI mail client
      hwc.home.apps.neomutt.enable = lib.mkDefault true;        # TUI mail client (alternative)
      hwc.home.apps.neomutt.theme.palette = lib.mkDefault "gruv";
      hwc.home.apps.betterbird.enable = lib.mkDefault true;     # GUI mail client (Thunderbird fork)
      hwc.home.apps.protonMail.enable = lib.mkDefault true;     # Proton Mail bridge/client

      # --- Proton Suite ---
      hwc.home.apps.protonAuthenticator.enable = lib.mkDefault true;  # 2FA authenticator
      hwc.home.apps.protonPass.enable = lib.mkDefault false;          # Password manager (optional)

      # --- Productivity & Office ---
      hwc.home.apps.obsidian.enable = lib.mkDefault true;                    # Knowledge base
      hwc.home.apps.onlyofficeDesktopeditors.enable = lib.mkDefault true;    # Office suite

      # --- Development & Automation ---
      hwc.home.apps.n8n.enable = lib.mkDefault false;            # Workflow automation (resource-heavy)
      hwc.home.apps.geminiCli.enable = lib.mkDefault true;       # AI CLI tool

      # --- Utilities ---
      hwc.home.apps.ipcalc.enable = lib.mkDefault true;          # IP calculator
      hwc.home.apps.wasistlos.enable = lib.mkDefault false;      # System monitor (niche)
    };
  };
}
