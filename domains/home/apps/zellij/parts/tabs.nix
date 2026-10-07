# Shared navigation data for layout, keymap, and Workbench standing tools.
#
# Consumes Workbench hubRegistry schema 3: one `workbench` tab whose rail
# switches hubs, so every hub destination resolves to that tab, and each hub's
# registry `key` is its Ctrl+Space letter (hubJumps).
{ lib, hubRegistry }:
let
  registryHubs = hubRegistry.hubs;
  unique = xs: builtins.length xs == builtins.length (lib.unique xs);

  # The target, final name, order, and launch policy are defined together.
  tools = {
    todui = { name = "tasks"; order = 10; suspended = false; };
    khalt = { name = "cal"; order = 20; suspended = false; };
    yazi = { name = "files"; order = 30; suspended = false; };
    aerc = { name = "aerc"; order = 40; suspended = true; };
    nvim = { name = "edit"; order = 50; suspended = false; };
    # Suspended: herdr starts a server and attaches a session; do not spawn one
    # just because the workbench opened. <ENTER> in the pane attaches.
    herdr = { name = "agents"; order = 60; suspended = true; };
  };
  toolTabs = lib.sort (a: b: a.order < b.order)
    (lib.mapAttrsToList (target: spec: spec // {
      inherit target;
      destination = "tool:${target}";
    }) tools);

  # The one tab that runs workbench; its rail shows every hub.
  paneTabs = [ { name = "workbench"; destination = "workbench"; landing = true; } ];
  # {key, desc, target} per hub, in rail default order, for the Ctrl+Space
  # letters (to-zellij.nix appends them to grammar.meta).
  hubJumps = map (hub: { inherit (hub) key; desc = hub.label; target = "hub:${hub.slug}"; })
    (lib.sort (a: b: a.order < b.order) registryHubs);
  destinations = paneTabs ++ toolTabs;
  tabIndex = builtins.listToAttrs (lib.imap1 (index: tab: {
    name = tab.destination; value = index;
  }) destinations);
  keys = map (tab: tab.destination) destinations;
  names = map (tab: tab.name) destinations;
in
assert lib.assertMsg (hubRegistry.schemaVersion == 3) "workbench: unsupported hub registry schema version";
assert lib.assertMsg (unique (map (hub: hub.slug) registryHubs)) "workbench: duplicate hub slug";
assert lib.assertMsg (builtins.length (lib.filter (hub: hub.landing) registryHubs) == 1)
  "workbench: exactly one landing hub is required";
assert lib.assertMsg (unique (map (jump: jump.key) hubJumps)) "workbench: duplicate hub key";
assert lib.assertMsg (unique keys) "workbench: duplicate navigation destination";
assert lib.assertMsg (unique names) "workbench: duplicate final tab name";
assert lib.assertMsg (unique (map (tab: tab.order) toolTabs)) "workbench: duplicate tool order";
{
  inherit paneTabs hubJumps toolTabs destinations;
  landingHub = (builtins.head (lib.filter (hub: hub.landing) registryHubs)).slug;
  # Destination → GoToTab index; every hub destination is the workbench tab.
  tabFor = tabIndex // builtins.listToAttrs (map (jump: {
    name = jump.target; value = tabIndex.workbench;
  }) hubJumps);
  launcherTabs = lib.mapAttrs (_: spec: spec.name) tools;
}
