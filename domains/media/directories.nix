# domains/media/directories.nix
#
# THE SINGLE PRODUCER of /mnt directory creation for the media stack.
#
# Until 2026-09-10 there were two. domains/server/containers/_shared/directories.nix
# was a near-identical copy imported directly by machines/server/config.nix, and
# both were live: the emitted tmpfiles set carried 111 lines for 92 unique paths,
# i.e. 17 paths declared twice. Deleting the copy was verified by building the
# host config both ways and diffing the emitted rules — 111 lines fell to 94 with
# the same 92 unique paths, zero missing and zero added, so the copy contributed
# nothing but duplicates.
#
# Duplicates were not harmless. The two files had drifted: this one had gained
# hot.cache, books/.audiobookshelf-metadata and podcasts, and the copy had not.
# They also spelled the same owner two ways — `eric users` against `1000 100` —
# which systemd resolves identically and a reader does not. Nothing broke, but
# the next divergence would have been silent in exactly the same way.
#
# If you are adding a /mnt path, add it HERE. domains/system/mounts/index.nix
# still owns the mount points themselves and the top-level library directories
# (`media.directories`); that split is deliberate — mounts owns what the disk is,
# this file owns what the services need inside it.
{ lib, config, ... }:
let
  paths = config.hwc.paths;
  appsRoot = paths.apps.root;
  hotRoot = paths.hot.root;
  downloadsRoot = paths.hot.downloads;
  mediaRoot = paths.media.root;

  mediaEnabled = name:
    lib.attrByPath [ "hwc" "media" name "enable" ] false config;

  networkingEnabled = name:
    lib.attrByPath [ "hwc" "networking" name "enable" ] false config;

  mkDir = path: "d ${path} 0755 1000 100 -";
  mkRootDir = path: "d ${path} 0755 root root -";

  appRoot = name: "${appsRoot}/${name}";
  appConfig = name: "${(appRoot name)}/config";

  mkConfigDirs = names:
    lib.concatMap (name: lib.optionals (mediaEnabled name) [ (mkDir (appConfig name)) ]) names;
in
{
  config = {
    systemd.tmpfiles.rules = lib.flatten [
      # Shared downloads structure (hot storage)
      (lib.optionals (downloadsRoot != null) [
        (mkDir downloadsRoot)
        (mkDir "${downloadsRoot}/incomplete")
        (mkDir "${downloadsRoot}/complete")
        (mkDir "${downloadsRoot}/tv")
        (mkDir "${downloadsRoot}/movies")
        (mkDir "${downloadsRoot}/music")
        (mkDir "${downloadsRoot}/scripts")
      ])

      # Service cache tier. Six services already wrote here — frigate, gpu,
      # immich, jellyfin, qbittorrent, tensorrt — off a directory made by hand
      # in 2025 that no module created, so a rebuilt machine would not have it.
      # Only the parent is declared: each consumer makes its own subdirectory,
      # and enumerating them here would be a second list to keep in sync with
      # the modules that actually own them.
      (lib.optionals (paths.hot.cache != null) [
        (mkDir paths.hot.cache)
      ])

      # Event spool + processing areas
      (lib.optionals (hotRoot != null) [
        (mkDir "${hotRoot}/events")
        (mkDir "${hotRoot}/processing")
        (mkDir "${hotRoot}/processing/sonarr-temp")
        (mkDir "${hotRoot}/processing/radarr-temp")
        (mkDir "${hotRoot}/processing/lidarr-temp")
        (mkDir "${hotRoot}/processing/tdarr-temp")
        (mkDir "${hotRoot}/processing/tdarr-backups")
      ])

      # Books library structure
      (lib.optionals (mediaRoot != null) [
        (mkDir "${mediaRoot}/books/ebooks")
        (mkDir "${mediaRoot}/books/audiobooks")
        (mkDir "${mediaRoot}/books/.audiobookshelf-metadata")
        (mkDir "${mediaRoot}/podcasts")
        # Shared between pinchflat (downloads into it) and the youtube
        # transcripts service (writes alongside). Both used to declare it
        # themselves, with pinchflat saying `1000 100` and transcripts saying
        # `eric users` — the same identity spelled two ways, resolved by
        # whichever rule systemd applied last. A library directory that two
        # services share belongs to neither of them.
        (mkDir "${mediaRoot}/youtube")
      ])

      # Container config roots (/opt)
      (lib.optionals (appsRoot != null) ([ (mkRootDir appsRoot) ] ++ mkConfigDirs [
        "audiobookshelf"
        "beets"
        "books"
        "calibre"
        "mousehole"
        "jellyfin"
        "lidarr"
        "navidrome"
        "organizr"
        "prowlarr"
        "qbittorrent"
        "radarr"
        "recyclarr"
        "sabnzbd"
        "sonarr"
        "soularr"
      ]))

      # Containers with non-standard config layouts
      (lib.optionals (appsRoot != null && networkingEnabled "gluetun") [
        (mkDir (appRoot "gluetun"))
      ])
      (lib.optionals (appsRoot != null && mediaEnabled "soularr") [
        (mkDir "${(appRoot "soularr")}/data")
      ])
      (lib.optionals (appsRoot != null && mediaEnabled "tdarr") [
        (mkDir "${(appRoot "tdarr")}/server")
        (mkDir "${(appRoot "tdarr")}/configs")
        (mkDir "${(appRoot "tdarr")}/logs")
      ])
      (lib.optionals (appsRoot != null && mediaEnabled "recyclarr") [
        (mkDir "${(appRoot "recyclarr")}/cache")
      ])

      # System-level config dirs
      (lib.optionals (mediaEnabled "slskd") [
        (mkRootDir "/etc/slskd")
        (mkRootDir "/var/lib/slskd")
      ])
    ];
  };
}
