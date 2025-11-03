#!/usr/bin/env bash
set -euo pipefail

TS_DOMAIN="${TS_DOMAIN:-hwc.ocelot-wahoo.ts.net}"
TIMEOUT="${TIMEOUT:-6}"
INSECURE="${INSECURE:-0}"

curl_flags=(-sS --max-time "${TIMEOUT}" -L -o /dev/null -w "%{http_code}\t%{remote_ip}\t%{remote_port}\t%{content_type}\t%{time_total}\t%{url_effective}\n")
if [[ "${INSECURE}" == "1" ]]; then curl_flags+=(--insecure); fi

services_subpath=(
  "jellyfin:/jellyfin:http://127.0.0.1:8096:podman-jellyfin.service"
  "jellyseerr:/jellyseerr:http://127.0.0.1:5055:podman-jellyseerr.service"
  "navidrome:/music:http://127.0.0.1:4533:podman-navidrome.service"
  "sonarr:/sonarr:http://127.0.0.1:8989:podman-sonarr.service"
  "radarr:/radarr:http://127.0.0.1:7878:podman-radarr.service"
  "lidarr:/lidarr:http://127.0.0.1:8686:podman-lidarr.service"
  "prowlarr:/prowlarr:http://127.0.0.1:9696:podman-prowlarr.service"
  "sabnzbd:/sab:http://127.0.0.1:8081:podman-sabnzbd.service"
  "qbittorrent:/qbt:http://127.0.0.1:8080:podman-qbittorrent.service"
  "couchdb:/sync:http://127.0.0.1:5984:podman-couchdb.service"
)

services_portmode=(
  "immich:7443:http://127.0.0.1:2283:podman-immich.service"
  "frigate:5443:http://127.0.0.1:5000:podman-frigate.service"
  "slskd:8443:http://127.0.0.1:5030:podman-slskd.service"
)

have() { command -v "$1" >/dev/null 2>&1; }

print_hdr() {
  printf "\n=== %s ===\n" "$1"
}

line() { printf "%s\n" "$*"; }

colhdr() {
  printf "% -12s % -7s % -40s % -8s % -9s % -20s\n" "TARGET" "MODE" "URL" "HTTP" "TIME(s)" "NOTE"
}

row() {
  local tgt="$1" mode="$2" url="$3" code="$4" tt="$5" note="$6"
  printf "% -12s % -7s % -40s % -8s % -9s % -20s\n" "$tgt" "$mode" "$url" "$code" "$tt" "$note"
}

print_hdr "System"
line "Date: $(date -Is)"
line "User: $(id -un) on $(hostnamectl --static 2>/dev/null || hostname)"
line "Kernel: $(uname -r)"
line "NixOS: $(grep -o 'VERSION=.*' /etc/os-release | cut -d= -f2 | tr -d '"' || true)"

print_hdr "Tailscale"
if have tailscale; then
  line "tailscaled: $(systemctl is-active tailscaled || true)"
  line "ts status (short):"
  tailscale status --json 2>/dev/null | jq -r '.Self | "Self: \(.HostName)  \(.TailscaleIPs | join(','))"' 2>/dev/null || tailscale status 2>/dev/null || true
  line "DNS for ${TS_DOMAIN}: $(getent hosts "${TS_DOMAIN}" | awk '{print $1}' | paste -sd, - || echo 'unresolved')"
else
  line "tailscale not installed"
fi

print_hdr "Caddy"
line "caddy: $(systemctl is-active caddy || true)"
line "listeners (443, port-mode):"
ss -tulpn 2>/dev/null | awk 'NR==1 || $5 ~ /:443$|:7443$|:5443$|:8443$/' || true
line "recent errors:"
journalctl -u caddy -p err -n 5 --no-pager 2>/dev/null || true

