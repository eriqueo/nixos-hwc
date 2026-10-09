# Shared navigation data for layout, keymap, and Workbench standing tools.
#
# Consumes Workbench hubRegistryFor schema 4: one `workbench` tab whose rail
# switches hubs, so every hub destination resolves to that tab, and each hub's
# registry `position` is its Ctrl+Space digit (hubJumps, positions 1–9).
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
  # The keymap adapter emits key|goto-hub|<tab>:<slug>|label from these targets.
  hubJumps = map (hub: {
    key = toString hub.position;
    desc = hub.label;
    target = "hub:${hub.slug}";
  }) (lib.sort (a: b: a.position < b.position)
    (lib.filter (hub: hub.position >= 1 && hub.position <= 9) registryHubs));
  destinations = paneTabs ++ toolTabs;
  tabIndex = builtins.listToAttrs (lib.imap1 (index: tab: {
    name = tab.destination; value = index;
  }) destinations);
  keys = map (tab: tab.destination) destinations;
  names = map (tab: tab.name) destinations;
in
assert lib.assertMsg (hubRegistry.schemaVersion == 4) "workbench: unsupported hub registry schema version";
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
  tabFor = tabIndex // builtins.listToAttrs (map (hub: {
    name = "hub:${hub.slug}"; value = tabIndex.workbench;
  }) registryHubs);
  launcherTabs = lib.mapAttrs (_: spec: spec.name) tools;
}
