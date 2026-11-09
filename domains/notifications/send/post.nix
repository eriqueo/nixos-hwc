# Shared POST and delivery-result handling for both notification CLIs.
# cli.nix owns human arguments; notify-scripts.nix owns event adapters.
# Neither can own this transport without coupling the other CLI to its grammar.
{ pkgs }:
pkgs.writeShellApplication {
  name = "hwc-notify-post";
  runtimeInputs = [ pkgs.curl pkgs.jq ];
  text = ''
    response=$(curl -sS --max-time "$2" -w '\n%{http_code}' \
      -X POST -H 'content-type: application/json' --data-binary @- "$1/notify") || exit 1
    status="''${response##*$'\n'}"
    body="''${response%$'\n'*}"
    printf '%s\n' "$body"
    if [ "$status" = 200 ] && printf '%s' "$body" | jq -e '
      type == "object" and
      (.attempted | type == "number") and (.attempted > 0) and
      (.attempted == (.attempted | floor)) and
      (.succeeded == .attempted) and (.failed == 0)
    ' >/dev/null 2>&1; then
      exit 0
    fi
    printf '%s' "$body" | jq -r '
      if (.attempted | type) == "number" and (.succeeded | type) == "number" then
        "Notification delivery incomplete: \(.succeeded)/\(.attempted) channels accepted. Inspect hwc-notify recent; do not resend successful channels automatically."
      else "Notification response invalid or rejected. Inspect hwc-notify recent before retrying." end
    ' >&2 2>/dev/null || echo "Notification response is not valid JSON." >&2
    exit 1
  '';
}
