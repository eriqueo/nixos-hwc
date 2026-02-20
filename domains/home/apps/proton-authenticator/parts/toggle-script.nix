{ pkgs }:

pkgs.writeShellScriptBin "proton-authenticator-toggle" ''
  #!/usr/bin/env bash
  # Toggle Proton Authenticator window visibility in Hyprland
  # - If no window: launch it (with fixes for blank/white screen on Wayland)
  # - If window exists:
  #   - On current workspace → move silently to scratchpad (workspace 8)
  #   - On another workspace → bring to current workspace + focus

  set -euo pipefail

  WINDOW_CLASS="Proton-authenticator"
  SCRATCHPAD_WS=8

  # Get window address if it exists (only one expected)
  WINDOW_ADDR=$( \
    ${pkgs.hyprland}/bin/hyprctl clients -j \
    | ${pkgs.jq}/bin/jq -r --arg class "$WINDOW_CLASS" \
      '.[] | select(.class == $class) | .address' \
  )

  if [ -z "$WINDOW_ADDR" ]; then
    # No window → launch with required env vars for rendering compatibility
    # WEBKIT_DISABLE_DMABUF_RENDERER=1 is the main fix for white/blank screen (Proton official + community)
    # GDK_BACKEND=x11 avoids Wayland protocol errors/crashes on Hyprland
    echo "Launching Proton Authenticator..." >&2
    env WEBKIT_DISABLE_DMABUF_RENDERER=1 GDK_BACKEND=x11 \
      ${pkgs.proton-authenticator}/bin/proton-authenticator &>/dev/null &
    # Optional: disown to detach fully
    disown
  else
    # Window exists → get its workspace
    WINDOW_WS=$( \
      ${pkgs.hyprland}/bin/hyprctl clients -j \
      | ${pkgs.jq}/bin/jq -r --arg addr "$WINDOW_ADDR" \
        '.[] | select(.address == $addr) | .workspace.id' \
    )

    CURRENT_WS=$(${pkgs.hyprland}/bin/hyprctl activeworkspace -j | ${pkgs.jq}/bin/jq -r '.id')

    if [ "$CURRENT_WS" = "$WINDOW_WS" ]; then
      # On current WS → hide (move to scratchpad workspace silently)
      echo "Hiding Proton Authenticator (to WS $SCRATCHPAD_WS)..." >&2
      ${pkgs.hyprland}/bin/hyprctl dispatch movetoworkspacesilent "$SCRATCHPAD_WS",address:"$WINDOW_ADDR"
    else
      # On different WS → bring here and focus
      echo "Bringing Proton Authenticator to current workspace..." >&2
      ${pkgs.hyprland}/bin/hyprctl dispatch movetoworkspace "$CURRENT_WS",address:"$WINDOW_ADDR"
      ${pkgs.hyprland}/bin/hyprctl dispatch focuswindow address:"$WINDOW_ADDR"
    fi
  fi
''
