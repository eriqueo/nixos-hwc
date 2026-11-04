# domains/home/apps/hyprland/index.nix
{ config, lib, pkgs, inputs, osConfig ? {}, screenshotRoot ? null, ... }:
let
  cfg = config.hwc.home.apps.hyprland;
  hmLib = import ../../../lib/hm.nix { inherit lib; };
  isNixOSHost = hmLib.isNixOSHost osConfig;
  osCfg = hmLib.osCfgOr osConfig;
  eglVendorLibraryFilenames = lib.attrByPath
    [ "environment" "sessionVariables" "__EGL_VENDOR_LIBRARY_FILENAMES" ]
    null
    osCfg;

  captureRoot = if screenshotRoot != null then screenshotRoot
    else lib.attrByPath [ "hwc" "paths" "screenshots" ] null osCfg;
  capturePkg = pkgs.writeShellApplication {
    name = "hwc-screenshot";
    text = ''exec ${lib.getExe inputs.screenshot-renamer.packages.${pkgs.system}.default} capture --root ${lib.escapeShellArg (if captureRoot == null then "" else toString captureRoot)} --hyprshot ${lib.getExe pkgs.hyprshot} --wl-copy ${pkgs.wl-clipboard}/bin/wl-copy --notify-send ${pkgs.libnotify}/bin/notify-send "$@"'';
  };
  captureCommand = if captureRoot == null then null else "${capturePkg}/bin/hwc-screenshot";

  # behavior declares the bindings once and returns them two ways: `settings`
  # (what Hyprland loads) and `keybinds` (structured records). theme paints
  # those records into the SUPER+? legend `card`; session wraps the card in the
  # viewer package. One declaration, so the legend can't drift from the keys.
  behavior   = import ./parts/behavior.nix   { inherit config lib pkgs captureCommand; };
  theme      = import ./parts/theme.nix      { inherit config lib pkgs; keybinds = behavior.keybinds; };
  session    = import ./parts/session.nix    { inherit config lib pkgs; card = theme.card; workbenchCommand = behavior.workbenchCommand; osConfig = osConfig; };

  hw = if builtins.pathExists ./parts/hardware.nix
       then import ./parts/hardware.nix { inherit lib pkgs; }
       else {};

  # Keep the existing declarative records as the single source for the legend
  # and compositor. This boundary renders them through Home Manager's Lua API.
  toLua = lib.generators.toLua {};
  raw = expr: lib.generators.mkLuaInline expr;
  split = lib.splitString ",";
  rest = xs: lib.concatStringsSep "," (lib.tail xs);
  call = name: value: "hl.dsp.${name}(${toLua value})";
  dispatch = action:
    let xs = split action; name = lib.head xs; arg = rest xs;
    in if name == "exec" then call "exec_cmd" arg
    else if name == "movefocus" then call "focus" { direction = arg; }
    else if name == "workspace" then call "focus" { workspace = arg; }
    else if name == "submap" then call "submap" arg
    else if name == "layoutmsg" then call "layout" arg
    else if name == "resizeactive" then
      let xy = lib.splitString " " arg;
      in call "window.resize" { x = lib.toInt (lib.head xy); y = lib.toInt (builtins.elemAt xy 1); relative = true; }
    else if name == "movewindow" then "hl.dsp.window.drag()"
    else if name == "resizewindow" then "hl.dsp.window.resize()"
    else if name == "killactive" then "hl.dsp.window.close()"
    else if lib.elem name [ "fullscreen" "pseudo" "pin" ] then "hl.dsp.window.${name}()"
    else if name == "exit" then "hl.dsp.exit()"
    else throw "Unmapped Hyprland dispatcher: ${name}";
  binding = repeating: value:
    let xs = split value; mods = lib.head xs; key = builtins.elemAt xs 1;
    in { _args = [ ((lib.optionalString (mods != "") (lib.replaceStrings [ " " ] [ " + " ] mods + " + ")) + key)
      (raw (dispatch (lib.concatStringsSep "," (lib.drop 2 xs)))) { inherit repeating; } ]; };
  rule = value:
    lib.foldl' (acc: field:
      let pair = lib.splitString " " field; key = lib.head pair;
          value = lib.concatStringsSep " " (lib.tail pair);
          typed = if value == "on" then true else if value == "off" then false else value;
      in if lib.hasPrefix "match:" key then acc // { match = (acc.match or {}) // { ${lib.removePrefix "match:" key} = value; }; }
      else acc // { ${key} = typed; }) {} (lib.splitString ", " value);
  legacySettings = lib.foldl' lib.recursiveUpdate {} [
    { debug.enable_stdout_logs = false; }
    (lib.filterAttrs (_: v: v != null) (builtins.intersectAttrs { monitor = null; workspace = null; input = null; device = null; } hw))
    behavior.settings
    { "exec-once" = session.execOnce or []; env = session.env or []; }
    theme.settings
  ];
  luaSettings = {
    config = (builtins.removeAttrs legacySettings [ "bind" "bindm" "windowrule" "layerrule" "monitor" "workspace" "device" "exec-once" "env" "animations" ]) // {
      animations = builtins.removeAttrs legacySettings.animations [ "bezier" "animation" ];
      input = legacySettings.input // { touchpad = (builtins.removeAttrs legacySettings.input.touchpad [ "tap-to-click" ]) // {
        tap_to_click = legacySettings.input.touchpad."tap-to-click";
      }; };
      general = legacySettings.general // { "col.active_border" =
        let parts = lib.splitString " " legacySettings.general."col.active_border";
        in { colors = lib.take 2 parts; angle = lib.toInt (lib.removeSuffix "deg" (builtins.elemAt parts 2)); };
      };
    };
    bind = map (binding false) ((legacySettings.bind or []) ++ (legacySettings.bindm or []));
    window_rule = map rule (legacySettings.windowrule or []);
    layer_rule = map rule (legacySettings.layerrule or []);
    monitor = map (value: let xs = split value; in {
      output = lib.head xs; mode = builtins.elemAt xs 1;
      position = builtins.elemAt xs 2; scale = builtins.elemAt xs 3;
    }) (legacySettings.monitor or []);
    workspace_rule = map (value: let xs = split value; in {
      workspace = lib.head xs; monitor = lib.removePrefix "monitor:" (builtins.elemAt xs 1);
    }) (legacySettings.workspace or []);
    device = legacySettings.device or [];
    env = map (value: let xs = split value; in { _args = [ (lib.head xs) (rest xs) ]; }) (legacySettings.env or []);
    curve = map (value: let xs = split value; num = n: builtins.fromJSON (builtins.elemAt xs n); in {
      _args = [ (lib.head xs) { type = "bezier"; points = [ [ (num 1) (num 2) ] [ (num 3) (num 4) ] ]; } ];
    }) legacySettings.animations.bezier;
    animation = map (value: let xs = split value; in {
      leaf = lib.head xs; enabled = builtins.elemAt xs 1 == "1";
      speed = lib.toInt (builtins.elemAt xs 2); bezier = builtins.elemAt xs 3;
    } // lib.optionalAttrs (lib.length xs > 4) { style = builtins.elemAt xs 4; }) legacySettings.animations.animation;
    on = [{ _args = [ "hyprland.start" (raw ("function()\n" + lib.concatMapStrings (cmd: "hl.exec_cmd(${toLua cmd})\n") (legacySettings."exec-once" or []) + "end")) ]; }];
  };

  wallpaperPath = ../../theme/nord-mountains.jpg;

  basePkgs = with pkgs; [
    wofi hyprshot grim hypridle swaybg swaylock cliphist wl-clipboard
    brightnessctl networkmanager wirelesstools wlogout fend
    socat  # For monitor hotplug listener
  ];

  # Hyprland owns app launches, so Waybar restarts cannot kill an app.
  appToggle = pkgs.writeShellScriptBin "hyprland-app-toggle" ''
    set -euo pipefail
    # --show: bring the window here and focus it, never hide it (an alert's Open).
    show=0
    if [[ "''${1:-}" == "--show" ]]; then
      show=1
      shift
    fi
    if [[ $# -lt 2 ]]; then
      echo "usage: hyprland-app-toggle [--show] CLASS COMMAND [ARGS...]" >&2
      exit 64
    fi
    class="$1"
    shift
    clients=$(${pkgs.hyprland}/bin/hyprctl clients -j)
    address=$(printf '%s' "$clients" | ${pkgs.jq}/bin/jq -r --arg class "$class" '[.[] | select(.class == $class) | .address] | first // empty')
    if [[ -z "$address" ]]; then
      ${pkgs.hyprland}/bin/hyprctl dispatch "hl.dsp.exec_cmd($(${pkgs.jq}/bin/jq -Rn --arg cmd "$*" '$cmd'))"
      exit
    fi
    window_workspace=$(printf '%s' "$clients" | ${pkgs.jq}/bin/jq -r --arg address "$address" '.[] | select(.address == $address) | .workspace.id')
    current_workspace=$(${pkgs.hyprland}/bin/hyprctl activeworkspace -j | ${pkgs.jq}/bin/jq -r '.id')
    if [[ "$show" == 1 ]]; then
      ${pkgs.hyprland}/bin/hyprctl dispatch "hl.dsp.window.move({workspace='$current_workspace',window='address:$address'})"
      ${pkgs.hyprland}/bin/hyprctl dispatch "hl.dsp.focus({window='address:$address'})"
    elif [[ "$window_workspace" == "$current_workspace" ]]; then
      ${pkgs.hyprland}/bin/hyprctl dispatch "hl.dsp.window.move({workspace='special:password-managers',window='address:$address',follow=false})"
    else
      ${pkgs.hyprland}/bin/hyprctl dispatch "hl.dsp.window.move({workspace='$current_workspace',window='address:$address'})"
      ${pkgs.hyprland}/bin/hyprctl dispatch "hl.dsp.focus({window='address:$address'})"
    fi
  '';

  # Monitor hotplug listener script. The toggle is a system-lane package (sys.nix).
  monitorToggle = "/run/current-system/sw/bin/hyprland-monitor-toggle";
  monitorListenerPkg = pkgs.writeShellScriptBin "hyprland-monitor-listener" ''
    #!/usr/bin/env bash
    # Listen to Hyprland IPC socket for monitor events and restart waybar.
    # Restore the remembered external-screen side at login, after hotplugs and
    # after config reloads, which discard the toggle's runtime monitor rules.

    SOCKET="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

    # Wait for socket to exist
    for i in {1..30}; do
      [[ -S "$SOCKET" ]] && break
      sleep 1
    done

    if [[ ! -S "$SOCKET" ]]; then
      echo "hyprland-monitor-listener: socket not found after 30s, exiting" >&2
      exit 1
    fi

    echo "hyprland-monitor-listener: listening on $SOCKET"
    ${monitorToggle} apply || echo "hyprland-monitor-listener: side restore failed" >&2

    ${pkgs.socat}/bin/socat -U - "UNIX-CONNECT:$SOCKET" | while read -r line; do
      case "$line" in
        configreloaded*)
          ${monitorToggle} apply || echo "hyprland-monitor-listener: side restore failed" >&2
          ;;
        monitoradded*|monitorremoved*)
          echo "hyprland-monitor-listener: $line - restarting waybar"
          # Small delay to let monitor fully initialize
          sleep 1
          ${monitorToggle} apply || echo "hyprland-monitor-listener: side restore failed" >&2
          ${pkgs.systemd}/bin/systemctl --user restart waybar
          ;;
      esac
    done
  '';
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.hyprland = {
    enable = lib.mkEnableOption "Hyprland window manager";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    #==========================================================================
    # DEPENDENCY FORCING (Home domain only)
    #==========================================================================
    # Hyprland requires these home apps - enforce at module level
    hwc.home.apps.waybar.enable = lib.mkForce true;
    hwc.home.apps.swaync.enable = lib.mkForce true;
    # System-level forcing done in sys.nix

    #==========================================================================
    # IMPLEMENTATION
    #==========================================================================
    home.packages = basePkgs ++ lib.optional (captureRoot != null) capturePkg ++ (session.packages or []) ++ [ monitorListenerPkg appToggle ];

    home.sessionVariables = { XDG_CURRENT_DESKTOP = "Hyprland"; };

    # environment.sessionVariables reaches login children, but a lingering
    # systemd --user manager predates that PAM environment. Publish the same
    # system-owned EGL selection through environment.d so daemon-reload updates
    # the manager environment used by subsequently started desktop services.
    systemd.user.sessionVariables = lib.optionalAttrs
      (isNixOSHost && eglVendorLibraryFilenames != null)
      { __EGL_VENDOR_LIBRARY_FILENAMES = eglVendorLibraryFilenames; };

    home.file.".local/state/hypr/.keep".text = "";

    # Monitor hotplug listener - restarts waybar when monitors are added/removed
    systemd.user.services.hyprland-monitor-listener = {
      Unit = {
        Description = "Hyprland monitor hotplug listener";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${monitorListenerPkg}/bin/hyprland-monitor-listener";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install = { WantedBy = [ "graphical-session.target" ]; };
    };

    wayland.windowManager.hyprland = {
      enable  = true;
      package = pkgs.hyprland;

      configType = "lua";
      importantPrefixes = [ "config" "curve" ];
      submaps = lib.mapAttrs (_: submap: {
        settings.bind = map (binding false) (submap.settings.bind or [])
          ++ map (binding true) (submap.settings.binde or []);
      }) behavior.submaps;
      settings = luaSettings;
    };

    # Wallpaper — swaybg is simpler and avoids hyprpaper IPC version mismatches
    # swaybg is launched in session.nix exec-once

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      # Cross-lane consistency: check if system-lane is also enabled (NixOS only)
      # Feature Detection: Only enforce on NixOS hosts where system config is available
      # On non-NixOS hosts, user is responsible for system-lane dependencies
      (hmLib.sysLaneAssert { inherit osConfig; enabled = cfg.enable; app = "hyprland"; })

      # Home-lane dependencies
      {
        assertion = config.hwc.home.apps.waybar.enable;
        message = "hyprland requires waybar (critical dependency - forced via mkForce)";
      }
      {
        assertion = config.hwc.home.apps.swaync.enable;
        message = "hyprland requires swaync notification daemon (critical dependency - forced via mkForce)";
      }
      {
        assertion = !cfg.enable || config.hwc.home.apps.kitty.enable;
        message = "hyprland requires kitty as session-critical terminal (SUPER+RETURN, multiple keybinds)";
      }
      {
        assertion = !cfg.enable || config.hwc.home.apps.yazi.enable;
        message = "hyprland requires yazi as file manager (SUPER+1, SUPER+T keybinds)";
      }
    ];
  };
}
