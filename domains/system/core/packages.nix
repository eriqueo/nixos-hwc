{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.system.core.packages;
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
    environment.systemPackages =
      # Base bundle
      (lib.optionals cfg.base.enable (with pkgs; [
        # Core shells and editors
        zsh git micro neovim vim tmux

        # Secrets and password management
        pass gnupg sops age ssh-to-age

        # CLI improvements
        bat eza fzf ripgrep fd zoxide which less diffutils

        # System utilities
        htop btop tree ncdu neofetch usbutils pciutils dmidecode

        # Networking basics
        wget curl

        # Archives and file management
        unzip zip p7zip rsync

        # Language servers and dev toolchain
        lua-language-server nil pyright nodePackages.typescript-language-server
        gopls clang-tools gcc gnumake cmake pkg-config nodejs python3 cargo go
        python3Packages.pip python3Packages.pynvim tree-sitter universal-ctags

        # GitHub CLI
        gh

        # Desktop-capable tools (works over X11 forwarding too)
        kitty xfce.thunar
      ]))

      # Server bundle
      ++ (lib.optionals cfg.server.enable (with pkgs; [
        xorg.xauth evince feh fping ethtool  # file-roller not available in 24.05
        picard claude-code flac
        htop iotop lsof nettools iproute2 tcpdump nmap
        age docker-compose podman-compose rsync rclone unzip p7zip
        postgresql redis ffmpeg imagemagick mediainfo
        python3  # aider-chat and gemini-cli not available in 24.05
        borgbackup restic
      ]))

      # Security/backup bundle
      ++ (lib.optionals cfg.security.enable (
        (with pkgs; [
          rclone rsync gnutar gzip bzip2 p7zip logrotate
          borgbackup restic
          age sops ssh-to-age
        ])
        ++ cfg.security.extraTools
        ++ (lib.optionals cfg.security.protonDrive.enable (with pkgs; [ rclone ]))
      ));

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [];
  };
}
