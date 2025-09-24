# nixos-h../domains/system/base-packages.nix
#
# BASE PACKAGES - Essential system tools and utilities
# Core command-line tools needed on all machines
#
# DEPENDENCIES (Upstream):
#   - None (base system packages)
#
# USED BY (Downstream):
#   - profiles/base.nix (enables via hwc.system.basePackages.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/base.nix: ../domains/system/base-packages.nix
#
# USAGE:
#   hwc.system.basePackages.enable = true;

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.basePackages;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  options.hwc.system.basePackages = {
    enable = lib.mkEnableOption "Essential system packages";
    
    development = lib.mkEnableOption "Development tools and language servers";
    
    multimedia = lib.mkEnableOption "Multimedia and graphics tools";
  };

  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  config = lib.mkIf cfg.enable {
        environment.systemPackages = with pkgs; [
          zsh git micro neovim
          tmux kitty xfce.thunar
          vim ncdu zoxide gh
      
          pass gnupg isync
          neomutt msmtp abook w3m lynx gnupg pass file
      
          htop btop tree neofetch
      
          wget curl dhcpcd upower usbutils dnsutils reaver fping
      
          unzip zip p7zip rsync
      
          lua-language-server nil pyright
          nodePackages.typescript-language-server
          gopls clang-tools
      
          gcc gnumake cmake
          pkg-config nodejs
          python3 cargo go
      
          bat eza fzf ripgrep fd
      
          python3Packages.pip
          python3Packages.pynvim
          nodePackages.neovim
          tree-sitter
          universal-ctags
      
          sops age ssh-to-age
      
          jq yq
      
          usbutils pciutils dmidecode
      
          parted
          gptfdisk
          dosfstools
          e2fsprogs
          ntfs3g

          lm_sensors smartmontools nvme-cli iproute2 alsa-utils
      
          wireshark wireshark-cli tcpdump ngrep mitmproxy
          nmap masscan zmap arp-scan arping
          traceroute mtr iproute2 nftables iptables bridge-utils
          iftop nethogs bmon bandwhich conntrack-tools
          iperf3 python3Packages.speedtest-cli fast-cli
          iw wirelesstools wpa_supplicant wavemon kismet
          bind ldns dogdns
          suricata snort zeek
          arp-scan arping aircrack-ng
        ];
      
        # Recommended modules for NixOS firewall/capture usability
        networking.firewall.enable = true;
      
        # Allow non-root capture with Wireshark/tcpdump (adds group, sets caps)
        programs.wireshark.enable = true;
    
  };
  
}
