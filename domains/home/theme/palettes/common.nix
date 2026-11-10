# Shared cursor assets and opacity vocabulary. gruv.nix owns one palette's
# colors; it cannot own facts that also apply to the other palettes.
{
  alpha = {
    opaque = "ff";
    strong = "cc";
    soft = "aa";
    faint = "66";
  };
  cursor = {
    size = 24;
    xcursor = {
      name = "Nordzy-cursors";
      package = "nordzy-cursor-theme";
    };
    hyprcursor.name = "Nordzy-hyprcursors";
  };
}
