#!/usr/bin/env bash
set -euo pipefail

have(){ command -v "$1" >/dev/null 2>&1; }
section(){ printf "\n=== %s ===\n" "$1"; }
kv(){ printf "%-18s %s\n" "$1:" "$2"; }

human_uptime_linux(){
  if [ -r /proc/uptime ]; then
    read -r up _ </proc/uptime || up=0
    s=${up%.*}
    d=$((s/86400)); s=$((s%86400))
    h=$((s/3600));  s=$((s%3600))
    m=$((s/60))
    out=""
    [ "$d" -gt 0 ] && out+="${d}d "
    [ "$h" -gt 0 ] && out+="${h}h "
    out+="${m}m"
    printf "%s\n" "$out"
  else
    uptime 2>/dev/null || true
  fi
}

h_kib(){
  awk -v k="$1" 'BEGIN{u[0]="KiB";u[1]="MiB";u[2]="GiB";u[3]="TiB";i=0;v=k+0;while(v>=1024&&i<3){v/=1024;i++}printf("%.1f %s",v,u[i])}'
}

linux_summary(){
  section "Summary"
  os=""; [ -r /etc/os-release ] && . /etc/os-release && os="${PRETTY_NAME}"
  host=$(hostname 2>/dev/null || true)
  vendor=$(cat /sys/devices/virtual/dmi/id/sys_vendor 2>/dev/null || true)
  product=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || true)
  cpu=$(have lscpu && lscpu | awk -F: '/^Model name/{sub(/^[ \t]*/,"",$2);print $2; exit}')
  cpus=$(have lscpu && lscpu | awk -F: '/^CPU\(s\)/{sub(/^[ \t]*/,"",$2);print $2; exit}')
  memk=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
  mem=$(h_kib "$memk")
  gpus=$(have lspci && lspci | grep -Ei 'vga|3d|display' | sed 's/^.*controller: //; s/^/ - /')
  disks_n=0
  disks_sz=0
  if have lsblk; then
    while read -r size type; do
      [ "$type" = "disk" ] || continue
      disks_n=$((disks_n+1))
      disks_sz=$((disks_sz+size))
    done < <(lsblk -bdn -o SIZE,TYPE 2>/dev/null)
  fi
  disks_h=$(awk -v b="$disks_sz" 'BEGIN{u[0]="B";u[1]="KiB";u[2]="MiB";u[3]="GiB";u[4]="TiB";i=0;v=b+0;while(v>=1024&&i<4){v/=1024;i++}printf("%.1f %s",v,u[i])}')
  kv "Host" "$host"
  kv "Model" "$(printf "%s %s" "$vendor" "$product" | sed 's/^ //; s/ $//')"
  kv "OS" "$os"
  kv "CPU" "$(printf "%s (%s threads)" "${cpu:-unknown}" "${cpus:-?}")"
  kv "Memory" "$mem"
  if [ -n "$gpus" ]; then printf "%s\n" "GPUs:"; printf "%s\n" "$gpus"; fi
  kv "Disks" "$(printf "%s total, %s aggregate" "$disks_n" "$disks_h")"
}

linux_system(){
  section "System"
  kv "Hostname" "$(hostname 2>/dev/null || true)"
  if [ -r /etc/os-release ]; then . /etc/os-release; kv "OS" "${PRETTY_NAME:-Linux}"; else kv "OS" "$(uname -sr)"; fi
  kv "Kernel" "$(uname -r)"
  if have systemd-detect-virt; then kv "Virtualization" "$(systemd-detect-virt || true)"; fi
  if grep -qi microsoft /proc/version 2>/dev/null; then kv "Environment" "WSL"; fi
  kv "Uptime" "$(human_uptime_linux)"
}

linux_cpu(){
  section "CPU"
  if have lscpu; then
    lscpu | awk -F: '
      /^Model name/ {printf "%-18s %s\n","Model",$2}
      /^Vendor ID/ {printf "%-18s %s\n","Vendor",$2}
      /^Socket\(s\)/ {printf "%-18s %s\n","Sockets",$2}
      /^Core\(s\) per socket/ {printf "%-18s %s\n","Cores/Socket",$2}
      /^Thread\(s\) per core/ {printf "%-18s %s\n","Threads/Core",$2}
      /^CPU\(s\):/ {printf "%-18s %s\n","Logical CPUs",$2}
      /^CPU max MHz/ {printf "%-18s %s MHz\n","Max MHz",$2}
      /^CPU min MHz/ {printf "%-18s %s MHz\n","Min MHz",$2}
    ' | sed 's/^[[:space:]]*//'
    have nproc && kv "nproc" "$(nproc)"
  else
    m=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2- | sed 's/^ //')
    [ -n "${m:-}" ] && kv "Model" "$m"
    c=$(grep -c ^processor /proc/cpuinfo 2>/dev/null || true); [ -n "${c:-}" ] && kv "Logical CPUs" "$c"
  fi
}