probe_url() {
  local label="$1" mode="$2" url="$3"
  local out http ip rport ctype ttime eff
  out="$(curl "${curl_flags[@]}" "$url" || true)"
  http="$(awk -F'\t' '{print $1}' <<< "$out")"
  ip="$(awk -F'\t' '{print $2}' <<< "$out")"
  rport="$(awk -F'\t' '{print $3}' <<< "$out")"
  ctype="$(awk -F'\t' '{print $4}' <<< "$out")"
  ttime="$(awk -F'\t' '{print $5}' <<< "$out")"
  eff="$(awk -F'\t' '{print $6}' <<< "$out")"
  local note="${ip}:${rport} ${ctype}"
  row "$label" "$mode" "$url" "$http" "$ttime" "$note"
}

print_hdr "Through Caddy (subpaths on https://${TS_DOMAIN})"
colhdr
for s in "${services_subpath[@]}"; do
  IFS=: read -r name path upstream unit <<< "$s"
  probe_url "$name" "subpath" "https://${TS_DOMAIN}${path}"
done

print_hdr "Through Caddy (port-mode https://${TS_DOMAIN}:PORT)"
colhdr
for s in "${services_portmode[@]}"; do
  IFS=: read -r name port upstream unit <<< "$s"
  probe_url "$name" "port" "https://${TS_DOMAIN}:${port}/"
done

print_hdr "Local upstreams (localhost)"
printf "% -12s % -7s % -24s % -8s % -9s % -20s\n" "TARGET" "MODE" "UPSTREAM" "HTTP" "TIME(s)" "NOTE"
for s in "${services_subpath[@]}"; do
  IFS=: read -r name path upstream unit <<< "$s"
  out="$(curl "${curl_flags[@]}" "$upstream" || true)"
  http="$(awk -F'\t' '{print $1}' <<< "$out")"
  ttime="$(awk -F'\t' '{print $5}' <<< "$out")"
  row "$name" "local" "$upstream" "$http" "$ttime" "$unit"
done
for s in "${services_portmode[@]}"; do
  IFS=: read -r name port upstream unit <<< "$s"
  out="$(curl "${curl_flags[@]}" "$upstream" || true)"
  http="$(awk -F'\t' '{print $1}' <<< "$out")"
  ttime="$(awk -F'\t' '{print $5}' <<< "$out")"
  row "$name" "local" "$upstream" "$http" "$ttime" "$unit"
done

print_hdr "Systemd units (expected containers)"
for s in "${services_subpath[@]}"; do
  IFS=: read -r name path upstream unit <<< "$s"
  printf "% -12s %s\n" "$name" "$(systemctl is-active "$unit" 2>/dev/null || echo unknown)"
done
for s in "${services_portmode[@]}"; do
  IFS=: read -r name port upstream unit <<< "$s"
  printf "% -12s %s\n" "$name" "$(systemctl is-active "$unit" 2>/dev/null || echo unknown)"
done

print_hdr "Common pitfalls snapshot"
line "Caddy binding conflicts:"
journalctl -u caddy --since "10 min ago" --no-pager | grep -E "bind: address already in use|cannot listen" || true
line "TLS for ${TS_DOMAIN} quick check:"
if have openssl; then
  echo | openssl s_client -connect "${TS_DOMAIN}:443" -servername "${TS_DOMAIN}" 2>/dev/null | awk '/subject=|issuer=|DNS:/{print}' | head -n 6 || true
fi

print_hdr "Exit summary"
fail=0
for s in "${services_subpath[@]}"; do
  IFS=: read -r name path upstream unit <<< "$s"
  code="$(curl -sS --max-time "${TIMEOUT}" -L -o /dev/null -w "%{http_code}" "https://${TS_DOMAIN}${path}" || echo "000")"
  [[ "$code" =~ ^2|3|401$ ]] || { echo "FAIL ${name} subpath -> ${code}"; fail=1; }
done
for s in "${services_portmode[@]}"; do
  IFS=: read -r name port upstream unit <<< "$s"
  code="$(curl -sS --max-time "${TIMEOUT}" -L -o /dev/null -w "%{http_code}" "https://${TS_DOMAIN}:${port}/" || echo "000")"
  [[ "$code" =~ ^2|3|401$ ]] || { echo "FAIL ${name} port:${port} -> ${code}"; fail=1; }
done
exit "$fail"
