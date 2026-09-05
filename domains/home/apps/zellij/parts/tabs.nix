# Shared navigation data for layout, keymap, and Workbench standing tools.
{ lib, workbenchSource }:
let
  # Transitional deployment list: remove when the versioned hubRegistry input
  # supplies deployment order. Validate commands against the packaged manifests.
  hubs = [ "hwc" "crm" "datax" "server" "brief" "refinery" ];
  manifestDir = workbenchSource + "/hubs";
  registered = map (file:
    (builtins.fromTOML (builtins.readFile (manifestDir + "/${file}"))).id
  ) (lib.filter (lib.hasSuffix ".toml") (builtins.attrNames (builtins.readDir manifestDir)));

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
  hubTabs = map (slug: { name = slug; destination = "hub:${slug}"; inherit slug; }) hubs;
  destinations = hubTabs ++ toolTabs;
  keys = map (tab: tab.destination) destinations;
  names = map (tab: tab.name) destinations;
  unique = xs: builtins.length xs == builtins.length (lib.unique xs);
in
assert lib.assertMsg (unique keys) "workbench: duplicate navigation destination";
assert lib.assertMsg (unique names) "workbench: duplicate final tab name";
assert lib.assertMsg (unique (map (tab: tab.order) toolTabs)) "workbench: duplicate tool order";
assert lib.assertMsg (lib.all (slug: lib.elem slug registered) hubs) "workbench: unregistered hub command";
{
  inherit hubs hubTabs toolTabs destinations;
  tabFor = builtins.listToAttrs (lib.imap1 (index: tab: {
    name = tab.destination; value = index;
  }) destinations);
  launcherTabs = lib.mapAttrs (_: spec: spec.name) tools;
}
