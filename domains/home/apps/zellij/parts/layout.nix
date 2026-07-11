# domains/home/apps/zellij/parts/layout.nix
# Pure function: -> the `workbench` zellij layout (KDL).
# No options, no side-effects.
#
# This is the initial geometry workbench operates inside. workbench itself runs
# in the top pane and drives `zellij action` to spawn/focus the PEER TUIs
# (todui, khalt, aerc, yazi, nvim) into the named panes below. Treating the
# layout as data (a KDL string) keeps "adding a pane target" a manifest/layout
# edit, not host code — consistent with the data-driven-rendering principle.
#
# `mailCommand` is late-bound (not assumed to be a local `aerc` binary): on the
# laptop, mail lives on the server, so index.nix derives it from the user's
# `hwc.home.core.shell.aliases.aerc` (e.g. "ssh -t server aerc"). Split into a
# KDL command + args node so the suspended pane runs the right thing on <ENTER>.
{ lib, mailCommand ? "aerc" }:

let
  # Tab names come from the shared source of truth so the host's WORKBENCH_TABS
  # (navigate-to-standing-tab) can never drift from the layout's actual names.
  tabs = import ./tabs.nix;

  mailParts = lib.splitString " " mailCommand;
  mailBin   = builtins.head mailParts;
  mailArgs  = builtins.tail mailParts;
  # Trailing ';' terminates the args node so the following start_suspended is a
  # separate KDL node, not more args. Empty when the command has no args.
  mailArgsKdl = lib.optionalString (mailArgs != [])
    (" args " + lib.concatMapStringsSep " " (a: "\"${a}\"") mailArgs + ";");

  # One tab per hub-page: `workbench --hub <id>` full-screen. The first hub is
  # the landing tab (focus=true). Tab name == hub id (matches the GoToTab order
  # in to-zellij.nix). Data-driven off tabs.hubs — adding a hub-page is a one-
  # line edit there.
  hubTab = i: hub: ''
        tab name="${hub}"${lib.optionalString (i == 0) " focus=true"} {
            pane name="${hub}" { command "workbench"; args "--hub" "${hub}"; }
        }'';
  hubTabs = lib.concatStringsSep "\n" (lib.imap0 hubTab tabs.hubs);
in
{
  workbenchKdl = ''
    // Flat tab set — peer TUIs, NONE mounted in-process. Every workbench HUB is
    // its own tab (`workbench --hub <id>`), and each TOOL is its own tab; uniform
    // whether a tab is a hub-page or a tool. The old single multi-hub "home" tab
    // is gone. Navigate with the meta-leader then a jump key, or Alt+←/→.
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
        // Hub-pages (data-driven from tabs.hubs): hwc · crm · datax · server · brief.
        // The first is the landing tab. Each is a single-hub workbench page.
${hubTabs}
        // Tasks + calendar: Eric's first-class TUIs, auto-started (always-on peers).
        tab name="${tabs.todui}" {
            pane name="todui" { command "todui"; }
        }
        tab name="${tabs.khalt}" {
            pane name="khalt" { command "khalt"; }
        }
        // Local TUIs — auto-start, cheap to keep warm.
        tab name="${tabs.yazi}" {
            pane name="yazi" { command "yazi"; }
        }
        // Mail is the one heavy peer: `ssh -t server aerc`, a held-open connection
        // to the server — stays start_suspended (press <ENTER> to launch) so no
        // idle SSH lingers in a detached session.
        tab name="${tabs.aerc}" {
            pane name="aerc" { command "${mailBin}";${mailArgsKdl} start_suspended true; }
        }
        tab name="${tabs.nvim}" {
            pane name="nvim" { command "nvim"; }
        }
    }
  '';
}
