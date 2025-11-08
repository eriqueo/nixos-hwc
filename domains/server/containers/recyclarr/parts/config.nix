# Recyclarr container configuration
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.services.containers.recyclarr;
  cfgRoot = "/opt/downloads/recyclarr";
in
{
  config = lib.mkIf cfg.enable {

    #=========================================================================
    # RECYCLARR CONFIGURATION FILE GENERATION
    #=========================================================================
    systemd.services.recyclarr-config-setup = {
      description = "Generate Recyclarr configuration from templates";
      before = [ "podman-recyclarr.service" ];
      wantedBy = [ "podman-recyclarr.service" ];
      wants = [ "agenix.service" ];
      after = [ "agenix.service" ];
      serviceConfig.Type = "oneshot";

      script = ''
        mkdir -p ${cfgRoot}/config
        mkdir -p ${cfgRoot}/cache

        # Generate recyclarr.yml configuration
        cat > ${cfgRoot}/config/recyclarr.yml <<EOF
        # Recyclarr Configuration
        # Automatically syncs TRaSH Guides to *arr instances

        ${lib.optionalString cfg.services.sonarr.enable ''
        sonarr:
          tv:
            base_url: http://host.containers.internal:8989
            api_key: !secret sonarr_api_key

            # Quality definitions from TRaSH Guides
            quality_definition:
              type: series

            # Quality profiles
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

            # Custom formats from TRaSH Guides
            custom_formats:
              - trash_ids:
                  # HDR Formats
                  - 58d6a88f13e2db7f5059c41047876f00  # DV
                  - e23edd2482476e595fb990b12e7c609c  # DV HDR10
                  - 55d53828b9d81cbe20b02efd00aa0efd  # DV HLG
                  - a3e19f8f627608af0211acd02bf89735  # DV SDR

                  # Unwanted
                  - 85c61753df5da1fb2aab6f2a47426b09  # BR-DISK
                  - 9c11cd3f07101cdba90a2d81cf0e56b4  # LQ
                  - 47435ece6b99a0b477caf360e79ba0bb  # x265 (HD)

                quality_profiles:
                  - name: HD-1080p
        ''}

        ${lib.optionalString cfg.services.radarr.enable ''
        radarr:
          movies:
            base_url: http://host.containers.internal:7878
            api_key: !secret radarr_api_key

            # Quality definitions from TRaSH Guides
            quality_definition:
              type: movie

            # Quality profiles
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

            # Custom formats from TRaSH Guides
            custom_formats:
              - trash_ids:
                  # Movie Versions
                  - 0f12c086e289cf966fa5948eac571f44  # Hybrid
                  - 570bc9ebecd92723d2d21500f4be314c  # Remaster
                  - eca37840c13c6ef2dd0262b141a5482f  # 4K Remaster

                  # HDR Formats
                  - e23edd2482476e595fb990b12e7c609c  # DV HDR10
                  - 58d6a88f13e2db7f5059c41047876f00  # DV

                  # Unwanted
                  - b8cd450cbfa689c0259a01d9e29ba3d6  # 3D
                  - 90cedc1fea7ea5d11298bebd3d1d3223  # EVO (no WEBDL)
                  - ae9b7c9ebde1f3bd336a8cbd1ec4c5e5  # No-RlsGroup

                quality_profiles:
                  - name: HD-1080p
        ''}

        ${lib.optionalString cfg.services.lidarr.enable ''
        lidarr:
          music:
            base_url: http://host.containers.internal:8686
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

        # Generate secrets file
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

        chmod 644 ${cfgRoot}/config/secrets.yml
        chmod 644 ${cfgRoot}/config/recyclarr.yml
        chown -R eric:users ${cfgRoot}
      '';
    };

    #=========================================================================
    # SYSTEMD TIMER FOR PERIODIC SYNC
    #=========================================================================
    systemd.services.recyclarr-sync = {
      description = "Recyclarr *arr configuration sync";
      after = [ "network-online.target" "podman-sonarr.service" "podman-radarr.service" "podman-lidarr.service" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.podman}/bin/podman run --rm --network=media-network --add-host=host.containers.internal:10.89.0.1 -v ${cfgRoot}/config:/config ghcr.io/recyclarr/recyclarr:latest sync";
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
