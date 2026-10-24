# domains/home/apps/workbench/index.nix
#
# THIN TRANSLATOR — wires the standalone `workbench` flake's HM module into the
# HWC namespace and feeds it the system theme palette + the MCP gateway URL +
# the packaged manifest registry. Same model as the khalt/todui translators:
# the app ships a generic `programs.workbench` module; HWC supplies the values.
#
# NAMESPACE: hwc.home.apps.workbench.*   (Charter Law 2: namespace = folder)
# USAGE:     hwc.home.apps.workbench.enable = true;
#
# Auto-imported by domains/home/apps/index.nix (readDir). `inputs` arrives via
# extraSpecialArgs (see flake.nix mkNixos/mkHome).

{ config, lib, pkgs, inputs, osConfig ? {}, workbenchMailTarget ? null, ... }:

let
  cfg = config.hwc.home.apps.workbench;
  zellijPkg = config.hwc.home.apps.zellij.package;

  # One origin producer: consume the same named vhost catalog as Caddy and
  # laptop DNS. Independent HM has no osConfig and must supply serverUrl.
  routes = lib.attrByPath [ "hwc" "networking" "shared" "effectiveRoutes" ] [] osConfig;
  domain = lib.attrByPath [ "hwc" "networking" "shared" "vhostDomain" ] "" osConfig;
  serverRoutes = lib.filter (route: (route.name or "") == "workbench"
    && (route.mode or "") == "vhost") routes;
  defaultServerUrl = if builtins.length serverRoutes == 1 && domain != ""
    then "https://${(builtins.head serverRoutes).name}.${domain}" else "";
  mailLaunch = lib.attrByPath [ "hwc" "mail" "aerc" "launchInfo" ] null config;
  # AUTO-MANAGED runtime: the foreground helper owns one bounded resource and
  # removes its sockets when that resource closes. No business content lives here.
  # The helper creates this one directory; a headless host need not have the
  # desktop app's separate workbench cache tree yet.
  mailRuntimeRoot = "${config.xdg.cacheHome}/workbench-mail";

  # Active system palette -> flat token map, string values only, handed to the
  # app as JSON via the generic module's `palette` option (which sets
  # WORKBENCH_PALETTE). Identical contract to tasq's paletteJson.
  colors = lib.filterAttrs (_: v: builtins.isString v)
    (((config.hwc.home.theme or {}).colors or {}));

  # Late binding: the mail peer is NOT assumed to be a local binary. Derive its
  # launch command from the single declaration in the shell domain — on the
  # laptop mail lives on the server, so this is "ssh -t server aerc"; elsewhere
  # it falls back to a bare "aerc". Same fact the zellij layout derives.
  aercCmd = (config.hwc.home.core.shell.aliases or {}).aerc or "aerc";

  # The provider is machine policy, not an app concern. Use the same Codex
  # package selected by hwc.home.apps.codex so the one-shot analyzer cannot
  # drift from the CLI on the user's PATH.
  codexPkg = if config.hwc.home.apps.codex.package != null
    then config.hwc.home.apps.codex.package
    else pkgs.codex;

  # Standing-tab map (navigate-to-tab, not spawn-duplicate): launch-target ->
  # tab name, the TOOL tabs only. Imported from the SAME source the zellij layout
  # emits its tab names from, so the host can never navigate to a tab name the
  # layout uses. Hub pages are separate from tool launch targets.
  navigation = import ../zellij/parts/tabs.nix {
    inherit lib;
    hubRegistry = inputs.workbench.hubRegistryFor {
      order = cfg.hubOrder;
      hidden = cfg.hiddenHubs;
    };
  };

  # Unified keymap grammar → ~/.config/workbench/keymap.json. Workbench parses
  # this versioned contract and merges its global bindings with hub actions.
  km   = (config.hwc.home.keymap or {}).grammar or {};
  kmOutput =
    import ../../keymap/parts/to-workbench.nix { inherit lib; grammar = km;
      mailContract = builtins.fromJSON (builtins.readFile "${inputs.system-one}/scripts/mail_classifier_contract.json"); };
  kmWb = lib.optionalString (km ? meta) kmOutput.json;

  # `wb-reload` as a REAL binary on the session PATH (not just a shell alias).
  # The SUPER+W keybind runs `kitty -e wb-reload`, and `kitty -e` execs its
  # argument directly — it does NOT start an interactive shell, so a zsh alias
  # named wb-reload is invisible to it. A writeShellScriptBin is the single
  # source of truth that resolves both from the keybind and from interactive
  # shells. Kills the named session first (picks up layout edits) then re-creates
  # it fresh — i.e. SUPER+W now reloads workbench every time, by design. Bare
  # The selected package is shared with the wrapper and shell. Run from a
  # fresh terminal; never from inside the
  # workbench session it would kill.
  wbReload = pkgs.writeShellScriptBin "wb-reload" ''
    ${lib.getExe zellijPkg} delete-session workbench --force 2>/dev/null || true
    exec ${lib.getExe zellijPkg} attach -c workbench
  '';
