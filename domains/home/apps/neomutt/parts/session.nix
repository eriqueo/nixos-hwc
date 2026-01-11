# modules/home/apps/neomutt/parts/session.nix
# NeoMutt • Session part (packages/env/services only)
{ lib, pkgs, config, osConfig ? {}, ... }:

{
  # App-scoped deps that make your behavior/appearance work out of the box
  packages = with pkgs; [
    neomutt        # the client
    msmtp          # send mail (your config points NeoMutt at msmtp)
    isync          # mbsync for offline sync (even if you trigger manually)
    notmuch        # fast search/index (optional to use; safe to install)
    urlscan        # used by the \cb macros
    abook          # query_command in your config
    lynx           # inline HTML renderer referenced in .mailcap
    zathura        # PDF viewer referenced in .mailcap
    # w3m          # (uncomment if you prefer w3m instead of lynx)
  ];

  services = { };  # keep empty here; timers/services belong in a separate “sync” part if you want them
  env = { };       # nothing special; EDITOR etc. handled globally
}