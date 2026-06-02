# domains/system/core/coredump.nix
#
# systemd-coredump retention. The default config keeps every coredump
# forever, so a single crash loop can fill /var. On 2026-05-29 a 5-min
# llama-server crash loop dropped 29 × ~146MB coredumps (~4GB) into
# /var/lib/systemd/coredump and stayed there until manually purged.
#
# MaxUse caps the directory; systemd-coredump rotates oldest-first.
# We keep a generous window so post-mortem analysis is still possible.
{ nixosApiVersion ? "unstable", ... }:
{
  # nixos-25.11 stable uses systemd.coredump.extraConfig; unstable removed it
  # (mkRemovedOptionModule) in favor of systemd.coredump.settings.Coredump.
  systemd.coredump =
    if nixosApiVersion == "stable" then {
      extraConfig = ''
        MaxUse=500M
        KeepFree=2G
      '';
    } else {
      settings.Coredump = {
        MaxUse = "500M";
        KeepFree = "2G";
      };
    };
}
