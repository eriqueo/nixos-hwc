# Single source of truth for aerc tag definitions.
# Imported by config.nix (queries, stylesets, column templates) and binds.nix (keybindings).
#
# COLOR SYSTEM: Tags are grouped by semantic domain. Each group shares one
# hwc palette color so you can instantly identify a tag's category at a glance.
# Secondary tags within a group use dim=true to differentiate.
#
#   Business (accent/copper-orange)  — office, work, hwcmt
#   Money    (info/blue)             — finance, bank, insurance
#   Personal (accentAlt/muted-red)   — personal, family, eriqueokeefe
#   Growth   (success/sage-green)    — admin, coaching
#   System   (fg3/muted-gray)        — tech, aerc, website
#   Flags    (error/red, warning/amber) — action, pending
#
# ALL category marking is exclusive under <Space>m leader.
# Display names use tag_key format for visual cue in sidebar (e.g. "finance_f").
#
# CUSTOM TAGS: User-defined tags live in tags-custom.json (same directory).
# Add tags there via the aerc-new-tag script (<Space>M in aerc), then run `hms`.
{ lib, colors ? {} }:
let
  c = colors;

  # Palette-derived group colors with hwc fallbacks
  group = {
    business = "#${c.accent    or "d08770"}";  # copper-orange — HWC brand
    money    = "#${c.info      or "5e81ac"}";  # blue — cool/financial
    personal = "#${c.warningBright or "fcbb74"}";  # bright amber — warm/personal
    growth   = "#${c.success   or "a3be8c"}";  # sage green — development
    system   = "#${c.fg3       or "50626f"}";  # muted gray — low noise
    urgent   = "#${c.error     or "bf616a"}";  # red — demands attention
    waiting  = "#${c.warning   or "cf995f"}";  # amber — needs follow-up
  };

  # Read custom tags from JSON sidecar (user-managed, not in Nix)
  customFile = ./tags-custom.json;
  customData = builtins.fromJSON (builtins.readFile customFile);
  customCategories = map (t: t // { color = group.${t.group} or group.system; }) (customData.categories or []);
  customFlags = map (t: t // { color = group.${t.group} or group.urgent; }) (customData.flags or []);

  # Category tags are mutually exclusive — assigning one removes the others.
  categoryTags = [
    # ── Business (copper-orange) ──
    { tag = "office";       color = group.business; display = "office_o";       spaceKey = "o"; }
    { tag = "work";         color = group.business; display = "work_w";         spaceKey = "w"; }
    { tag = "hwcmt";        color = group.business; display = "hwcmt_h";        spaceKey = "h"; dim = true;
      query = "(to:heartwoodcraftmt@gmail.com OR from:heartwoodcraftmt@gmail.com) AND NOT tag:trash"; }

    # ── Money (blue) ──
    { tag = "finance";      color = group.money;    display = "finance_f";      spaceKey = "f"; }
    { tag = "bank";         color = group.money;    display = "bank_b";         spaceKey = "b"; }
    { tag = "insurance";    color = group.money;    display = "insurance_$";    spaceKey = "$"; dim = true; }

    # ── Personal (muted red) ──
    { tag = "personal";     color = group.personal; display = "personal_p";     spaceKey = "p"; }
    { tag = "family";       color = group.personal; display = "family_y";       spaceKey = "y"; }
    { tag = "eriqueokeefe"; color = group.personal; display = "eriqueokeefe_e"; spaceKey = "e";
      query = "(to:eriqueokeefe@gmail.com OR from:eriqueokeefe@gmail.com) AND NOT tag:trash"; }

    # ── Growth (sage green) ──
    { tag = "admin";        color = group.growth;   display = "admin_n";        spaceKey = "n"; }
    { tag = "coaching";     color = group.growth;   display = "coaching_c";     spaceKey = "c"; }

    # ── System (muted gray) ──
    { tag = "tech";         color = group.system;   display = "tech_t";         spaceKey = "t"; }
    { tag = "aerc";         color = group.system;   display = "aerc_~";         spaceKey = "`"; }
    { tag = "website";      color = group.system;   display = "website_@";      spaceKey = "@"; }
  ] ++ customCategories;

  # Flag tags coexist with categories (not exclusive).
  flagTags = [
    { tag = "action";  color = group.urgent;  display = "action_!";  spaceKey = "!"; bold = true; }
    { tag = "pending"; color = group.waiting;  display = "pending_?"; spaceKey = "?"; }
  ] ++ customFlags;

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

  # Clear flags only (action, pending + Proton junk) — preserves category
  clearFlagsCmd =
    let
      extras = [ "important" "flagged" "starred" ];
      toClear = lib.unique ((map (t: t.tag) flagTags) ++ extras);
      removes = lib.concatMapStringsSep " " (n: "-${n}") toClear;
    in removes;

  # Nuclear clear: removes ALL custom categories + flags + Proton junk
  clearAllCmd =
    let
      extras = [ "important" "flagged" "starred" ];
      allToClear = lib.unique (categoryNames ++ (map (t: t.tag) flagTags) ++ extras);
      removes = lib.concatMapStringsSep " " (n: "-${n}") allToClear;
    in removes;

in {
  inherit categoryTags flagTags allTags tagStyle categoryNames exclusiveCmd clearFlagsCmd clearAllCmd;
  inherit group tagStyleLines;
}
