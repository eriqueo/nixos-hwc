# aerc tag definitions — PRESENTATION layer over the canonical taxonomy.
# Imported by config.nix (queries, stylesets, column templates) and binds.nix (keybindings).
#
# Optional legacy/manual tag vocabulary comes from domains/mail/taxonomy/data.nix.
# Workflow State, Domain, and classifier traits come from the separate pinned
# System One contract. This file owns only what is aerc-specific: mapping each
# group's palette ROLE to a hex color from the active theme, and the exclusive
# <Space>m marking / styleset command generation.
#
# CUSTOM TAGS: User-defined tags live in tags-custom.json (same directory) —
# deliberately OUTSIDE the taxonomy. Add tags there via the aerc-new-tag
# script (<Space>M in aerc), then run `hms`.
{ lib, colors ? {} }:
let
  c = colors;
  taxonomy = (import ../../taxonomy/lib.nix { inherit lib; }).data;

  # Palette role → hex, with hwc fallbacks. The taxonomy assigns each group a
  # ROLE (accent/info/…); the theme decides what that role looks like.
  roleColor = {
    accent        = "#${c.accent        or "d08770"}";  # copper-orange — HWC brand
    info          = "#${c.info          or "5e81ac"}";  # blue — cool/financial
    warningBright = "#${c.warningBright or "fcbb74"}";  # bright amber — warm/personal
    success       = "#${c.success       or "a3be8c"}";  # sage green — development
    fg3           = "#${c.fg3           or "50626f"}";  # muted gray — low noise
    error         = "#${c.error         or "bf616a"}";  # red — demands attention
    warning       = "#${c.warning       or "cf995f"}";  # amber — needs follow-up
  };

  # group name (business/money/…) → hex, via the taxonomy's role assignment
  group = lib.mapAttrs (_: role: roleColor.${role} or roleColor.fg3) taxonomy.groups;

  # Taxonomy entry → aerc tag record (drop the group key, resolve its color)
  colorize = fallback: t:
    (removeAttrs t [ "group" ]) // { color = group.${t.group} or fallback; };

  # Read custom tags from JSON sidecar (user-managed, not in Nix)
  customFile = ./tags-custom.json;
  customData = builtins.fromJSON (builtins.readFile customFile);
  customCategories = map (t: t // { color = group.${t.group} or group.system; }) (customData.categories or []);
  customFlags = map (t: t // { color = group.${t.group} or group.urgent; }) (customData.flags or []);

  # Legacy category tags remain searchable but are not workflow State or Domain.
  categoryTags = (map (colorize group.system) taxonomy.categories) ++ customCategories;

  # Optional fact/protection tags coexist with Domain and workflow State.
  flagTags = (map (colorize group.urgent) taxonomy.flags) ++ customFlags;

  allTags = flagTags ++ categoryTags;

  # Style name for a tag (uses display if set, else tag)
  tagStyle = t: t.display or t.tag;

  # All category tag names (for building exclusive remove lists)
  categoryNames = map (t: t.tag) categoryTags;

  # Generate [user] styleset lines from tag definitions
  tagStyleLines = lib.concatStringsSep "\n" (map (t:
    let
      name = tagStyle t;
      base = "${name}.fg = ${t.color}";
      dimLine = lib.optionalString (t.dim or false) "\n${name}.dim = true";
      boldLine = lib.optionalString (t.bold or false) "\n${name}.bold = true";
      # Legacy extra support (for any one-off overrides)
      extraLine = lib.optionalString (t ? extra) "\n${t.extra}";
    in base + dimLine + boldLine + extraLine
  ) allTags);

  # Exclusive label command: +tag -all-other-categories (does NOT remove inbox — archiving is separate)
  exclusiveCmd = t:
    let others = lib.filter (n: n != t.tag) categoryNames;
        removes = lib.concatMapStringsSep "" (n: " -${n}") others;
    in "+${t.tag}${removes}";

  # Clear flags only (action, pending + Proton junk) — preserves category and
  # every taxonomy-protected flag. `keep` is a durable janitor/auto-trash
  # shield, so an interactive bulk clear must never remove it.
  clearableFlagNames = map (t: t.tag)
    (lib.filter (t: !(t.protected or false)) flagTags);
  clearFlagsCmd =
    let
      extras = [ "important" "flagged" "starred" ];
      toClear = lib.unique (clearableFlagNames ++ extras);
      removes = lib.concatMapStringsSep " " (n: "-${n}") toClear;
    in removes;

  # Bulk clear: removes categories, removable flags, and Proton junk while
  # preserving protected flags.
  clearAllCmd =
    let
      extras = [ "important" "flagged" "starred" ];
      allToClear = lib.unique (categoryNames ++ clearableFlagNames ++ extras);
      removes = lib.concatMapStringsSep " " (n: "-${n}") allToClear;
    in removes;

in {
  inherit categoryTags flagTags allTags tagStyle categoryNames exclusiveCmd clearFlagsCmd clearAllCmd;
  inherit group tagStyleLines;
}
