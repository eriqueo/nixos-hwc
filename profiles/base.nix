{ lib, pkgs, ... }:
{
  imports = [
    ../modules/system/paths.nix
    ../modules/system/filesystem.nix
    ../modules/system/networking.nix
    ../modules/security/secrets.nix
    ../modules/home/eric.nix
    ../modules/infrastructure/gpu.nix
  ];

  # Your base configuration
  time.timeZone = "America/Denver";

  # Nix configuration
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
      trusted-users = [ "eric" ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
  };

  # Charter v3 Networking Configuration
  hwc.networking = {
    enable = true;
    ssh = {
      enable = true;
      passwordAuthentication = false;
      x11Forwarding = lib.mkDefault false;
    };
    networkManager.enable = true;
    firewall = {
      enable = true;
      strict = true;
      allowPing = false;
    };
    tailscale.enable = true;
  };

  # Container runtime (from your config)
  virtualisation = {
    docker.enable = true;
    oci-containers.backend = "docker";
  };

  # Basic packages
  environment.systemPackages = with pkgs; [
    vim
    git
    wget
    curl
    htop
    tmux
    ncdu
    tree
    ripgrep
    fd
    bat
    eza
    zoxide
    fzf
  ];

  # Charter v3 User Configuration
  hwc.home = {
    user.enable = true;
    groups = {
      basic = true;        # wheel, networkmanager
      media = true;        # video, audio, render
      development = true;  # docker, podman
    };
    ssh.enable = true;
    environment = {
      enableZsh = true;
      enablePaths = true;
    };
  };

  # Charter v3 Security Configuration
  hwc.security = {
    enable = true;
    secrets = {
      user = true;  # User account secrets
      vpn = true;   # VPN credentials for Tailscale/services
    };
    ageKeyFile = lib.mkDefault "/etc/age/keys.txt";
  };

  # Enable core filesystem management
  hwc.filesystem = {
    enable = true;
    securityDirectories.enable = true;  # Security dirs always needed
  };
}
