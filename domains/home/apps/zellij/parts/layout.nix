# domains/home/apps/zellij/parts/layout.nix
# Pure function: -> the `workbench` zellij layout (KDL).
# No options, no side-effects.
#
# This is the initial geometry workbench operates inside. workbench itself runs
# in each hub tab and drives `zellij action` to spawn/focus the PEER TUIs
# (todui, khalt, aerc, yazi, nvim) and web-app launchers in their standing tool
# tabs. Treating the
# layout as data (a KDL string) keeps "adding a pane target" a manifest/layout
# edit, not host code — consistent with the data-driven-rendering principle.
#
# `mailCommand` is late-bound (not assumed to be a local `aerc` binary): on the
# laptop, mail lives on the server, so index.nix derives it from the user's
# `hwc.home.core.shell.aliases.aerc` (e.g. "ssh -t server aerc"). Split into a
# KDL command + args node so the suspended pane runs the right thing on <ENTER>.
{ lib, tabs, mailCommand ? "aerc", webAppCommand ? "workbench-web-app"
, vhostDomain ? "hwc.iheartwoodcraft.com" }:

let
  mailParts = lib.splitString " " mailCommand;
  mailBin   = builtins.head mailParts;
  mailArgs  = builtins.tail mailParts;
  launchFor = tool:
    if tool.kind == "web" then {
      command = webAppCommand;
      args = [ tool.name "https://${tool.host}.${vhostDomain}" ];
    } else if tool.target == "aerc" then {
      command = mailBin;
      args = mailArgs;
    } else {
      command = tool.target;
      args = [];
    };
  # Trailing ';' terminates the args node so the following start_suspended is a
  # separate KDL node, not more args. builtins.toJSON gives KDL-compatible
  # quoted strings and escapes any late-bound mail arguments safely.
  argsKdl = args: lib.optionalString (args != [])
    (" args " + lib.concatMapStringsSep " " builtins.toJSON args + ";");

  # Nix owns the transport command; navigation data owns the names and order.
  hubTab = hub: ''
        tab name="${hub.name}"${lib.optionalString hub.landing " focus=true"} {
            pane name="${hub.name}" { command "workbench"; args "--hub" "${hub.slug}"; }
        }'';
  hubTabs = lib.concatStringsSep "\n" (map hubTab tabs.hubTabs);
  toolTab = tool: let launch = launchFor tool; in ''
        tab name="${tool.name}" {
            pane name="${tool.target}" { command ${builtins.toJSON launch.command};${argsKdl launch.args}${lib.optionalString tool.suspended " start_suspended true;"} }
        }'';
  toolTabs = lib.concatStringsSep "\n" (map toolTab tabs.toolTabs);
in
{
  workbenchKdl = ''
    // Flat tab set — peer TUIs, NONE mounted in-process. Every Workbench hub
    // with defaultTab has its own tab (`workbench --hub <id>`), and each TOOL is its own tab; uniform
    // whether a tab is a hub-page or a tool. The old single multi-hub "home" tab
    // is gone. Navigate with the meta-leader then a jump key, or Ctrl+j/k.
    layout {
        // Every tab gets a tab-bar (top, shows all tab names + which is focused)
        // and a status-bar (bottom, shows the active zellij keybinds). Without
        // these a custom layout renders bare panes with no way to discover the
        // other tabs or how to move — `children` is where each tab's panes land.
        default_tab_template {
            pane size=1 borderless=true { plugin location="zellij:tab-bar"; }
            children
            pane size=1 borderless=true { plugin location="zellij:status-bar"; }
        }
        // Hub pages precede tools; names and indices share one data source.
${hubTabs}
        // Aerc starts suspended so an idle session does not hold an SSH link.
        // Web launchers start suspended so opening Workbench never opens a GUI.
${toolTabs}
    }
  '';
}