linux_memory(){
  section "Memory"
  if [ -r /proc/meminfo ]; then
    awk '
      function kv(k,v){printf "%-18s %s\n", k":", v}
      function h(k){split("KiB MiB GiB TiB",u," ");i=1;v=k+0;while(v>=1024&&i<4){v/=1024;i++}return sprintf("%.1f %s",v,u[i])}
      { gsub(/:[ \t]*/," ",$0); a[$1]=$2 }
      END{
        mt=a["MemTotal"]; mf=a["MemFree"]; mb=a["Buffers"]; mc=a["Cached"]; sr=a["SReclaimable"]; sh=a["Shmem"];
        ma=a["MemAvailable"]; if(ma==""||ma==0){ ma = mf + mb + mc + sr - sh }
        used = mt - ma
        kv("Total", h(mt)); kv("Used", h(used)); kv("Free", h(mf)); kv("Available", h(ma))
        st=a["SwapTotal"]; sf=a["SwapFree"]; if(st>0){kv("Swap Total",h(st));kv("Swap Used",h(st-sf));kv("Swap Free",h(sf))}
      }' /proc/meminfo
  fi
  if have dmidecode && [ "$(id -u)" -eq 0 ]; then
    spd=$(dmidecode -t memory | awk -F: '/Speed:/{gsub(/^[ \t]+/,"",$2); if($2!="Unknown") print $2}' | head -1)
    [ -n "${spd:-}" ] && kv "DIMM Speed" "$spd"
  fi
}

linux_mobo_bios(){
  section "Motherboard/BIOS"
  if have dmidecode && [ "$(id -u)" -eq 0 ]; then
    dmidecode -t baseboard -t bios | awk -F: '
      /Manufacturer:/ && !seen1++ {printf "%-18s %s\n","Board Vendor",$2}
      /Product Name:/ && !seen2++ {printf "%-18s %s\n","Board Model",$2}
      /^Version:/ && !seen3++ {printf "%-18s %s\n","Board Version",$2}
      /BIOS Vendor:/ {printf "%-18s %s\n","BIOS Vendor",$2}
      /BIOS Version:/ {printf "%-18s %s\n","BIOS Version",$2}
      /Release Date:/ {printf "%-18s %s\n","BIOS Date",$2}
    ' | sed 's/^[[:space:]]*//'
  else
    kv "Note" "Run as root with dmidecode for board/BIOS details"
  fi
}

linux_gpu(){
  section "Graphics"
  if have lspci; then
    lspci | grep -Ei 'vga|3d|display' | sed 's/^/ - /'
  fi
  if have nvidia-smi; then
    printf "\nNVIDIA\n"
    nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader
  fi
}

linux_storage(){
  section "Storage"
  have lsblk && lsblk -o NAME,SIZE,TYPE,MODEL,SERIAL,ROTA,TRAN,MOUNTPOINT -e7
  if have nvme; then
    printf "\nNVMe\n"; nvme list || true
  fi
  if have zpool; then
    printf "\nZFS Pools\n"; zpool list || true
    if zpool status -x >/dev/null 2>&1; then kv "ZFS Health" "all pools are healthy"; else printf "ZFS Status\n"; zpool status || true; fi
  fi
  if have smartctl; then
    printf "\nSMART (health)\n"
    for d in /dev/nvme[0-9]n1 /dev/sd[a-z] /dev/vd[a-z]; do
      [ -e "$d" ] || continue
      if smartctl -H "$d" >/dev/null 2>&1; then
        h=$(smartctl -H "$d" | awk -F: '/SMART overall-health/{gsub(/^[ \t]+/,"",$2); print $2}')
        [ -n "${h:-}" ] && printf " - %s: %s\n" "$d" "$h"
      fi
    done
  fi
}

linux_filesystems(){
  section "Filesystems"
  have df && df -hT -x tmpfs -x devtmpfs
}

