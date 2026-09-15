# Shared navigation data for layout, keymap, and Workbench standing tools.
{ lib, hubRegistry }:
let
  # Application facts arrive through one versioned, system-independent input.
  registryHubs = hubRegistry.hubs;
  orderedHubs = lib.sort (a: b: a.deploymentOrder < b.deploymentOrder) (lib.filter (hub: hub.defaultTab) registryHubs);

  # The target, final name, order, and launch policy are defined together.
  # Terminal tools are exposed to Workbench's pane launcher. Web tools are
  # standing Zellij tabs backed by the shared browser launcher; they stay out
  # of WORKBENCH_TABS because the Python host does not spawn web-app panes.
  tools = {
    todui = { name = "tasks"; order = 10; suspended = false; kind = "terminal"; };
    khalt = { name = "cal"; order = 20; suspended = false; kind = "terminal"; };
    yazi = { name = "files"; order = 30; suspended = false; kind = "terminal"; };
    paperless = { name = "paperless"; order = 35; suspended = true; kind = "web"; host = "paperless"; };
    firefly = { name = "firefly"; order = 36; suspended = true; kind = "web"; host = "firefly"; };
    aerc = { name = "aerc"; order = 40; suspended = true; kind = "terminal"; };
    nvim = { name = "edit"; order = 50; suspended = false; kind = "terminal"; };
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
  launcherTools = lib.filterAttrs (_: spec: spec.kind == "terminal") tools;
in
assert lib.assertMsg (hubRegistry.schemaVersion == 2) "workbench: unsupported hub registry schema version";
assert lib.assertMsg (unique (map (hub: hub.slug) registryHubs)) "workbench: duplicate hub slug";
assert lib.assertMsg (lib.all (hub: builtins.isBool hub.defaultTab && (!hub.landing || hub.defaultTab)) registryHubs)
  "workbench: landing hub must be a default tab";
assert lib.assertMsg (unique (map (hub: hub.deploymentOrder) registryHubs)) "workbench: duplicate hub deployment order";
assert lib.assertMsg (builtins.length (lib.filter (hub: hub.landing) registryHubs) == 1)
  "workbench: exactly one landing hub is required";
assert lib.assertMsg (unique keys) "workbench: duplicate navigation destination";
assert lib.assertMsg (unique names) "workbench: duplicate final tab name";
assert lib.assertMsg (unique (map (tab: tab.order) toolTabs)) "workbench: duplicate tool order";
assert lib.assertMsg (lib.all (tab: lib.elem tab.kind [ "terminal" "web" ]) toolTabs)
  "workbench: unsupported tool-tab kind";
assert lib.assertMsg (lib.all (tab: tab.kind != "web" ||
  (tab.suspended && builtins.match "[a-z0-9]+(-[a-z0-9]+)*" (tab.host or "") != null)) toolTabs)
  "workbench: web tabs require a safe host slug and suspended start";
{
  inherit hubTabs toolTabs destinations;
  landingHub = (builtins.head (lib.filter (hub: hub.landing) hubTabs)).slug;
  tabFor = builtins.listToAttrs (lib.imap1 (index: tab: {
    name = tab.destination; value = index;
  }) destinations);
  launcherTabs = lib.mapAttrs (_: spec: spec.name) launcherTools;
}
