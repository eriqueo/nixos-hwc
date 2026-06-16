# domains/home/apps/zellij/parts/tabs.nix
#
# Single source of truth for the workbench tab layout: launch-target -> tab name.
# Consumed by:
#   * parts/layout.nix            — emits the workbench KDL (the `tab name=…`s)
#   * ../../workbench/index.nix   — WORKBENCH_TABS, so the host NAVIGATES to a
#                                   tool's standing tab instead of spawning a
#                                   duplicate pane (the spawn-in-home bug).
#
# The DECLARATION ORDER here is the zellij tab order, and MUST stay aligned with
# the GoToTab <index> map in ../../keymap/parts/to-zellij.nix (1-based):
#   1 host · 2 todui · 3 khalt · 4 yazi · 5 aerc · 6 nvim
# Rename a tab in ONE place and both the layout and the host follow on rebuild.
{
  host  = "home";
  todui = "tasks";
  khalt = "cal";
  yazi  = "files";
  aerc  = "mail";
  nvim  = "edit";
}
