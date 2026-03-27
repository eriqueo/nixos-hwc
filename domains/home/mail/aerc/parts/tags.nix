# Single source of truth for aerc tag definitions.
# Imported by config.nix (queries, stylesets, column templates) and binds.nix (keybindings).
#
# ALL category marking is exclusive under <Space>m leader.
# Display names use tag_key format for visual cue in sidebar (e.g. "finance_f").
{ lib }:
let
  # Category tags are mutually exclusive — assigning one removes the others.
  categoryTags = [
    { tag = "office";     color = "#81a1c1"; display = "office_o";    spaceKey = "o"; }
    { tag = "admin";      color = "#b48ead"; display = "admin_n";     spaceKey = "n"; }
    { tag = "work";       color = "#d08770"; display = "work_w";      spaceKey = "w"; }
    { tag = "coaching";   color = "#ebcb8b"; display = "coaching_c";  spaceKey = "c"; }
    { tag = "finance";    color = "#81a1c1"; display = "finance_f";   spaceKey = "f"; }
    { tag = "bank";       color = "#88c0d0"; display = "bank_b";      spaceKey = "b"; }
    { tag = "insurance";  color = "#81a1c1"; display = "insurance_$"; extra = "insurance_$.dim = true"; spaceKey = "$"; }
    { tag = "tech";       color = "#88c0d0"; display = "tech_t";      spaceKey = "t"; }
    { tag = "personal";   color = "#d3869b"; display = "personal_p";  spaceKey = "p"; }
    { tag = "family";     color = "#d3869b"; display = "family_y";    spaceKey = "y"; }
    { tag = "hwcmt";      color = "#d08770"; display = "hwcmt_h";     extra = "hwcmt_h.dim = true"; spaceKey = "h"; query = "(to:heartwoodcraftmt@gmail.com OR from:heartwoodcraftmt@gmail.com) AND NOT tag:trash"; }
    { tag = "eriqueokeefe"; color = "#d3869b"; display = "eriqueokeefe_e"; spaceKey = "e"; query = "(to:eriqueokeefe@gmail.com OR from:eriqueokeefe@gmail.com) AND NOT tag:trash"; }
    { tag = "aerc";       color = "#4c566a"; display = "aerc_`";      spaceKey = "`"; }
    { tag = "website";    color = "#4c566a"; display = "website_@";   spaceKey = "@"; }
  ];

  # Flag tags coexist with categories (not exclusive).
  flagTags = [
    { tag = "action";       color = "#bf616a"; display = "action_!";       spaceKey = "!"; }
    { tag = "pending";      color = "#ebcb8b"; display = "pending_?";      spaceKey = "?"; }
  ];

  allTags = flagTags ++ categoryTags;

  # Style name for a tag (uses display if set, else tag)
  tagStyle = t: t.display or t.tag;

  # All category tag names (for building exclusive remove lists)
  categoryNames = map (t: t.tag) categoryTags;

  # Exclusive label command: +tag -all-other-categories (does NOT remove inbox — archiving is separate)
  exclusiveCmd = t:
    let others = lib.filter (n: n != t.tag) categoryNames;
        removes = lib.concatMapStringsSep "" (n: " -${n}") others;
    in "+${t.tag}${removes}";
  # One-shot clear: removes ALL custom categories + flags + Proton junk (flagged/starred/important)
  # So <Space>m- cleans the tags column AND the ! in flags column in one press
  clearCustomCmd =
    let
      extras = [ "important" "flagged" "starred" ];
      allToClear = lib.unique (categoryNames ++ (map (t: t.tag) flagTags) ++ extras);
      removes = lib.concatMapStringsSep " " (n: "-${n}") allToClear;
    in removes;

in {
  inherit categoryTags flagTags allTags tagStyle categoryNames exclusiveCmd clearCustomCmd;
}