in
{
  imports = [ inputs.workbench.homeManagerModules.workbench ];

  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.home.apps.workbench = {
    enable = lib.mkEnableOption "workbench — Textual TUI ops host (zellij-orchestrated)";

    serverUrl = lib.mkOption {
      type = lib.types.str;
      default = defaultServerUrl;
      description = "Private HTTPS Workbench origin shared by desktop and central TUI; derived from the sole named vhost, or explicitly supplied for independent Home Manager.";
    };

    handoff.enable = lib.mkEnableOption "central TUI handoffs through the private Workbench service";
    mailHelper.enable = lib.mkEnableOption "the foreground Workbench Mail helper profile";

    desktop = {
      enable = lib.mkEnableOption "optional bundled Workbench desktop consumer";
      summary.enable = lib.mkEnableOption "confirmed read-only temporary item summaries";
      externalLinks.enable = lib.mkEnableOption "confirmed HTTPS/exact T3 conversation opening";
      mail = {
        enable = lib.mkEnableOption "confirmed exact-thread opening in an owned Mail window";
        target = lib.mkOption {
          type = lib.types.nullOr (lib.types.submodule {
            options = lib.genAttrs [ "host" "remoteHelper" "remoteProfile" ]
              (_: lib.mkOption { type = lib.types.str; });
          });
          default = workbenchMailTarget;
          description = "Fixed helper target supplied by the fleet composition; independent HM must supply it explicitly.";
        };
      };
    };

    hubOrder = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Hub slugs in custom rail order; empty uses manifest defaults.";
    };

    hiddenHubs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Hub slugs hidden from the rail and its position shortcuts.";
    };

    gatewayUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:6200";
      description = "MCP gateway URL workbench talks to (offline fixtures fallback if unreachable).";
    };

    offline = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Force fixtures, never contact the gateway.";
    };

    hubsDir = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Optional custom hub manifests (*.toml). Empty uses the packaged hubs/
        that produce the Workbench flake registry. Custom hubs do not change
        the deployed Zellij tab set.
      '';
    };
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkMerge [ (lib.mkIf cfg.enable {
    # wb-reload binary on the session PATH — used by the SUPER+W Hyprland keybind
    # (kitty -e wb-reload) and available interactively. See let-block note.
    home.packages = [ wbReload ];

    # Drive the generic standalone module. It builds a wrapped `workbench` with
    # WORKBENCH_* baked in (palette JSON, gateway URL, hubs dir) and puts the
    # peer TUIs on its PATH so `zellij action` can spawn them.
    programs.workbench = {
      enable = true;
      handoff.serviceUrl = if cfg.handoff.enable then cfg.serverUrl else "";
      palette = colors;
      gatewayUrl = cfg.gatewayUrl;
      offline = cfg.offline;
      hubsDir = cfg.hubsDir;
      inherit (cfg) hubOrder hiddenHubs;
      defaultHub = navigation.landingHub;   # application-owned landing designation
      tabs = navigation.launcherTabs;    # plain jumps navigate to the tool's standing tab
      agentCommand = lib.getExe codexPkg;

      # Peer launch overrides (late binding). Mail runs wherever the shell alias
      # says — on the laptop that's the server over ssh, so DON'T bake a local
      # aerc onto PATH; the launcher invokes `ssh -t server aerc` instead.
      launchers = (lib.optionalAttrs (km ? meta) (kmOutput.handoffCommands aercCmd)) // { aerc = aercCmd;
        browser = "gpu-launch chromium-hwc-workbench"; };
      # `opens = "url:…"` (e.g. the DataX SR2 dashboard on Enter) opens in the GUI
      # browser. Use `chromium-hwc-workbench`, NOT the SUPER+B `chromium-hwc`: it
      # carries the same GPU/ANGLE/WebGL flags but a DEDICATED --user-data-dir, so
      # workbench windows run in their own profile + singleton and never contend
      # with the interactive chromium for the Default profile's SQLite locks. Two
      # live instances over one profile (after a suspend/resume singleton race) is
      # what stacked the "couldn't open profile" dialogs. gpu-launch is on the
      # session PATH (same as the Hyprland keybind in apps/hyprland/parts/behavior.nix).

      extraRuntimePackages = with pkgs; [
        zellijPkg     # same pane host as the shell and restart helper
        yazi          # peer pane: files
        neovim        # peer pane: editor
        codexPkg      # selected-item agent provider
        # mail (aerc) is NOT a local binary here — see launchers.aerc above.
        # Only bake a local aerc when no remote alias redirects it.
        # todui + khalt come from their own HM modules already on PATH.
      ] ++ lib.optional (aercCmd == "aerc") aerc;
    };

    # Versioned unified-keymap data, written only when the keymap module exists.
    xdg.configFile = lib.optionalAttrs (kmWb != "") {
      "workbench/keymap.json".text = kmWb;
    };
  }) (lib.mkIf cfg.desktop.enable {
    # The app owns its schema, package and entry. No credentials enter native
    # config, and tool paths cannot come from a browser or source item.
    programs.workbench.desktop = {
      enable = true;
      origin = cfg.serverUrl;
      summary = if cfg.desktop.summary.enable then {
        terminal = lib.getExe pkgs.kitty;
        editor = lib.getExe pkgs.neovim-unwrapped;
      } else null;
      externalOpener = if cfg.desktop.externalLinks.enable
        then lib.getExe' pkgs.xdg-utils "xdg-open" else null;
      mail = if cfg.desktop.mail.enable && cfg.desktop.mail.target != null then
        cfg.desktop.mail.target // {
          terminal = lib.getExe pkgs.kitty;
          ssh = lib.getExe pkgs.openssh;
          runtimeRoot = mailRuntimeRoot;
        } else null;
    };
  }) (lib.mkIf cfg.mailHelper.enable {
    programs.workbench.mailHelper = {
      enable = true;
      profile = if mailLaunch == null then {} else mailLaunch // { runtime = mailRuntimeRoot; };
    };
    assertions = [{
      assertion = mailLaunch != null;
      message = "Workbench Mail helper requires the aerc capability's generated launchInfo.";
    }];
  }) (lib.mkIf (cfg.desktop.enable && cfg.desktop.mail.enable) {
    assertions = [{
      assertion = cfg.desktop.mail.target != null;
      message = "Workbench native Mail requires a fixed helper target; independent Home Manager must configure it explicitly.";
    }];
  }) (lib.mkIf (cfg.desktop.enable || (cfg.enable && cfg.handoff.enable)) {
    assertions = [{
      assertion = builtins.match "https://[^/?#@[:space:]]+/?" cfg.serverUrl != null;
      message = "Workbench desktop/central TUI requires one private HTTPS serverUrl; independent Home Manager must configure it explicitly.";
    }];
  }) ];
}
