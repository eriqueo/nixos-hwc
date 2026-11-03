{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.navidrome;
  # Temporary dependency override: remove when the upstream package selects
  # x/net >=0.62 and this image's module/native/current-data checks pass.
  # Temporary upstream CVE-2026-107696 fix. Remove when the pinned FFmpeg
  # source contains this redirect bound and the finite redirect contract passes.
  runtimeFfmpeg = pkgs.ffmpeg-headless.overrideAttrs (old: {
    patches = old.patches ++ [ (pkgs.fetchurl {
      url = "https://code.ffmpeg.org/FFmpeg/FFmpeg/commit/eb9cef3ef1f6adac1e701e3f5f06739a0fcb0c97.patch";
      hash = "sha256-89nXK7WjusxfLXexFWGRK///1KCZHVhHv/ejnpfQ8gw=";
    }) ];
  });
  moduleSums = pkgs.writeText "navidrome-fixed-go.sum" ''
    golang.org/x/net v0.62.0 h1:18ELalfM5+XNRwzM2nYqXsZQ9ByS1uhj2O/U7+5jqRY=
    golang.org/x/net v0.62.0/go.mod h1:WgDCOTH8iwtB66T4/GfI94AHo/hhdb7Hah9NDseQfiI=
    golang.org/x/crypto v0.58.0 h1:COkYLr4k7nDI4r6QtMML2AfzeIswWHAJthLS6K/M/54=
    golang.org/x/crypto v0.58.0/go.mod h1:Xh+kl5A+M0gMiWDytH2Hhr5Z7WbNCpv/eB/EFgfSk+w=
    golang.org/x/text v0.43.0 h1:1QivrlhwAsnMOcqgOdl9my7s9OyZl8O5/UGUTJVXoWc=
    golang.org/x/text v0.43.0/go.mod h1:hbSIYA/amXcRXTFSZqh8tWHEoqRvvbKPJ2uz/KU+a+s=
    golang.org/x/sys v0.49.0 h1:XbzkgYJHdqh/8m2Uu0W/dQv8nktxx4BFHp1M0gROTXA=
    golang.org/x/sys v0.49.0/go.mod h1:hNLxWAXmnKAxqDtdwIYC4bM9oQPEecfsnNMuSxOs3og=
    golang.org/x/term v0.47.0 h1:cpyOwQkr2Nzxe2p6KnrTG7Ei2wtzjsuSjhpXXepZ/BM=
    golang.org/x/term v0.47.0/go.mod h1:efAfAuG6RKABvg1ArGebRkvX6LXul14SM67o2e4mUCY=
    golang.org/x/sync v0.24.0 h1:iqiDrGoDgyuvAKrhLQthUEzU/R378N78gXbBjxed7oA=
    golang.org/x/sync v0.24.0/go.mod h1:sUUOizhqBxiL6pEWpqNLUiaJn1ShEbZ6BBqskPbjZm0=
    golang.org/x/tools v0.51.0 h1:k4Xc/1Om9jwkBJBo4NVLMSARBoWtK10mx+W5BnXCeAI=
    golang.org/x/tools v0.51.0/go.mod h1:9eEncMayCV6zRMGhR5eZEC2iBx98qWcF1HZ9Z7wJOoA=
    golang.org/x/telemetry v0.0.0-20260924152758-ed294f943157 h1:DftxASHKl6JolFPqoN+2WrFO53JvkHwRXvFqf8gsivA=
    golang.org/x/telemetry v0.0.0-20260924152758-ed294f943157/go.mod h1:i+ivNqjDnTF3WTElsdk5g9V5DTSBYgdNo7xTU9SDwYA=
  '';
  runtimePackage = (pkgs.navidrome.override { ffmpeg-headless = runtimeFfmpeg; }).overrideAttrs (old: {
  postPatch = old.postPatch + ''
    substituteInPlace go.mod \
      --replace-fail 'golang.org/x/net v0.59.0' 'golang.org/x/net v0.62.0' \
      --replace-fail 'golang.org/x/crypto v0.57.0' 'golang.org/x/crypto v0.58.0' \
      --replace-fail 'golang.org/x/text v0.42.0' 'golang.org/x/text v0.43.0' \
      --replace-fail 'golang.org/x/sys v0.48.0' 'golang.org/x/sys v0.49.0' \
      --replace-fail 'golang.org/x/term v0.46.0' 'golang.org/x/term v0.47.0' \
      --replace-fail 'golang.org/x/sync v0.23.0' 'golang.org/x/sync v0.24.0' \
      --replace-fail 'golang.org/x/tools v0.49.0' 'golang.org/x/tools v0.51.0' \
      --replace-fail 'golang.org/x/telemetry v0.0.0-20260811182544-a038080d80e5' 'golang.org/x/telemetry v0.0.0-20260924152758-ed294f943157'
    cat ${moduleSums} >> go.sum
  '';
  vendorHash = "sha256-hFRBDiQOGbw1KLyIwnnj3JqDZfriHtH9H2BaobjYXsA=";
  });
  runtimeArchive = pkgs.dockerTools.buildLayeredImage {
    name = "localhost/navidrome-runtime";
    tag = "${runtimePackage.version}-${builtins.substring 0 12 (builtins.hashString "sha256" (toString runtimePackage))}";
    contents = [ runtimePackage pkgs.cacert ];
    extraCommands = "mkdir -p data tmp; chmod 1777 tmp";
    config = {
      Entrypoint = [ "${runtimePackage}/bin/navidrome" ];
      WorkingDir = "/data";
      Env = [
        "ND_DATAFOLDER=/data" "ND_MUSICFOLDER=/music" "ND_PORT=4533"
        "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      ];
      ExposedPorts."4533/tcp" = {};
    };
  };
  runtimeImage = "${runtimeArchive.imageName}:${runtimeArchive.imageTag}";
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.navidrome = {
    enable = lib.mkEnableOption "navidrome container";
    image = lib.mkOption { type = lib.types.str; default = runtimeImage; description = "Qualified Nix-built application, Go and native-library image"; };
    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.hwc.paths.apps.root}/navidrome/data";
      description = "CRITICAL database and uploaded artwork; provision current data before activation. Borg owns recovery and retention.";
    };
    _runtimeImage = lib.mkOption { type = lib.types.str; default = runtimeImage; internal = true; readOnly = true; };
    network.mode = lib.mkOption { type = lib.types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable = lib.mkOption { type = lib.types.bool; default = true; };
  };

  imports = [
    ./sys.nix
    ./parts/config.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    system.build.navidromeRuntimeImage = runtimeArchive;
    system.build.navidromeRuntimePackage = runtimePackage;
    system.build.navidromeRuntimeFfmpeg = runtimeFfmpeg;
    systemd.services.podman-navidrome.preStart = lib.mkBefore ''
      # Do not replace an existing anonymous volume with an empty database.
      test -s ${lib.escapeShellArg "${cfg.dataDir}/navidrome.db"} || {
        echo "Navidrome current database must be provisioned in its configured data directory" >&2
        exit 1
      }
      test "$(${pkgs.sqlite}/bin/sqlite3 -readonly ${lib.escapeShellArg "${cfg.dataDir}/navidrome.db"} 'PRAGMA quick_check')" = ok
      ${lib.optionalString (cfg.image == runtimeImage) "${pkgs.podman}/bin/podman load --input ${runtimeArchive}"}
    '';
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Add assertions and validation logic here
}
