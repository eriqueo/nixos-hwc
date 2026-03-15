# Single source of truth for aerc tag definitions.
# Imported by config.nix (queries, stylesets, column templates) and binds.nix (keybindings).
{ lib }:
let
  # Category tags are mutually exclusive — assigning one removes the others.
  # Flag tags (starred) coexist with categories.
  categoryTags = [
    { tag = "work";           color = "#FFB86C"; key = "w"; }
    { tag = "coaching";       color = "#F1FA8C"; spaceKey = "c"; }
    { tag = "finance";        color = "#50FA7B"; key = "f"; }
    { tag = "bank";           color = "#8BE9FD"; spaceKey = "b"; }
    { tag = "insurance";      color = "#50FA7B"; extra = "insurance.dim = true"; spaceKey = "i"; noGoTo = true; }
    { tag = "tech";           color = "#BD93F9"; key = "t"; }
    { tag = "gmail-personal"; color = "#FF79C6"; display = "personal"; spaceKey = "p"; }
    { tag = "personal";       color = "#FF79C6"; key = "p"; }
  ];

  flagTags = [
    { tag = "starred"; color = "#FF5555"; extra = "starred.bold = true"; key = "s"; spaceKey = "*"; }
  ];

  allTags = flagTags ++ categoryTags;

  # Style name for a tag (uses display if set, else tag)
  tagStyle = t: t.display or t.tag;

  # All category tag names (for building exclusive remove lists)
  categoryNames = map (t: t.tag) categoryTags;

  # Exclusive label command: +tag -all-other-categories -inbox
  exclusiveCmd = t:
    let others = lib.filter (n: n != t.tag) categoryNames;
        removes = lib.concatMapStringsSep "" (n: " -${n}") others;
    in "+${t.tag}${removes} -inbox";

in {
  inherit categoryTags flagTags allTags tagStyle categoryNames exclusiveCmd;
}
