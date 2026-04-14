# save as check-tools.sh && bash check-tools.sh
missing=0
need() {
  label="$1"; shift
  for c in "$@"; do
    if command -v "$c" >/dev/null 2>&1; then printf "OK   %-18s %s\n" "$label" "$(command -v "$c")"; return 0; fi
  done
  printf "MISSING %-18s tried: %s\n" "$label" "$*"; missing=1
}

# shells/editors/terms
need zsh                 zsh
need git                 git
need micro               micro
need neovim              nvim
need tmux                tmux
need kitty               kitty
need thunar              thunar

# cli utils
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

# secrets/mail/web
need pass                pass
need gpg                 gpg
need isync               mbsync
need neomutt             neomutt
need msmtp               msmtp
need abook               abook
need w3m                 w3m
need lynx                lynx
need file                file

# sysinfo/storage
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

# net basics
need wget                wget
need curl                curl
need dhcpcd              dhcpcd
need upower              upower
need iproute2            ip
need traceroute          traceroute
need mtr                 mtr

# dns & name tools
need dnsutils            dig host nslookup
need ldns                drill
need dogdns              dog
# if you truly keep bind (server), at least:
need bind                named rndc

# wifi & radio
need iw                  iw
# NOTE: on NixOS the package name is typically 'wireless-tools';
# but we check for binaries here:
need wireless-tools      iwconfig iwlist
need wpa_supplicant      wpa_supplicant
need wavemon             wavemon
need kismet              kismet
need aircrack-ng         airmon-ng airodump-ng aireplay-ng

# nmap & scanners
need nmap                nmap
need masscan             masscan
need zmap                zmap
need arp-scan            arp-scan
need arping              arping

# firewall/bridge
need nftables            nft
need iptables            iptables
need bridge-utils        brctl

# traffic & perf
need iftop               iftop
need nethogs             nethogs
need bmon                bmon
need bandwhich           bandwhich
need conntrack-tools     conntrack
need iperf3              iperf3
need speedtest-cli       speedtest-cli
need fast-cli            fast

# capture/analysis
need wireshark           wireshark
need wireshark-cli       tshark
need tcpdump             tcpdump
need ngrep               ngrep
need mitmproxy           mitmproxy

# IDS/NSM
need suricata            suricata
need snort               snort
need zeek                zeek

# extras used by scripts
need reaver/wash         wash reaver             # (wash & reaver binaries)
need fping               fping
need ipcalc              ipcalc
need zip                 zip
need unzip               unzip
need p7zip               7z 7za
need rsync               rsync

# LSPs / dev toolchain (spot-check primary binaries)
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

exit $missing
