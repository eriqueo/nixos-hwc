# domains/home/apps/hyprland/parts/scripts.nix
#
# HYPRLAND SCRIPTS - Window manager helper tools
# Pure script definitions for Hyprland session management
#
# DEPENDENCIES (Upstream):
#   - pkgs (Nixpkgs for writeShellScriptBin and tool dependencies)
#
# USED BY (Downstream):
#   - domains/home/apps/hyprland/sys.nix (imports and exposes as system packages)
#
# USAGE:
#   let scripts = import ./parts/scripts.nix { inherit pkgs lib; };
#   in { environment.systemPackages = scripts; }

{ pkgs, lib, osConfig ? {}, workspacePlan ? (import ./hardware.nix { inherit lib pkgs; }).workspacePlan, ... }:

with pkgs;

[
  #============================================================================
  # SMART WINDOW MOVE - Move within workspace, cross monitors at edges
  #============================================================================
  (writeShellScriptBin "hyprland-smart-move" ''
    #!/usr/bin/env bash
    set -euo pipefail

    DIRECTION="''${1:-r}"  # l, r, u, d

    # Get window position before move
    BEFORE=$(${hyprland}/bin/hyprctl activewindow -j)
    POS_BEFORE=$(echo "$BEFORE" | ${jq}/bin/jq -r '"\(.at[0]),\(.at[1])"')

    # Try to move within workspace
    ${hyprland}/bin/hyprctl dispatch "hl.dsp.window.move({direction='$DIRECTION'})"

    # Small delay for Hyprland to process
    sleep 0.05

    # Get window position after move
    AFTER=$(${hyprland}/bin/hyprctl activewindow -j)
    POS_AFTER=$(echo "$AFTER" | ${jq}/bin/jq -r '"\(.at[0]),\(.at[1])"')

    # If position unchanged, window was at edge - move to adjacent monitor
    if [[ "$POS_BEFORE" == "$POS_AFTER" ]]; then
      case "$DIRECTION" in
        l) ${hyprland}/bin/hyprctl dispatch 'hl.dsp.window.move({monitor="-1"})' ;;
        r) ${hyprland}/bin/hyprctl dispatch 'hl.dsp.window.move({monitor="+1"})' ;;
        u) ${hyprland}/bin/hyprctl dispatch 'hl.dsp.window.move({monitor="-1"})' ;;
        d) ${hyprland}/bin/hyprctl dispatch 'hl.dsp.window.move({monitor="+1"})' ;;
      esac
    fi
  '')

  #============================================================================
  # WORKSPACE OVERVIEW - Enhanced workspace selector with window previews
  #============================================================================
  (writeShellScriptBin "hyprland-workspace-overview" ''
    #!/usr/bin/env bash
    set -euo pipefail

    # Get all workspaces with their contents
    WORKSPACES=$(${hyprland}/bin/hyprctl workspaces -j | ${jq}/bin/jq -r '
      .[] |
      if .windows > 0 then
        "\(.id): \(.windows) windows - \(.lastwindowtitle // "empty")"
      else
        "\(.id): empty"
      end
    ' | sort -n)

    # Use wofi to select workspace
    SELECTED=$(echo "$WORKSPACES" | ${wofi}/bin/wofi --dmenu --prompt "Go to workspace:" --lines 10)

    if [[ -n "$SELECTED" ]]; then
      WORKSPACE_ID=$(echo "$SELECTED" | cut -d: -f1)
      ${hyprland}/bin/hyprctl dispatch "hl.dsp.focus({workspace='$WORKSPACE_ID'})"
      ${libnotify}/bin/notify-send "Workspace" "Switched to workspace $WORKSPACE_ID" -t 1000 -i desktop
    fi
  '')

  #============================================================================
  # MONITOR TOGGLE - Switch external monitor position (left/right)
  #============================================================================
  # No argument: flip the external screen's side and remember it for that screen
  # (keyed by its EDID description, so each desk keeps its own side).
  # `apply`: restore the remembered side (default right, the config default).
  # hyprland-monitor-listener runs it after config reloads, which discard
  # runtime monitor rules, and after hotplugs.
  (writeShellScriptBin "hyprland-monitor-toggle" ''
    #!/usr/bin/env bash
    set -euo pipefail

    MODE="''${1:-toggle}"
    if [[ "$MODE" != toggle && "$MODE" != apply ]]; then
      echo "usage: hyprland-monitor-toggle [apply]" >&2
      exit 64
    fi
    STATE_DIR="''${XDG_STATE_HOME:-$HOME/.local/state}/hypr/external-side"

    # Get monitor data once
    MONITOR_DATA=$(${hyprland}/bin/hyprctl monitors -j)

    # Identify laptop and external monitors. Physical outputs only: headless
    # outputs (the HWC-GAME stream capture) report no make.
    LAPTOP=$(echo "$MONITOR_DATA" | ${jq}/bin/jq -r '.[] | select(.make != "" and (.name | test("eDP|LVDS"))) | .name' | head -1)
    EXTERNAL=$(echo "$MONITOR_DATA" | ${jq}/bin/jq -r '.[] | select(.make != "" and (.name | test("eDP|LVDS") | not)) | .name' | head -1)

    if [[ -z "$EXTERNAL" || -z "$LAPTOP" ]]; then
      [[ "$MODE" == apply ]] && exit 0
      ${libnotify}/bin/notify-send "Monitor" "No external monitor detected" -t 2000 -i display
      exit 1
    fi

    DESCRIPTION=$(echo "$MONITOR_DATA" | ${jq}/bin/jq -r ".[] | select(.name==\"$EXTERNAL\") | .description")
    STATE="$STATE_DIR/$(printf '%s' "$DESCRIPTION" | ${coreutils}/bin/tr -c 'A-Za-z0-9._-' '_')"

    # The laptop at x=0 means the external screen is currently on the right.
    LAPTOP_POS=$(echo "$MONITOR_DATA" | ${jq}/bin/jq -r ".[] | select(.name==\"$LAPTOP\") | .x")
    if [[ $LAPTOP_POS -eq 0 ]]; then CURRENT=right; else CURRENT=left; fi
    if [[ "$MODE" == apply ]]; then
      SIDE=$(${coreutils}/bin/cat "$STATE" 2>/dev/null || echo right)
      [[ "$SIDE" == left ]] || SIDE=right
      [[ "$SIDE" == "$CURRENT" ]] && exit 0
    elif [[ "$CURRENT" == right ]]; then
      SIDE=left
    else
      SIDE=right
    fi

    # Get monitor specs (resolution@refresh,position,scale)
    LAPTOP_SPEC=$(echo "$MONITOR_DATA" | ${jq}/bin/jq -r ".[] | select(.name==\"$LAPTOP\") | \"\(.width)x\(.height)@\(.refreshRate | floor)\"")
    EXTERNAL_SPEC=$(echo "$MONITOR_DATA" | ${jq}/bin/jq -r ".[] | select(.name==\"$EXTERNAL\") | \"\(.width)x\(.height)@\(.refreshRate | floor)\"")
    LAPTOP_SCALE=$(echo "$MONITOR_DATA" | ${jq}/bin/jq -r ".[] | select(.name==\"$LAPTOP\") | .scale")
    EXTERNAL_SCALE=$(echo "$MONITOR_DATA" | ${jq}/bin/jq -r ".[] | select(.name==\"$EXTERNAL\") | .scale")

    # Calculate effective widths (accounting for scale)
    LAPTOP_WIDTH=$(echo "$MONITOR_DATA" | ${jq}/bin/jq -r ".[] | select(.name==\"$LAPTOP\") | (.width / .scale | floor)")
    EXTERNAL_WIDTH=$(echo "$MONITOR_DATA" | ${jq}/bin/jq -r ".[] | select(.name==\"$EXTERNAL\") | (.width / .scale | floor)")

    if [[ "$SIDE" == left ]]; then
      # Move external to left (apply both rules in one Lua request)
      ${hyprland}/bin/hyprctl eval "hl.monitor({output='$EXTERNAL',mode='$EXTERNAL_SPEC',position='0x0',scale=$EXTERNAL_SCALE}); hl.monitor({output='$LAPTOP',mode='$LAPTOP_SPEC',position='$((EXTERNAL_WIDTH))x0',scale=$LAPTOP_SCALE})"
    else
      # Move external to right
      ${hyprland}/bin/hyprctl eval "hl.monitor({output='$LAPTOP',mode='$LAPTOP_SPEC',position='0x0',scale=$LAPTOP_SCALE}); hl.monitor({output='$EXTERNAL',mode='$EXTERNAL_SPEC',position='$((LAPTOP_WIDTH))x0',scale=$EXTERNAL_SCALE})"
    fi

    if [[ "$MODE" == toggle ]]; then
      ${coreutils}/bin/mkdir -p "$STATE_DIR"
      printf '%s\n' "$SIDE" > "$STATE.new" && ${coreutils}/bin/mv "$STATE.new" "$STATE"
      ${libnotify}/bin/notify-send "Monitor" "External on $SIDE" -t 1500 -i display
    fi

    # Restart waybar to pick up monitor changes
    ${systemd}/bin/systemctl --user restart waybar
  '')

  #============================================================================
  # SYSTEM HEALTH CHECKER - Monitor disk, memory, CPU temp, and services
  #============================================================================
  (writeShellScriptBin "hyprland-system-health-checker" ''
    #!/usr/bin/env bash
    set -euo pipefail

    # Check disk space
    DISK_USAGE=$(${coreutils}/bin/df / | ${gawk}/bin/awk 'NR==2 {print int($5)}' | sed 's/%//')
    if [[ $DISK_USAGE -gt 90 ]]; then
      ${libnotify}/bin/notify-send "System Warning" "Disk usage is at $DISK_USAGE%!" -u critical -i dialog-warning
    fi

    # Check memory usage
    MEM_USAGE=$(${procps}/bin/free | ${gnugrep}/bin/grep Mem | ${gawk}/bin/awk '{printf "%.0f", $3/$2 * 100.0}')
    if [[ $MEM_USAGE -gt 90 ]]; then
      ${libnotify}/bin/notify-send "System Warning" "Memory usage is at $MEM_USAGE%!" -u critical -i dialog-warning
    fi

    # Check CPU temperature
    TEMP=$(${lm_sensors}/bin/sensors 2>/dev/null | ${gnugrep}/bin/grep -E "(Core 0|Tctl)" | head -1 | ${gawk}/bin/awk '{print $3}' | sed 's/+//;s/°C.*//' | cut -d'.' -f1 || echo "0")
    if [[ $TEMP -gt 80 ]]; then
      ${libnotify}/bin/notify-send "System Warning" "CPU temperature is $TEMP°C!" -u critical -i dialog-warning
    fi

    # Check if waybar is running
    if ! ${procps}/bin/pgrep -f waybar > /dev/null; then
      ${libnotify}/bin/notify-send "System Info" "Waybar is not running, attempting restart..." -i dialog-information
      ${systemd}/bin/systemctl --user restart waybar
    fi

    # If all checks pass, show success
    ${libnotify}/bin/notify-send "System Health" "All systems nominal ✓\nDisk: $DISK_USAGE% | Memory: $MEM_USAGE% | CPU: $TEMP°C" -t 3000 -i emblem-ok-symbolic
  '')

  #============================================================================
  # WORKSPACE SWITCH - Monitor-aware switch with optional linked-mode sync
  #============================================================================
  (writeShellScriptBin "hwc-workspace-switch" ''
    #!/usr/bin/env bash
    set -euo pipefail

    MOVE=0
    if [[ "''${1:-}" == --move ]]; then MOVE=1; shift; fi
    SLOT="''${1:?slot required (${lib.concatMapStringsSep "," toString workspacePlan.slots})}"
    STATE_FILE="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hwc-workspace-link"

    # Capture focused monitor before any dispatch
    FOCUSED=$(${hyprland}/bin/hyprctl monitors -j | ${jq}/bin/jq -r '.[] | select(.focused) | .name')

    # Always switch current monitor normally
    case "$SLOT" in ${lib.concatMapStringsSep "|" toString workspacePlan.slots}) ;; *) exit 64 ;; esac
    TARGET=$SLOT
    if [[ ! "$FOCUSED" =~ ^(eDP|LVDS) ]]; then TARGET=$((SLOT + ${toString workspacePlan.externalOffset})); fi
    if [[ "$MOVE" == 1 ]]; then
      ${hyprland}/bin/hyprctl dispatch "hl.dsp.window.move({workspace='$TARGET'})"
      exit
    fi
    ${hyprland}/bin/hyprctl dispatch "hl.dsp.focus({workspace='$TARGET'})"

    # Linked mode: sync the other monitor to the same slot
    if [[ -f "$STATE_FILE" ]]; then
      MONITORS=$(${hyprland}/bin/hyprctl monitors -j)
      EXTERNAL=$(echo "$MONITORS" | ${jq}/bin/jq -r '.[] | select(.make != "" and (.name | test("^(eDP|LVDS)") | not)) | .name' | head -1)
      if [[ -z "$EXTERNAL" ]]; then
        exit 0  # Single monitor — nothing to sync
      fi

      if [[ "$FOCUSED" =~ ^(eDP|LVDS) ]]; then
        OTHER="$EXTERNAL"
        TARGET_WS=$((SLOT + ${toString workspacePlan.externalOffset}))
      else
        OTHER=$(echo "$MONITORS" | ${jq}/bin/jq -r '.[] | select(.name | test("^(eDP|LVDS)")) | .name' | head -1)
        TARGET_WS=$SLOT
      fi

      # Focus the other monitor first so the workspace dispatch lands there (not here)
      ${hyprland}/bin/hyprctl dispatch "hl.dsp.focus({monitor='$OTHER'})"
      ${hyprland}/bin/hyprctl dispatch "hl.dsp.focus({workspace='$TARGET_WS'})"
      ${hyprland}/bin/hyprctl dispatch "hl.dsp.focus({monitor='$FOCUSED'})"
    fi
  '')

  # NOTE: `hyprland-keybinds-viewer` used to live here, reading `hyprctl binds -j`.
  # It has moved to the HOME lane (parts/keybinds-viewer.nix, wired in index.nix)
  # for two reasons, both permanent:
  #   1. `hyprctl binds -j` emits MALFORMED JSON in Hyprland 0.56.0 — keys and
  #      values are misaligned (`"keycode": RETURN`, `"allow_input_capture": ,`)
  #      — so jq failed to parse and the viewer silently showed nothing.
  #   2. It could only ever print `exec hyprland-monitor-toggle`, never
  #      "Swap external monitor side". Descriptions do not exist at runtime.
  # The replacement renders from parts/keybinds.nix at build time and is themed
  # from hwc.home.theme.colors, which the system lane cannot read.

  #============================================================================
  # REFINERY INTAKE - pop a textbox, POST the sentence to the refinery /intake
  #============================================================================
  (writeShellScriptBin "refinery-intake" ''
    #!/usr/bin/env bash
    set -euo pipefail
    URL="''${REFINERY_INTAKE_URL:-https://refinery.hwc.iheartwoodcraft.com/intake}"
    # Empty stdin → wofi --dmenu becomes a free-text entry; Enter returns the typed line.
    idea=$(${wofi}/bin/wofi --dmenu --prompt "Refinery intake" < /dev/null)
    [ -n "$idea" ] || exit 0
    if ${curl}/bin/curl -fsS -X POST --data-urlencode "text=$idea" "$URL" >/dev/null; then
      ${libnotify}/bin/notify-send "🛠 Refinery" "Intake queued: $idea"
    else
      ${libnotify}/bin/notify-send -u critical "🛠 Refinery" "Intake failed (is the board up?)"
    fi
  '')
]