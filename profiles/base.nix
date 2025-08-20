{ lib, pkgs, ... }:
{
  imports = [
    ../modules/system/paths.nix
    ../modules/system/users.nix
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

  # Basic networking
  networking = {
    networkmanager.enable = true;
    firewall = {
      enable = true;
      allowPing = false;
    };
  };

  # SSH
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
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

  # Enable ZSH
  programs.zsh.enable = true;
}
