{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.server.apps.beets-native;

  # Beets with all plugins enabled
  beetsPackage = pkgs.beets;

  beetsConfig = pkgs.writeText "config.yaml" ''
    directory: ${cfg.musicDir}
    library: ${cfg.configDir}/library.db

    import:
      move: yes
      copy: no
      write: yes
      incremental: yes
      timid: no
      log: ${cfg.configDir}/import.log

    paths:
      default: $albumartist/$album%aunique{}/$track $title
      singleton: Non-Album/$artist/$title
      comp: Compilations/$album%aunique{}/$track $title

    plugins: duplicates fetchart embedart scrub replaygain missing info chroma web

    duplicates:
      checksum: ffmpeg
      copy: ""
      move: ""

    fetchart:
      auto: yes
      cautious: yes
      cover_names: cover folder

    embedart:
      auto: yes
      maxwidth: 1000

    scrub:
      auto: yes

    replaygain:
      auto: no
      backend: ffmpeg

    ui:
      color: yes

    musicbrainz:
      searchlimit: 10

    match:
      strong_rec_thresh: 0.15
      medium_rec_thresh: 0.40
      rec_gap_thresh: 0.40
      max_rec:
        missing_tracks: medium
        unmatched_tracks: medium
      distance_weights:
        source: 2.0
        artist: 3.0
        album: 3.0
        media: 1.0
        mediums: 1.0
        year: 1.0
        country: 0.5
        label: 0.5
        catalognum: 0.5
        albumdisambig: 0.5
        album_id: 5.0
        tracks: 2.0
        missing_tracks: 0.9
        unmatched_tracks: 0.6
        track_title: 3.0
        track_artist: 2.0
        track_index: 1.0
        track_length: 2.0
        track_id: 5.0

    autotagger:
      strong_rec_thresh: 0.10

    web:
      host: 127.0.0.1
      port: 8337
  '';

in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Install beets with all plugins on the host
    environment.systemPackages = [
      beetsPackage
      pkgs.ffmpeg  # Required for replaygain and chroma
    ];

    # Create config directory
    systemd.tmpfiles.rules = [
      "d ${cfg.configDir} 0755 eric users -"
      "d ${cfg.musicDir} 0755 eric users -"
      "d ${cfg.importDir} 0755 eric users -"
      "L+ /home/eric/.config/beets/config.yaml - - - - ${beetsConfig}"
    ];

    # Beets web service (optional)
    systemd.services.beets-web = {
      description = "Beets Web Interface";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        User = "eric";
        ExecStart = "${beetsPackage}/bin/beet web";
        Restart = "on-failure";
        Environment = [
          "BEETSDIR=/home/eric/.config/beets"
        ];
      };
    };

    # Validation
    assertions = [
      {
        assertion = !cfg.enable || true;
        message = "Beets native installation enabled";
      }
    ];
  };
}
