#!/usr/bin/env bash
set -euo pipefail

TS_DOMAIN="${TS_DOMAIN:-hwc.ocelot-wahoo.ts.net}"
TIMEOUT="${TIMEOUT:-6}"
INSECURE="${INSECURE:-0}"

# Use '|' as a safe delimiter so http://... doesn't break parsing.
# name|mode|public_path_or_port|upstream_url|unit_hint
SERVICES=(
  "jellyfin|subpath|/jellyfin|http://127.0.0.1:8096|jellyfin"
  "jellyseerr|port|5543|http://127.0.0.1:5055|jellyseerr"
  "navidrome|subpath|/music|http://127.0.0.1:4533|navidrome"
  "sonarr|subpath|/sonarr|http://127.0.0.1:8989|sonarr"
  "radarr|subpath|/radarr|http://127.0.0.1:7878|radarr"
  "lidarr|subpath|/lidarr|http://127.0.0.1:8686|lidarr"
  "prowlarr|subpath|/prowlarr|http://127.0.0.1:9696|prowlarr"
  "sabnzbd|subpath|/sab|http://127.0.0.1:8081|sabnzbd"
  "qbittorrent|subpath|/qbt|http://127.0.0.1:8080|qbittorrent"
  "couchdb|subpath|/sync|http://127.0.0.1:5984|couchdb"
  "immich|port|7443|http://127.0.0.1:2283|immich"
  "frigate|port|5443|http://127.0.0.1:5000|frigate"
  "slskd|port|8443|http://127.0.0.1:5030|slskd"
)

have() { command -v "$1" >/dev/null 2>&1; }

curl_flags=(-sS --max-time "${TIMEOUT}" -L -o /dev/null -w "%{http_code}\t%{remote_ip}\t%{remote_port}\t%{content_type}\t%{time_total}\t%{url_effective}\n")
[[ "${INSECURE}" == "1" ]] && curl_flags+=(--insecure)

hdr()   { printf "\n=== %s ===\n" "$1"; }
line()  { printf "%s\n" "$*"; }
table_h(){ printf "%-12s %-7s %-40s %-8s %-9s %-24s\n" "TARGET" "MODE" "URL" "HTTP" "TIME(s)" "NOTE"; }
table_r(){ printf "%-12s %-7s %-40s %-8s %-9s %-24s\n" "$@"; }

hdr "System"
line "Date: $(date -Is)"
line "User: $(id -un) on $(hostnamectl --static 2>/dev/null || hostname)"
line "Kernel: $(uname -r)"
line "NixOS: $(. /etc/os-release; echo "$VERSION $VERSION_CODENAME" 2>/dev/null || true)"

hdr "Tailscale"
if have tailscale; then
  line "tailscaled: $(systemctl is-active tailscaled || true)"
  line "DNS for ${TS_DOMAIN}: $(getent hosts "${TS_DOMAIN}" | awk '{print $1}' | paste -sd, - || echo 'unresolved')"
else
  line "tailscale not installed"
fi

hdr "Caddy"
line "caddy: $(systemctl is-active caddy || true)"
line "listeners (443 + port-mode):"
ss -tulpn 2>/dev/null | awk 'NR==1 || $5 ~ /:443$|:7443$|:5443$|:8443$/'
line "recent errors:"
journalctl -u caddy -p err -n 5 --no-pager 2>/dev/null || true

probe() {
  local label="$1" mode="$2" url="$3"
  local out http ip rport ctype ttime
  out="$(curl "${curl_flags[@]}" "$url" || true)"
  http="$(awk -F'\t' '{print $1}' <<< "$out")"
  ip="$(awk -F'\t' '{print $2}' <<< "$out")"
  rport="$(awk -F'\t' '{print $3}' <<< "$out")"
  ctype="$(awk -F'\t' '{print $4}' <<< "$out")"
  ttime="$(awk -F'\t' '{print $5}' <<< "$out")"
  table_r "$label" "$mode" "$url" "$http" "$ttime" "${ip}:${rport} ${ctype}"
}

hdr "Through Caddy"
table_h
for s in "${SERVICES[@]}"; do
  IFS='|' read -r name mode pub upstream unit <<< "$s"
  if [[ "$mode" == "subpath" ]]; then
    probe "$name" "$mode" "https://${TS_DOMAIN}${pub}"
  else
    probe "$name" "$mode" "https://${TS_DOMAIN}:${pub}/"
  fi
done

hdr "Local upstreams"
printf "%-12s %-7s %-28s %-8s %-9s %-24s\n" "TARGET" "MODE" "UPSTREAM" "HTTP" "TIME(s)" "NOTE"
for s in "${SERVICES[@]}"; do
  IFS='|' read -r name mode pub upstream unit <<< "$s"
  out="$(curl "${curl_flags[@]}" "$upstream" || true)"
  http="$(awk -F'\t' '{print $1}' <<< "$out")"
  ttime="$(awk -F'\t' '{print $5}' <<< "$out")"
  table_r "$name" "local" "$upstream" "$http" "$ttime" ""
done

hdr "Systemd units (best-effort detection)"
# Try explicit unit names first, then fuzzy match against list-units
mapfile -t ALL_UNITS < <(systemctl list-units --type=service --all --no-legend | awk '{print $1}')
for s in "${SERVICES[@]}"; do
  IFS='|' read -r name mode pub upstream unit <<< "$s"
  guessed="podman-${unit}.service"
  status=""
  if systemctl status "$guessed" &>/dev/null; then
    status="$(systemctl is-active "$guessed" 2>/dev/null)"
    printf "%-12s %s (%s)\n" "$name" "$status" "$guessed"
  else
    # fuzzy fallback
    match="$(printf "%s\n" "${ALL_UNITS[@]}" | rg -i "(podman-)?${unit}(\.service)?$" -n --no-line-number | head -1 || true)"
    if [[ -n "$match" ]]; then
      status="$(systemctl is-active "$match" 2>/dev/null || true)"
      printf "%-12s %s (%s)\n" "$name" "$status" "$match"
    else
      printf "%-12s %s\n" "$name" "unknown (no unit found)"
    fi
  fi
done

hdr "Common pitfalls snapshot"
line "Caddy binding conflicts (10m):"
journalctl -u caddy --since "10 min ago" --no-pager | rg -i "bind: address already in use|cannot listen" || true
line "TLS for ${TS_DOMAIN}:"
if have openssl; then
  echo | openssl s_client -connect "${TS_DOMAIN}:443" -servername "${TS_DOMAIN}" 2>/dev/null | awk '/subject=|issuer=|DNS:/{print}' | head -6 || true
fi

hdr "Exit summary"
fail=0
for s in "${SERVICES[@]}"; do
  IFS='|' read -r name mode pub upstream unit <<< "$s"
  if [[ "$mode" == "subpath" ]]; then
    code="$(curl -sS --max-time "${TIMEOUT}" -L -o /dev/null -w "%{http_code}" "https://${TS_DOMAIN}${pub}" || echo "000")"
  else
    code="$(curl -sS --max-time "${TIMEOUT}" -L -o /dev/null -w "%{http_code}" "https://${TS_DOMAIN}:${pub}/" || echo "000")"
  fi
  if [[ ! "$code" =~ ^(2|3|401) ]]; then
    echo "FAIL ${name} (${mode}) -> ${code}"
    fail=1
  fi
done
exit "$fail"
