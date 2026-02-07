{ pkgs }:

pkgs.writeShellScriptBin "proton-authenticator-toggle" ''
  # Toggle Proton Authenticator window visibility
  # If window exists, focus it or hide it. If not, launch it.

  WINDOW_CLASS="Proton Pass Authenticator"

  # Check if proton-authenticator window exists
  WINDOW_INFO=$(${pkgs.hyprland}/bin/hyprctl clients -j | ${pkgs.jq}/bin/jq -r ".[] | select(.class == \"$WINDOW_CLASS\") | .address")

  if [ -z "$WINDOW_INFO" ]; then
    # Window doesn't exist, launch it
    ${pkgs.proton-authenticator}/bin/proton-authenticator &
  else
    # Window exists, check if it's on the current workspace
    CURRENT_WORKSPACE=$(${pkgs.hyprland}/bin/hyprctl activeworkspace -j | ${pkgs.jq}/bin/jq -r ".id")
    WINDOW_WORKSPACE=$(${pkgs.hyprland}/bin/hyprctl clients -j | ${pkgs.jq}/bin/jq -r ".[] | select(.class == \"$WINDOW_CLASS\") | .workspace.id")

    if [ "$CURRENT_WORKSPACE" = "$WINDOW_WORKSPACE" ]; then
      # Window is on current workspace, minimize it by moving to workspace 7 (scratchpad-like)
      ${pkgs.hyprland}/bin/hyprctl dispatch movetoworkspacesilent 7,address:$WINDOW_INFO
    else
      # Window is on different workspace, bring it to current workspace and focus
      ${pkgs.hyprland}/bin/hyprctl dispatch movetoworkspace "$(${pkgs.hyprland}/bin/hyprctl activeworkspace -j | ${pkgs.jq}/bin/jq -r .id),address:$WINDOW_INFO"
      ${pkgs.hyprland}/bin/hyprctl dispatch focuswindow address:$WINDOW_INFO
    fi
  fi
''
