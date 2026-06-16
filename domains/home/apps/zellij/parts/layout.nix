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
{ lib, mailCommand ? "aerc", tabBar ? ''plugin location="zellij:tab-bar";'' }:

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
in
{
  workbenchKdl = ''
    // workbench tab grid — peer TUIs, NONE mounted in-process. Home-page model:
    // the `host` (workbench) owns its own tab as the dashboard / command center;
    // each tool gets its own tab (peers of files/mail/edit). The host directs
    // you to the right tab to do work — it never embeds a tool's UI.
    // Tab names carry an emoji for at-a-glance colour; navigate by Ctrl+t then
    // tab number, or Alt+←/→.
    layout {
        // Every tab gets a tab-bar (top, shows all tab names + which is focused)
        // and a status-bar (bottom, shows the active zellij keybinds). Without
        // these a custom layout renders bare panes with no way to discover the
        // other tabs or how to move — `children` is where each tab's panes land.
        default_tab_template {
            pane size=1 borderless=true { ${tabBar} }
            children
            pane size=1 borderless=true { plugin location="zellij:status-bar"; }
        }
        // Home = the workbench host alone (full pane). The dashboard you land on.
        tab name="${tabs.host}" focus=true {
            pane name="host" {
                command "workbench"
            }
        }
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
