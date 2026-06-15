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
    // workbench pane grid — peer TUIs, NONE mounted in-process.
    // workbench occupies the host pane and orchestrates the rest via
    // `zellij action new-pane -n <name> -- <cmd>` / `--focus`.
    layout {
        tab name="workbench" focus=true {
            pane size="35%" name="host" {
                command "workbench"
            }
            pane split_direction="vertical" {
                // Left column: tasks + calendar (Eric's own first-class TUIs).
                pane name="todui" {
                    command "todui"
                    start_suspended true
                }
                pane name="khalt" {
                    command "khalt"
                    start_suspended true
                }
            }
        }
        // Secondary tabs workbench focuses on demand (g f / g m / g e grammar).
        tab name="files" {
            pane name="yazi" { command "yazi"; start_suspended true; }
        }
        tab name="mail" {
            pane name="aerc" { command "${mailBin}";${mailArgsKdl} start_suspended true; }
        }
        tab name="edit" {
            pane name="nvim" { command "nvim"; start_suspended true; }
        }
    }
  '';
}