linux_network(){
  section "Network"
  if have ip; then ip -br addr show; fi
  def=""
  if have ip; then
    def=$(ip route show default 2>/dev/null | awk 'NR==1{for(i=1;i<=NF;i++) if($i=="via") gw=$(i+1); for(i=1;i<=NF;i++) if($i=="dev") dev=$(i+1); if(gw||dev) printf("Default: via %s dev %s\n", gw, dev)}')
    [ -n "$def" ] && echo "$def"
  fi
  if command -v resolvectl >/dev/null 2>&1; then
    dns=$(resolvectl dns 2>/dev/null | sed 's/^/ - /')
    [ -n "$dns" ] && printf "DNS\n%s\n" "$dns"
  elif [ -r /etc/resolv.conf ]; then
    dns=$(awk '/^nameserver/{print " - "$2}' /etc/resolv.conf)
    [ -n "$dns" ] && printf "DNS\n%s\n" "$dns"
  fi
  if have lspci; then
    printf "\nPCIe NICs\n"
    lspci -Dvmm 2>/dev/null | awk '
      BEGIN{RS=""; FS="\n"}
      {cls=""; slot=""; vendor=""; device=""
       for(i=1;i<=NF;i++){
         if($i ~ /^Class:/){cls=$i}
         else if($i ~ /^Slot:/){slot=$i}
         else if($i ~ /^Vendor:/){vendor=$i}
         else if($i ~ /^Device:/){device=$i}
       }
       if(cls ~ /Ethernet controller|Network controller|Wireless controller/){
         gsub(/^Class:[ \t]*/,"",cls); gsub(/^Slot:[ \t]*/,"",slot)
         gsub(/^Vendor:[ \t]*/,"",vendor); gsub(/^Device:[ \t]*/,"",device)
         printf(" - %s %s %s\n", slot, vendor, device)
       }}'
  fi
}

linux_usb(){
  section "USB"
  if have lsusb; then lsusb; else kv "Note" "usbutils not installed"; fi
}

linux_audio(){
  section "Audio"
  if [ -r /proc/asound/cards ]; then
    awk '
      /^[[:space:]]*[0-9]+[[:space:]]*\[[^]]+\][[:space:]]*:/{
        line=$0
        match(line,/^[[:space:]]*([0-9]+)/,m); idx=m[1]
        match(line,/\[([^]]+)\]/,b); id=b[1]
        sub(/^.*:[[:space:]]*/,"",line)
        gsub(/^[[:space:]]+|[[:space:]]+$/,"",line)
        printf(" - card %s: %s [%s]\n", idx, line, id)
      }' /proc/asound/cards
  fi
  if have pactl; then pactl list short sinks 2>/dev/null || true
  elif have pw-cli; then pw-cli list-objects Node 2>/dev/null | grep -E "node.name|media.class" -A1 || true
  elif have aplay; then aplay -l 2>/dev/null || true
  fi
}

linux_power(){
  section "Power/Battery"
  if have upower; then
    bat=$(upower -e 2>/dev/null | grep -m1 BAT || true)
    if [ -n "${bat:-}" ]; then
      upower -i "$bat" | awk -F: '/state|percentage|time to|energy-full|energy-full-design|cycle count/ {gsub(/^[ \t]+/,"",$2); printf "%-18s %s\n",$1,$2}'
    else
      kv "Battery" "none detected"
    fi
  elif have acpi; then acpi -b || true
  else kv "Battery" "tooling not available"; fi
}

linux_temps(){
  if have sensors; then
    section "Temperatures"
    sensors 2>/dev/null | awk '
      BEGIN{skip=0}
      /^ucsi_source_psy_/ {skip=1; next}
      /^$/ {skip=0}
      !skip {print " " $0}
    '
  fi
}

mac_system(){
  section "System"
  kv "Hostname" "$(scutil --get ComputerName 2>/dev/null || hostname)"
  kv "OS" "$(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
  kv "Kernel" "$(uname -r)"
  kv "Uptime" "$(uptime | sed 's/^.*up //; s/,.*//')"
}

mac_prof(){ have system_profiler && system_profiler -detailLevel mini "$1" 2>/dev/null; }

mac_all(){
  section "Summary"
  kv "Host" "$(scutil --get ComputerName 2>/dev/null || hostname)"
  hw=$(system_profiler SPHardwareDataType 2>/dev/null | sed -n 's/^[[:space:]]*Model Name:[[:space:]]*//p; s/^[[:space:]]*Model Identifier:[[:space:]]*/Identifier: /p; s/^[[:space:]]*Memory:[[:space:]]*/Memory: /p' | paste -sd' | ' -)
  [ -n "$hw" ] && kv "Hardware" "$hw"
  mac_system
  section "Hardware"; mac_prof SPHardwareDataType
  section "Graphics/Displays"; mac_prof SPDisplaysDataType
  section "Storage"; mac_prof SPNVMeDataType; mac_prof SPSerialATADataType; mac_prof SPStorageDataType
  section "USB"; mac_prof SPUSBDataType
  section "Network"; mac_prof SPNetworkDataType
  section "Power/Battery"; mac_prof SPPowerDataType
  section "Audio"; mac_prof SPAudioDataType
}

main(){
  case "$(uname -s)" in
    Linux)
      linux_summary
      linux_system
      linux_cpu
      linux_memory
      linux_mobo_bios
      linux_gpu
      linux_storage
      linux_filesystems
      linux_network
      linux_usb
      linux_audio
      linux_power
      linux_temps
      ;;
    Darwin) mac_all ;;
    *) section "System"; kv "OS" "$(uname -a)";;
  esac
}

main
