{ lib, config, pkgs, ... }:
let
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  cfg = config.hwc.media.slskd;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.slskd = {
    enable = lib.mkEnableOption "slskd container";
    image = lib.mkOption { type = lib.types.str; default = "slskd/slskd:0.21.4"; description = "Container image (pinned for stability)"; };
    # Defaults to "vpn", and the assertion below makes "media" a BUILD FAILURE
    # unless allowClearnet is set explicitly. This option defaulted to "media"
    # from the day the module was written, so slskd egressed on the house IP for
    # six weeks — ~29.4 GB out, 15.5 GB in — while every sibling downloader was
    # tunnelled. Nothing objected, because nothing was watching: the ordering
    # line that appeared to wire slskd to gluetun lived in a module whose enable
    # was never set. A default is not a guarantee; the assertion is.
    network.mode = lib.mkOption { type = lib.types.enum [ "media" "vpn" ]; default = "vpn"; };

    vpnInstance = lib.mkOption {
      type = lib.types.str;
      default = "gluetun-slskd";
      description = ''
        Which hwc.networking.gluetun instance slskd lives inside. It gets its
        OWN tunnel rather than sharing qBittorrent's: Proton forwards exactly one
        port per WireGuard session, and Soulseek without an inbound port loses
        uploads AND degrades search and browse — which is precisely what soularr
        depends on.
      '';
    };

    allowClearnet = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Escape hatch for running slskd outside the tunnel. Leaving this false is
        what makes an un-tunnelled slskd fail to build instead of quietly leaking
        the house IP. Setting it true is a deliberate, reviewable act.
      '';
    };

    listenPort = lib.mkOption {
      type = lib.types.port;
      default = 50300;
      description = ''
        Soulseek listen port used when no forwarded port is available yet. On the
        VPN the live value comes from the tunnel's NAT-PMP port instead.
      '';
    };

    gpu.enable = lib.mkOption { type = lib.types.bool; default = true; };
    directories = {
      downloads = lib.mkOption { type = lib.types.str; default = "/downloads/music"; description = "Completed downloads directory"; };
      incomplete = lib.mkOption { type = lib.types.str; default = "/downloads/incomplete"; description = "Incomplete downloads directory"; };
    };
  };

  imports = [
    ./sys.nix
    ./parts/config.nix
  ];

  #==========================================================================
  # IMPLEMENTATION & VALIDATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    assertions = helpers.mkVpnAssertions {
      name = "slskd";
      networkMode = cfg.network.mode;
      vpnContainer = cfg.vpnInstance;
      gluetunInstances = config.hwc.networking.gluetun.instances;
    } ++ [
      {
        # The leak, as a build failure.
        assertion = cfg.network.mode == "vpn" || cfg.allowClearnet;
        message = ''
          slskd is configured with network.mode = "media", which puts its
          traffic on the house IP. Set hwc.media.slskd.network.mode = "vpn"
          (default), or set hwc.media.slskd.allowClearnet = true if that is
          genuinely what you want.
        '';
      }
      {
        assertion = config.hwc.paths ? media && config.hwc.paths ? hot;
        message = "slskd requires hwc.paths.media and hwc.paths.hot to be defined";
      }
      {
        assertion = config.age.secrets ? slskd-web-username
                  && config.age.secrets ? slskd-web-password
                  && config.age.secrets ? slskd-soulseek-username
                  && config.age.secrets ? slskd-soulseek-password
                  && config.age.secrets ? slskd-api-key;
        message = "slskd requires agenix secrets: slskd-web-username, slskd-web-password, slskd-soulseek-username, slskd-soulseek-password, slskd-api-key";
      }
    ];
  };
}
