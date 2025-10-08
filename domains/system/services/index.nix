# The NEW, CORRECT, and AUTOMATED domains/system/services/index.nix
{ lib, ... }:

let
  # Read the current directory
  dir = builtins.readDir ./.;

  # Find all subdirectories (like 'backup', 'hardware', 'networking', etc.)
  # We also explicitly ignore the old 'parts' directory if it still exists.
  subds = lib.filterAttrs (n: t: t == "directory" && n != "parts") dir;

  # This is the magic part:
  # 1. Get the names of all subdirectories.
  # 2. Filter that list to only include directories that contain an 'index.nix'.
  # 3. Map the final list of names to full importable paths.
  subIndex = lib.pipe (lib.attrNames subds) [
    (ns: lib.filter (n: builtins.pathExists (./. + "/${n}/index.nix")) ns)
    (ns: lib.map (n: ./. + "/${n}/index.nix") ns)
  ];

in
{
  # The imports block is now incredibly simple and clean.
  imports =
    [
      # It imports the master options for this domain...
      ./options.nix
    ]
    # ...and then automatically imports every valid module it finds.
    ++ subIndex;
}
