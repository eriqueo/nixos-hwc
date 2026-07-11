# domains/home/apps/zellij/parts/tabs.nix
#
# Single source of truth for the flat workbench tab set. The old single "home"
# tab (one multi-hub workbench) is DISSOLVED: every workbench hub is now its OWN
# top-level tab/page (`workbench --hub <id>`), a peer of the tool tabs — so the
# experience is uniform whether a tab is a hub-page or a tool.
#
# Consumed by:
#   * parts/layout.nix            — emits the KDL: one tab per hub (workbench
#                                   --hub <id>) + one per tool.
#   * ../../workbench/index.nix   — WORKBENCH_TABS (tool standing tabs only), so
#                                   the host NAVIGATES to a tool's tab instead of
#                                   spawning a duplicate pane.
#   * ../../keymap/parts/to-zellij.nix — derives 1-based GoToTab indices from the
#                                   tab order below (hubs first, then tools).
#
# TAB ORDER is hubs ++ tools:  1 hwc · 2 crm · 3 datax · 4 server · 5 brief ·
#                              6 tasks · 7 cal · 8 files · 9 mail · 10 edit
# Change a name/order in ONE place; layout, host, and keymap follow on rebuild.
{
  # Hub-pages: each is `workbench --hub <id>` full-screen; tab name == hub id.
  # Order = leftmost tabs. The first one is the landing tab (focus=true).
  # crm sits second to match its hub `order=15` (between hwc=10 and datax=20).
  hubs = [ "hwc" "crm" "datax" "server" "brief" ];

  # Tool tabs: launch-target -> tab name (the standing tab the host jumps to).
  todui = "tasks";
  khalt = "cal";
  yazi  = "files";
  aerc  = "mail";
  nvim  = "edit";
}
