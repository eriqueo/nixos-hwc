{ config, pkgs, lib, ... }:
{
  home.stateVersion = "24.05";

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true; 
    syntaxHighlighting.enable = true;
    dotDir = "${config.xdg.configHome}/zsh";
      history = {
        size = 10000;
        path = "${config.xdg.configHome}/zsh/history";
      };
    shellAliases = {
      g = "git"; ga = "git add"; gc = "git commit"; gp = "git push";
      gs = "git status"; gl = "git log --oneline --graph --decorate --all";
      grebuild = "sudo nixos-rebuild switch --flake /etc/nixos#hwc-kids";
      grebirth = "sudo nixos-rebuild boot --flake /etc/nixos#hwc-kids";
    };
    initExtra = "";
  };

  programs.git.enable = true;
  programs.fzf.enable = true;
  programs.zoxide.enable = true;

  # Needed so GUI auth prompts (e.g., NetworkManager in Hyprland) work
  services.gnome-keyring.enable = true;

  # ↓ THIS must be at the top level (not under programs.zsh)
  systemd.user.services.polkit-agent = {
    Unit = { Description = "Polkit agent"; };
    Service = {
      ExecStart = "${pkgs.lxqt.lxqt-policykit}/bin/lxqt-policykit-agent";
      Restart = "on-failure";
    };
    Install = { WantedBy = [ "graphical-session.target" ]; };
  };

  home.packages = with pkgs; [ ];
}
