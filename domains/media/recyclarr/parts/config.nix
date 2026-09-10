# Recyclarr container configuration
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.recyclarr;
  appsRoot = config.hwc.paths.apps.root;
  cfgRoot = "${appsRoot}/recyclarr";

  generateConfigScript = pkgs.writeShellScript "recyclarr-generate-config" ''
    set -euo pipefail

    install -d -m755 ${cfgRoot}
    install -d -m755 ${cfgRoot}/config
    install -d -m755 ${cfgRoot}/cache

    cat > ${cfgRoot}/config/recyclarr.yml <<'EOF'
    # Recyclarr Configuration
    # Automatically syncs TRaSH Guides to *arr instances

    ${lib.optionalString cfg.services.sonarr.enable ''
    sonarr:
      tv:
        base_url: http://localhost:8989
        api_key: !secret sonarr_api_key

        # Quality definitions from TRaSH Guides, with explicit size caps.
        #
        # The guide's `series` data sets a MINIMUM per tier and leaves max and
        # preferred unlimited — it gates quality with custom formats, not size.
        # With no cap Sonarr took whatever the indexer offered: measured
        # 2026-09-09, Parks and Recreation held 122 WEBRip-1080p files at a
        # median 2.2 GB for a 21-minute episode (100 MB/min) while a 1.01 GB
        # WEBDL-1080p of the same episode sat rejected in the release list.
        #
        # `max` is set near the p90 of what this library ALREADY holds per
        # tier, so the cap removes outliers rather than the normal case, and
        # `preferred` sits near the median so Sonarr picks the smaller of two
        # acceptable releases. Both were derived from measured MB/min across
        # 4,300 episode files, not from a general sense of a good bitrate.
        #
        # Every `max` below was checked against that tier's LIVE guide minimum
        # on 2026-09-09 and clears it. A max at or under min does not cap a
        # tier, it makes the tier ungrabbable — that is how four Radarr tiers
        # were broken on 2026-08-24. Guide minimums at time of writing:
        # HDTV/WEBDL/WEBRip-720p 10, Bluray-720p 17.1, HDTV/WEBDL/WEBRip-1080p
        # 15, Bluray-1080p 50.4. Re-check them before changing any value here.
        #
        # Bluray-1080p Remux is deliberately left uncapped: it is not in the
        # HD-1080p profile, so a cap there gates nothing and only risks the
        # min/max inversion above.
        quality_definition:
          type: series
          qualities:
            - name: HDTV-720p
              preferred: 28
              max: 45
            - name: WEBDL-720p
              preferred: 30
              max: 45
            - name: WEBRip-720p
              preferred: 30
              max: 45
            - name: Bluray-720p
              preferred: 40
              max: 55
            - name: HDTV-1080p
              preferred: 40
              max: 70
            - name: WEBDL-1080p
              preferred: 50
              max: 85
            - name: WEBRip-1080p
              preferred: 45
              max: 70
            - name: Bluray-1080p
              preferred: 65
              max: 95

        # Quality profiles
        # HD-1080p prefers 1080p but falls back through 720p down to
        # DVD/SDTV so old or obscure shows (DVD-only releases) still
        # download, then upgrade automatically when 1080p appears.
        #
        # WEB-DL RANKS ABOVE BLURAY, AND ABOVE WEBRIP SEPARATELY.
        #
        # WEBDL-1080p and WEBRip-1080p used to share one `WEB-1080p` group,
        # which made them EQUAL to Sonarr — so a WEBRip could never upgrade to
        # a WEB-DL of the same show, no matter how much worse it was. That is
        # the defect behind Parks and Recreation: 122 WEBRip files at 100
        # MB/min sat there while 1.0 GB WEB-DLs of the same episodes were
        # rejected as "equal or higher preference". Grouping qualities is for
        # things you genuinely do not care to distinguish; these are not that.
        #
        # WEB-DL is first because it is the best quality-per-byte source for
        # television: a 1080p WEB-DL of a sitcom runs ~50 MB/min against ~90
        # for the Bluray of the same episode, off the same digital master.
        #
        # THE CUTOFF DELIBERATELY STAYS AT Bluray-1080p, one rank BELOW the
        # top. Cutoff means "stop upgrading once reached", and a file at or
        # above it is satisfied. Bluray therefore stays put instead of being
        # chased down to WEB-DL — this library holds ~250 GB of Bluray-sourced
        # episodes (Columbo, Band of Brothers, Jeeves and Wooster, South Park)
        # that are large because Bluray is large, not because anything is
        # wrong. Moving the cutoff up to WEBDL-1080p would put every one of
        # them below cutoff and a Cutoff Unmet search would replace real
        # picture quality with a smaller file. WEBRip and HDTV are below the
        # cutoff and DO get upgraded, which is the intended effect.
        quality_profiles:
          - name: HD-1080p
            reset_unmatched_scores:
              enabled: true
            upgrade:
              allowed: true
              until_quality: Bluray-1080p
              until_score: 10000
            qualities:
              - name: WEBDL-1080p
              - name: Bluray-1080p
              - name: WEBRip-1080p
              - name: HDTV-1080p
              - name: WEBDL-720p
              - name: Bluray-720p
              - name: WEBRip-720p
              - name: HDTV-720p
              - name: SD-Fallback
                qualities:
                  - Bluray-576p
                  - Bluray-480p
                  - DVD
                  - WEBDL-480p
                  - WEBRip-480p
                  - SDTV

        # Custom formats from TRaSH Guides
        custom_formats:
          - trash_ids:
              # Unwanted
              - 85c61753df5da1fb2aab6f2a47426b09  # BR-DISK
              - 9c11cd3f07101cdba90a2d81cf0e56b4  # LQ
              - 47435ece6b99a0b477caf360e79ba0bb  # x265 (HD)

            assign_scores_to:
              - name: HD-1080p
    ''}

    ${lib.optionalString cfg.services.radarr.enable ''
    radarr:
      movies:
        base_url: http://localhost:7878
        api_key: !secret radarr_api_key

        # Quality definitions from TRaSH Guides, with explicit size caps.
        #
        # These caps were set once before, on 2026-08-24, by
        # `workspace/media/radarr-rightsize.py --set-max-size` writing straight
        # to the Radarr API — and recyclarr reverted every one of them on its
        # next nightly run, because recyclarr owns this endpoint and the guide
        # data says unlimited. Measured 2026-09-09: all twelve were back to
        # None. The sync reports success while doing it, so nothing surfaced.
        # That is why the caps live HERE now and not in that script; the script
        # keeps its reporting and replacement modes, but `--set-max-size` writes
        # to a field this file owns.
        #
        # Same derivation as the Sonarr block: `max` near the p90 of what the
        # library already holds per tier, `preferred` near the median, measured
        # over 323 movies. Checked against LIVE guide minimums on 2026-09-09 —
        # WEBDL/WEBRip-1080p 12.5, HDTV-1080p 33.8, Bluray-1080p 50.8,
        # Bluray-720p 25.7 — and every max clears its min.
        #
        # Remux-1080p (min 102, holding 215-267 MB/min) is left uncapped on
        # purpose: it sits outside the HD-1080p profile, so it is not grabbable
        # anyway, and a cap near its min is the inversion that broke four tiers
        # in August.
        quality_definition:
          type: movie
          qualities:
            - name: HDTV-720p
              preferred: 30
              max: 45
            - name: WEBDL-720p
              preferred: 35
              max: 55
            - name: WEBRip-720p
              preferred: 35
              max: 55
            - name: Bluray-720p
              preferred: 45
              max: 60
            - name: HDTV-1080p
              preferred: 50
              max: 70
            - name: WEBDL-1080p
              preferred: 60
              max: 90
            - name: WEBRip-1080p
              preferred: 55
              max: 80
            - name: Bluray-1080p
              preferred: 80
              max: 110

        # Quality profiles
        # Same fallback ladder as Sonarr: prefer 1080p, accept anything
        # down to DVD/SDTV, upgrade automatically when better appears.
        quality_profiles:
          - name: HD-1080p
            reset_unmatched_scores:
              enabled: true
            upgrade:
              allowed: true
              until_quality: Bluray-1080p
              until_score: 10000
            qualities:
              - name: Bluray-1080p
              - name: WEB-1080p
                qualities:
                  - WEBDL-1080p
                  - WEBRip-1080p
              - name: HDTV-1080p
              - name: Bluray-720p
              - name: WEB-720p
                qualities:
                  - WEBDL-720p
                  - WEBRip-720p
              - name: HDTV-720p
              - name: SD-Fallback
                qualities:
                  - Bluray-576p
                  - Bluray-480p
                  - DVD
                  - WEBDL-480p
                  - WEBRip-480p
                  - SDTV

        # Custom formats from TRaSH Guides
        custom_formats:
          - trash_ids:
              # Movie Versions
              - 0f12c086e289cf966fa5948eac571f44  # Hybrid
              - 570bc9ebecd92723d2d21500f4be314c  # Remaster
              - eca37840c13c6ef2dd0262b141a5482f  # 4K Remaster

              # Unwanted
              - b8cd450cbfa689c0259a01d9e29ba3d6  # 3D
              - ae9b7c9ebde1f3bd336a8cbd1ec4c5e5  # No-RlsGroup

            assign_scores_to:
              - name: HD-1080p
    ''}

    ${lib.optionalString cfg.services.lidarr.enable ''
    lidarr:
      music:
        base_url: http://localhost:8686
        api_key: !secret lidarr_api_key

        # Quality definitions
        quality_definition:
          type: music

        # Quality profiles
        quality_profiles:
          - name: Lossless
            upgrade:
              allowed: true
              until_quality: FLAC
            qualities:
              - name: FLAC
              - name: MP3-320
    ''}
    EOF

    cat > ${cfgRoot}/config/secrets.yml <<EOF
    secrets:
    ${lib.optionalString cfg.services.sonarr.enable ''
      sonarr_api_key: $(cat ${config.age.secrets.${cfg.services.sonarr.apiKeySecret}.path} 2>/dev/null || echo "PLACEHOLDER_SONARR_API_KEY")
    ''}
    ${lib.optionalString cfg.services.radarr.enable ''
      radarr_api_key: $(cat ${config.age.secrets.${cfg.services.radarr.apiKeySecret}.path} 2>/dev/null || echo "PLACEHOLDER_RADARR_API_KEY")
    ''}
    ${lib.optionalString cfg.services.lidarr.enable ''
      lidarr_api_key: $(cat ${config.age.secrets.${cfg.services.lidarr.apiKeySecret}.path} 2>/dev/null || echo "PLACEHOLDER_LIDARR_API_KEY")
    ''}
    EOF

    chown -R eric:users ${cfgRoot}
    chmod 640 ${cfgRoot}/config/secrets.yml
    chmod 644 ${cfgRoot}/config/recyclarr.yml
  '';
in
{
  config = lib.mkIf cfg.enable {

    #=========================================================================
    # SYSTEMD TIMER FOR PERIODIC SYNC
    #=========================================================================
    systemd.services.recyclarr-sync = {
      description = "Recyclarr *arr configuration sync";
      after = [ "network-online.target" "podman-sonarr.service" "podman-radarr.service" "podman-lidarr.service" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStartPre = "${generateConfigScript}";
        ExecStart = "${pkgs.podman}/bin/podman run --rm --network=host -v ${cfgRoot}/config:/config ${cfg.image} sync";
      };
    };

    systemd.timers.recyclarr-sync = {
      description = "Recyclarr sync timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = if cfg.schedule == "daily" then "daily"
                     else if cfg.schedule == "weekly" then "weekly"
                     else cfg.schedule;
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };

    #=========================================================================
    # FIREWALL CONFIGURATION
    #=========================================================================
    # Recyclarr doesn't need external ports (connects outbound to *arr services)
  };
}
