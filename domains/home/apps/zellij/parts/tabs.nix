# Shared navigation data for layout, keymap, and Workbench standing tools.
{ lib, hubRegistry }:
let
  # Application facts arrive through one versioned, system-independent input.
  registryHubs = hubRegistry.hubs;
  orderedHubs = lib.sort (a: b: a.deploymentOrder < b.deploymentOrder) registryHubs;

  # The target, final name, order, and launch policy are defined together.
  tools = {
    todui = { name = "tasks"; order = 10; suspended = false; };
    khalt = { name = "cal"; order = 20; suspended = false; };
    yazi = { name = "files"; order = 30; suspended = false; };
    aerc = { name = "aerc"; order = 40; suspended = true; };
    nvim = { name = "edit"; order = 50; suspended = false; };
  };
  toolTabs = lib.sort (a: b: a.order < b.order)
    (lib.mapAttrsToList (target: spec: spec // {
      inherit target;
      destination = "tool:${target}";
    }) tools);
  hubTabs = map (hub: {
    name = hub.slug;
    destination = "hub:${hub.slug}";
    inherit (hub) slug landing;
  }) orderedHubs;
  destinations = hubTabs ++ toolTabs;
  keys = map (tab: tab.destination) destinations;
  names = map (tab: tab.name) destinations;
  unique = xs: builtins.length xs == builtins.length (lib.unique xs);
in
assert lib.assertMsg (hubRegistry.schemaVersion == 1) "workbench: unsupported hub registry schema version";
assert lib.assertMsg (unique (map (hub: hub.deploymentOrder) registryHubs)) "workbench: duplicate hub deployment order";
assert lib.assertMsg (builtins.length (lib.filter (hub: hub.landing) registryHubs) == 1)
  "workbench: exactly one landing hub is required";
assert lib.assertMsg (unique keys) "workbench: duplicate navigation destination";
assert lib.assertMsg (unique names) "workbench: duplicate final tab name";
assert lib.assertMsg (unique (map (tab: tab.order) toolTabs)) "workbench: duplicate tool order";
{
  inherit hubTabs toolTabs destinations;
  landingHub = (builtins.head (lib.filter (hub: hub.landing) hubTabs)).slug;
  tabFor = builtins.listToAttrs (lib.imap1 (index: tab: {
    name = tab.destination; value = index;
  }) destinations);
  launcherTabs = lib.mapAttrs (_: spec: spec.name) tools;
}
