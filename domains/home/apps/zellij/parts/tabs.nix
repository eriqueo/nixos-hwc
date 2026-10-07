# Shared navigation data for layout, keymap, and Workbench standing tools.
#
# Accepts Workbench hubRegistry schema 2 (one zellij tab per hub) and schema 3
# (one `workbench` tab whose rail switches hubs). EXPAND STEP of the v2→v3
# migration: the v2 branch is removed once flake.lock pins a schema-3 Workbench
# and the cutover smoke passes (removal condition: `hubRegistry.schemaVersion
# == 3` in the locked input AND the workbench-tui S4 smoke recorded in its
# handoff).
{ lib, hubRegistry }:
let
  schema = hubRegistry.schemaVersion;
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

  # ── schema 2: one tab per default hub (temporary, see header) ─────────────
  # The v2 registry carries no meta letters; these are the letters the keymap
  # grammar hand-typed until schema 3 made the registry their one producer.
  v2Letters = {
    hwc = { key = "h"; desc = "HWC"; };
    crm = { key = "r"; desc = "CRM"; };
    brief = { key = "b"; desc = "Brief"; };
    refinery = { key = "R"; desc = "Refinery"; };
    mail = { key = "i"; desc = "Inbox (Workbench)"; };
    nightly = { key = "N"; desc = "Nightly"; };
  };
  v2 = let
    ordered = lib.sort (a: b: a.deploymentOrder < b.deploymentOrder)
      (lib.filter (hub: hub.defaultTab) registryHubs);
    hubTabs = map (hub: {
      name = hub.slug;
      destination = "hub:${hub.slug}";
      args = [ "--hub" hub.slug ];
      inherit (hub) slug landing;
    }) ordered;
  in
  assert lib.assertMsg (lib.all (hub: builtins.isBool hub.defaultTab && (!hub.landing || hub.defaultTab)) registryHubs)
    "workbench: landing hub must be a default tab";
  assert lib.assertMsg (unique (map (hub: hub.deploymentOrder) registryHubs)) "workbench: duplicate hub deployment order";
  {
    paneTabs = hubTabs;
    hubTargets = map (tab: { inherit (tab) slug destination; }) hubTabs;
    hubJumps = lib.concatMap (tab: lib.optional (v2Letters ? ${tab.slug}) {
      inherit (v2Letters.${tab.slug}) key desc;
      target = tab.destination;
    }) hubTabs;
  };

  # ── schema 3: one workbench tab; every hub is a destination inside it ─────
  v3 = {
    paneTabs = [ { name = "workbench"; destination = "workbench"; args = [ ]; landing = true; slug = ""; } ];
    # Each hub resolves to the workbench tab. S4 jumps there only; S5 adds the
    # control message that also switches the running workbench to the hub.
    hubTargets = map (hub: { inherit (hub) slug; destination = "hub:${hub.slug}"; }) registryHubs;
    hubJumps = map (hub: { inherit (hub) key; desc = hub.label; target = "hub:${hub.slug}"; })
      (lib.sort (a: b: a.order < b.order) registryHubs);
  };

  shape = if schema == 3 then v3 else v2;
  destinations = shape.paneTabs ++ toolTabs;
  tabIndex = builtins.listToAttrs (lib.imap1 (index: tab: {
    name = tab.destination; value = index;
  }) destinations);
  hubIndex = target: if schema == 3 then tabIndex.workbench else tabIndex.${target.destination};
  keys = map (tab: tab.destination) destinations;
  names = map (tab: tab.name) destinations;
in
assert lib.assertMsg (schema == 2 || schema == 3) "workbench: unsupported hub registry schema version";
assert lib.assertMsg (unique (map (hub: hub.slug) registryHubs)) "workbench: duplicate hub slug";
assert lib.assertMsg (builtins.length (lib.filter (hub: hub.landing) registryHubs) == 1)
  "workbench: exactly one landing hub is required";
assert lib.assertMsg (unique (map (jump: jump.key) shape.hubJumps)) "workbench: duplicate hub key";
assert lib.assertMsg (unique keys) "workbench: duplicate navigation destination";
assert lib.assertMsg (unique names) "workbench: duplicate final tab name";
assert lib.assertMsg (unique (map (tab: tab.order) toolTabs)) "workbench: duplicate tool order";
{
  inherit schema toolTabs destinations;
  # paneTabs: the tabs running `workbench`; hubJumps: {key, desc, target} for
  # the Ctrl+Space hub letters (to-zellij.nix appends them to grammar.meta).
  inherit (shape) paneTabs hubJumps;
  landingHub = (builtins.head (lib.filter (hub: hub.landing) registryHubs)).slug;
  # Destination → GoToTab index. A hub destination maps to the tab that shows
  # it: its own tab under schema 2, the workbench tab under schema 3.
  tabFor = tabIndex // builtins.listToAttrs (map (target: {
    name = target.destination; value = hubIndex target;
  }) shape.hubTargets);
  launcherTabs = lib.mapAttrs (_: spec: spec.name) tools;
}
