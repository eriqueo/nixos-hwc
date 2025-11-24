SERVICE="podman-frigate"
CONTAINER="frigate"
API_URL="http://127.0.0.1:5001"

journal_file="$(mktemp)"
journal_err_file="$(mktemp)"
api_stats_file="$(mktemp)"
api_err_file="$(mktemp)"

print_section() {
  printf "\n===== %s =====\n" "$1"
}

print_issue() {
  printf "ISSUE: %s\n" "$1"
}

print_ok() {
  printf "OK: %s\n" "$1"
}

print_section "Service status"
service_status="$(systemctl is-active "$SERVICE" 2>/dev/null || echo "unknown")"
echo "systemctl is-active $SERVICE -> $service_status"
if [ "$service_status" != "active" ]; then
  print_issue "Service is not active. Check: systemctl status $SERVICE --no-pager"
fi

print_section "Container presence"
if sudo podman ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  print_ok "Container $CONTAINER is running"
else
  print_issue "Container $CONTAINER is not running"
fi

print_section "Container stats snapshot"
stats_output="$(sudo podman stats "$CONTAINER" --no-stream 2>&1)"
if [ $? -eq 0 ]; then
  echo "$stats_output"
else
  print_issue "podman stats failed: $stats_output"
fi

print_section "Container process tree"
top_output="$(sudo podman top "$CONTAINER" 2>&1)"
if [ $? -eq 0 ]; then
  echo "$top_output"
else
  print_issue "podman top failure: $top_output"
fi

print_section "Recent logs (last 30 minutes)"
journalctl -u "$SERVICE" --since "30 minutes ago" --no-pager >"$journal_file" 2>"$journal_err_file"
if [ -s "$journal_file" ]; then
  tail -n 80 "$journal_file"
else
  print_issue "journalctl returned no logs"
  if [ -s "$journal_err_file" ]; then
    cat "$journal_err_file"
  fi
fi

print_section "Log scan for warnings"
if [ -s "$journal_file" ]; then
  matches="$(grep -Ei 'error|warning|unprocessed recording|Too many unprocessed|detector failed|unable to open|rtsp' "$journal_file")"
  if [ -n "$matches" ]; then
    echo "$matches"
  else
    print_ok "No warnings detected by pattern scan"
  fi
else
  print_issue "No log file to scan"
fi

print_section "API health"
curl -fsS "$API_URL/api/stats" -o "$api_stats_file" 2>"$api_err_file"
if [ $? -eq 0 ]; then
  print_ok "API reachable at $API_URL/api/stats"
  if command -v jq >/dev/null 2>&1; then
    jq '.detectors' "$api_stats_file"
  else
    head -n 40 "$api_stats_file"
  fi
else
  print_issue "API unreachable"
  if [ -s "$api_err_file" ]; then
    cat "$api_err_file"
  fi
fi

print_section "Port checks"
for port in 5001 8554 8555; do
  if sudo ss -tulpn | grep -q ":$port"; then
    print_ok "Port $port listening"
    sudo ss -tulpn | grep ":$port"
  else
    print_issue "Port $port NOT listening"
  fi
done

print_section "Camera connectivity (optional)"
if [ -n "$CAM_TEST_URL" ]; then
  if command -v ffprobe >/dev/null 2>&1; then
    probe_out="$(ffprobe -hide_banner "$CAM_TEST_URL" 2>&1)"
    if [ $? -eq 0 ]; then
      print_ok "Camera reachable at CAM_TEST_URL"
    else
      print_issue "Camera unreachable"
      echo "$probe_out"
    fi
  else
    print_issue "ffprobe not installed"
  fi
else
  echo "CAM_TEST_URL not set"
fi

print_section "GPU health"
if command -v nvidia-smi >/dev/null 2>&1; then
  gpu_out="$(nvidia-smi 2>&1)"
  if echo "$gpu_out" | grep -qi "insufficient"; then
    print_issue "nvidia-smi permission error. Run script with sudo or adjust GPU permissions"
  else
    echo "$gpu_out"
  fi
else
  echo "nvidia-smi not found"
fi

print_section "High-level summary"
if [ -s "$journal_file" ]; then
  if grep -q 'Too many unprocessed recording' "$journal_file"; then
    print_issue "Recording backlog detected, likely detect/record pipeline overload"
  fi
  if grep -q '"" 400' "$journal_file"; then
    print_issue "Repeated empty HTTP 400s, likely a raw TCP health check hitting 5001"
  fi
  if grep -q '"GET /auth"' "$journal_file"; then
    print_issue "Requests to /auth returning 404, likely from a reverse-proxy or HA integration"
  fi
fi
if [ "$service_status" = "active" ]; then
  print_ok "Service podman-frigate is active"
fi
if sudo podman ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  print_ok "Container frigate is up"
fi

rm -f "$journal_file" "$journal_err_file" "$api_stats_file" "$api_err_file"

echo "Health script complete"
