# domains/system/packages/base.nix
# BASE PACKAGES - Essential system tools and utilities
# Charter-compliant: implementation only, options in packages/options.nix

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.system.packages.base;
in {
  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
        environment.systemPackages = with pkgs; [
          zsh git micro neovim
          tmux kitty xfce.thunar
          vim ncdu zoxide gh
      
          pass gnupg isync
          neomutt msmtp abook
          w3m lynx gnupg pass file
      
          htop btop tree neofetch
      
          wget curl dhcpcd upower 
          usbutils dnsutils reaverwps fping
      
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
      
          pciutils dmidecode
      
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
          wireguard-tools
        ];
      
        # Recommended modules for NixOS firewall/capture usability
        networking.firewall.enable = true;
      
        # Allow non-root capture with Wireshark/tcpdump (adds group, sets caps)
        programs.wireshark.enable = true;

  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Add assertions and validation logic here
  
}
