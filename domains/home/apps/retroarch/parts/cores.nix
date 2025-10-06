# Pure helper for mapping core names to nixpkgs libretro packages
{ pkgs }:

let
  inherit (pkgs) libretro;

  # Map user-friendly core names to nixpkgs libretro packages
  coreMap = {
    # Nintendo
    "snes9x" = libretro.snes9x;
    "bsnes" = libretro.bsnes;
    "bsnes-hd" = libretro.bsnes-hd;
    "mesen" = libretro.mesen;
    "nestopia" = libretro.nestopia;
    "mupen64plus" = libretro.mupen64plus;
    "parallel-n64" = libretro.parallel-n64;

    # Sega
    "genesis-plus-gx" = libretro.genesis-plus-gx;
    "picodrive" = libretro.picodrive;

    # Sony
    "beetle-psx-hw" = libretro.beetle-psx-hw;
    "beetle-psx" = libretro.beetle-psx;
    "pcsx-rearmed" = libretro.pcsx-rearmed;
    "pcsx2" = libretro.pcsx2;
    "ppsspp" = libretro.ppsspp;

    # Handhelds
    "mgba" = libretro.mgba;
    "gambatte" = libretro.gambatte;
    "sameboy" = libretro.sameboy;
    "melonds" = libretro.melonds;
    "desmume" = libretro.desmume;
    "citra" = libretro.citra;

    # Arcade
    "mame" = libretro.mame;
    "mame2003-plus" = libretro.mame2003-plus;
    "fbneo" = libretro.fbneo;
    "fbalpha2012" = libretro.fbalpha2012;

    # Other consoles
    "dolphin" = libretro.dolphin;
    "beetle-saturn" = libretro.beetle-saturn;
    "yabause" = libretro.yabause;
    "virtualjaguar" = libretro.virtualjaguar;

    # Computer systems
    "dosbox-pure" = libretro.dosbox-pure;
    "vice-x64" = libretro.vice-x64;
    "puae" = libretro.puae;  # Amiga

    # Game engines
    "scummvm" = libretro.scummvm;
  };
in
{
  # Expose the core map
  inherit coreMap;

  # Given a list of core names, return the corresponding packages
  resolveCores = coreNames:
    builtins.map (name:
      coreMap.${name} or (builtins.throw "Unknown RetroArch core: ${name}")
    ) coreNames;
}
