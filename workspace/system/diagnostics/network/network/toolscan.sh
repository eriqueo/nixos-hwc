#!/usr/bin/env bash
set -Euo pipefail

# shellcheck source=network-report.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/network-report.sh"
report_init 'Installed tool inventory' 'Check which workstation and network commands are available in PATH.' \
  'Reads command availability; does not scan the network or install anything.' '[--details]' "$@" || exit 0
set -- "${REPORT_ARGS[@]}"

# save as check-tools.sh && bash check-tools.sh
missing=0; available=0; absent=0; missing_groups=()
need() {
  label="$1"; shift
  for c in "$@"; do
    if command -v "$c" >/dev/null 2>&1; then
      printf "  [FOUND] %-22s %s\n" "$label" "$c"
      if (( REPORT_DETAILS )); then info "Path: $(command -v "$c")"; fi
      available=$((available+1)); return 0
    fi
  done
  printf "  [MISSING] %-20s checked: %s\n" "$label" "$*"; missing=1; absent=$((absent+1)); missing_groups+=("$label")
}

report_section "Shells, editors and terminal apps" "Inspect basic workstation commands." "MISSING means absent from PATH, not a broken computer. Some rows accept alternative commands."
need zsh                 zsh
need git                 git
need micro               micro
need neovim              nvim
need tmux                tmux
need kitty               kitty
need thunar              thunar

report_section "Command-line utilities" "Inspect search, browsing and file utilities." "MISSING means absent from PATH, not a broken computer. Some rows accept alternative commands."
need vim                 vim
need ncdu                ncdu
need zoxide              zoxide
need gh                  gh
need tree                tree
need bat                 bat
need eza                 eza
need fzf                 fzf
need ripgrep             rg
need fd                  fd
need neofetch            neofetch

report_section "Mail, secrets and text browsers" "Inspect optional personal workstation tools." "MISSING means absent from PATH, not a broken computer. Some rows accept alternative commands."
need pass                pass
need gpg                 gpg
need isync               mbsync
need neomutt             neomutt
need msmtp               msmtp
need abook               abook
need w3m                 w3m
need lynx                lynx
need file                file

report_section "Hardware and storage tools" "Inspect commands used by system inventory." "MISSING means absent from PATH, not a broken computer. Some rows accept alternative commands."
need htop                htop
need btop                btop
need usbutils            lsusb
need pciutils            lspci
need dmidecode           dmidecode
need parted              parted
need gptfdisk            sgdisk gdisk
need dosfstools          mkfs.vfat fatlabel
need e2fsprogs           mkfs.ext4 fsck.ext4 tune2fs
need ntfs3g              ntfs-3g
need lm_sensors          sensors
need smartmontools       smartctl
need nvme-cli            nvme
need alsa-utils          alsamixer aplay

report_section "Connection tools" "Inspect downloads, routes and path diagnostics." "MISSING means absent from PATH, not a broken computer. Some rows accept alternative commands."
need wget                wget
need curl                curl
need dhcpcd              dhcpcd
need upower              upower
need iproute2            ip
need traceroute          traceroute
need mtr                 mtr

report_section "DNS tools" "Inspect commands that resolve website names." "MISSING means absent from PATH, not a broken computer. Some rows accept alternative commands."
need dnsutils            dig host nslookup
need ldns                drill
need dogdns              dog
# if you truly keep bind (server), at least:
need bind                named rndc

report_section "WiFi and radio tools" "Inspect signal and monitor-mode tooling." "MISSING means absent from PATH, not a broken computer. Some rows accept alternative commands."
need iw                  iw
# NOTE: on NixOS the package name is typically 'wireless-tools';
# but we check for binaries here:
need wireless-tools      iwconfig iwlist
need wpa_supplicant      wpa_supplicant
need wavemon             wavemon
need kismet              kismet
need aircrack-ng         airmon-ng airodump-ng aireplay-ng

report_section "Network scanners" "Inspect device and port discovery tools." "MISSING means absent from PATH, not a broken computer. Some rows accept alternative commands."
need nmap                nmap
need masscan             masscan
need zmap                zmap
need arp-scan            arp-scan
need arping              arping

report_section "Firewall and bridge tools" "Inspect commands for local network configuration." "MISSING means absent from PATH, not a broken computer. Some rows accept alternative commands."
need nftables            nft
need iptables            iptables
need bridge-utils        brctl

report_section "Traffic and performance tools" "Inspect bandwidth and traffic monitors." "MISSING means absent from PATH, not a broken computer. Some rows accept alternative commands."
need iftop               iftop
need nethogs             nethogs
need bmon                bmon
need bandwhich           bandwhich
need conntrack-tools     conntrack
need iperf3              iperf3
need speedtest-cli       speedtest-cli
need fast-cli            fast

report_section "Packet capture tools" "Inspect packet capture and analysis commands." "MISSING means absent from PATH, not a broken computer. Some rows accept alternative commands."
need wireshark           wireshark
need wireshark-cli       tshark
need tcpdump             tcpdump
need ngrep               ngrep
need mitmproxy           mitmproxy

report_section "Network monitoring tools" "Inspect optional intrusion-detection tools." "MISSING means absent from PATH, not a broken computer. Some rows accept alternative commands."
need suricata            suricata
need snort               snort
need zeek                zeek

report_section "Script dependencies" "Inspect support tools used by these scripts." "MISSING means absent from PATH, not a broken computer. Some rows accept alternative commands."
need reaver/wash         wash reaver             # (wash & reaver binaries)
need fping               fping
need ipcalc              ipcalc
need zip                 zip
need unzip               unzip
need p7zip               7z 7za
need rsync               rsync

report_section "Development tools" "Inspect optional coding commands." "MISSING means absent from PATH, not a broken computer. Some rows accept alternative commands."
need lua-language-server lua-language-server
need nil                 nil
need pyright             pyright
need ts-langserver       typescript-language-server
need gopls               gopls
need clang-tools         clangd
need gcc                 gcc
need make                make
need cmake               cmake
need pkg-config          pkg-config
need nodejs              node
need python3             python3
need pip                 pip3 pip
need cargo               cargo
need go                  go
need tree-sitter         tree-sitter
need ctags               ctags
need sops                sops
need age                 age
need ssh-to-age          ssh-to-age
need jq                  jq
need yq                  yq

report_heading "Tool inventory summary"
info "Available tool groups: $available | Missing tool groups: $absent"
info "Next: add only the tools needed for your chosen script to NixOS/Home Manager."
info "This broad inventory includes optional workstation tools. Missing rows do not prevent every network script from running."
if (( missing )); then
  report_tldr CHECK 'Some listed tools are missing; this is not a network fault.' \
    "$available tool groups found; $absent missing. First missing groups: ${missing_groups[*]:0:5}; full list above." \
    'Match missing tools to the script you intend to run. Add only required commands to NixOS/Home Manager; do not install the entire list.' \
    'Availability in PATH does not test a tool, its permissions or any connection.'
else
  report_tldr PASS 'Every listed tool group has an available command.' \
    "$available groups found; none missing." \
    'Run net-tools quicknet for connection diagnosis, or choose the household audit for security testing.' \
    'Alternative commands can satisfy a group; individual script dependencies and permissions still need preflight checks.'
fi
exit "$missing"
