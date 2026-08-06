# domains/home/apps/hyprland/parts/session.nix
{
  config,
  lib,
  pkgs,
  card ? "",
  osConfig ? {},
  ...
}: let
  cur = config.hwc.home.theme.cursor or {};
  xc = cur.xcursor or {};
  hc = cur.hyprcursor or {};
  cursorSize = toString (cur.size or 24);

  pkgByName = name:
    if lib.hasAttr name pkgs
    then builtins.getAttr name pkgs
    else pkgs.adwaita-icon-theme;
  xcPkg = pkgByName (xc.package or "adwaita-icon-theme");

  xcursorName = xc.name or "Adwaita";
  hyprcursorName = hc.name or xcursorName;

  hyprcursorSource =
    if (hc ? assetPathRel)
    then ../../.. + "/${hc.assetPathRel}"
    else null;

  #============================================================================
  # AUTOSTART — apps and services launched once when Hyprland starts.
  #
  # To add/remove a startup item, just edit this list.
  #   - { cmd = "foo"; }                  → background service, no workspace
  #   - { cmd = "foo"; workspace = N; }   → window pinned to workspace N silently
  #
  # Workspace pinning uses Hyprland's native `[workspace N silent]` exec rule,
  # which is race-free (unlike a startup script that dispatches workspaces).
  #============================================================================
  autostart = [
    # Background / one-shot services
    {cmd = "xfconfd";}
    {cmd = "hyprctl setcursor ${hyprcursorName} ${cursorSize}";}
    {cmd = "swaybg -i ${../../../theme/nord-mountains.jpg} -m fill";}
    {cmd = "wl-paste --watch cliphist store";}

    # Applications (pinned to workspaces)
    {
      cmd = "gpu-launch chromium-hwc";
      workspace = 1;
    }
    {
      cmd = "kitty";
      workspace = 2;
    }
    {
      cmd = "gpu-launch chromium-hwc --app=https://app.jobtread.com";
      workspace = 4;
    }
    {
      cmd = "proton-mail";
      workspace = 8;
    }
  ];

  mkExec = a:
    if a ? workspace
    then "[workspace ${toString a.workspace} silent] ${a.cmd}"
    else a.cmd;

  #============================================================================
  # KEYBIND LEGEND VIEWER (SUPER+?) — the session package for the card that
  # parts/theme.nix paints from parts/behavior.nix's records. Floated by the
  # `hypr-keybinds` windowrule in behavior.nix.
  #============================================================================
  cardFile = pkgs.writeText "hyprland-keybinds-card" (card + "\n");

  keybindsViewer = pkgs.writeShellScriptBin "hyprland-keybinds-viewer" ''
    #!/usr/bin/env bash
    set -euo pipefail

    # Toggle: a second SUPER+? dismisses the card instead of stacking another
    # window. Without this, holding the chord buries the desktop in legends.
    if ${pkgs.hyprland}/bin/hyprctl clients -j 2>/dev/null \
      | ${pkgs.jq}/bin/jq -e '.[] | select(.class == "hypr-keybinds")' >/dev/null 2>&1; then
      ${pkgs.hyprland}/bin/hyprctl dispatch closewindow class:hypr-keybinds
      exit 0
    fi

    # -R renders the baked ANSI colours; less gives `/` search and `q` to close.
    exec ${pkgs.kitty}/bin/kitty \
      --class hypr-keybinds \
      --title "Hyprland Keybinds" \
      -e ${pkgs.less}/bin/less -R --mouse ${cardFile}
  '';
in {
  # FLAT KEYS (NO nested `settings = {}`!)
  execOnce = map mkExec autostart;

  env = [
    "HYPRCURSOR_THEME,${hyprcursorName}"
    "HYPRCURSOR_SIZE,${cursorSize}"
    "XCURSOR_THEME,${xcursorName}"
    "XCURSOR_SIZE,${cursorSize}"
    "XCURSOR_PATH,${xcPkg}/share/icons"
    # "HWC_SCREENSHOTS_DIR,${screenshotsDir}"
  ];

  packages = [keybindsViewer];

  files = lib.mkIf (hyprcursorSource != null) {
    ".local/share/icons/${hyprcursorName}".source = hyprcursorSource;
  };
}
