{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.navidrome;
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  # Temporary upstream FFmpeg security backports for RTSP, SFTP, DASH,
  # HDR metadata and PSSH handling. Remove when the pinned source contains
  # these fixes and the finite protocol/native/data contracts pass.
  runtimeFfmpeg = pkgs.ffmpeg-headless.overrideAttrs (old: {
    patches = old.patches ++ (helpers.selectFfmpegSecurityBackports {
      advisories = [ "CVE-2026-107696" "CVE-2026-107675" "CVE-2026-107677" "CVE-2026-107676" "CVE-2026-107678" ];
    }).patches;
  });
  # Temporary Go overrides: remove when upstream selects x/net >=0.62
  # and chi >=5.4 and the module/native/current-data checks pass.
  moduleSums = pkgs.writeText "navidrome-fixed-go.sum" ''
    github.com/go-chi/chi/v5 v5.4.0 h1:+ufzvFTGKyin26Or5DLrlIDq4ygIDBVcj7oVNeeaYFE=
    github.com/go-chi/chi/v5 v5.4.0/go.mod h1:d1IG7GtKPSjPyBP365PH8sAGVHk3qfB/IhjFNRH1wWM=
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
  # Temporary log privacy backport: remove when upstream omits query strings
  # and header collections and the actual app log contract passes.
  privacyPatch = pkgs.writeText "navidrome-request-log-privacy.patch"
    (lib.concatStringsSep "\n" [
      "--- a/server/middlewares.go"
      "+++ b/server/middlewares.go"
      "@@ -3,7 +3,6 @@"
      " import ("
      " \t\"cmp\""
      " \t\"context\""
      "-\t\"encoding/json\""
      " \t\"errors\""
      " \t\"fmt\""
      " \t\"io/fs\""
      "@@ -39,7 +38,7 @@"
      " \t\tnext.ServeHTTP(ww, r)"
      " \t\tstatus := ww.Status()"
      " "
      "-\t\tmessage := fmt.Sprintf(\"HTTP: %s %s://%s%s\", r.Method, scheme, r.Host, r.RequestURI)"
      "+\t\tmessage := fmt.Sprintf(\"HTTP: %s %s://%s%s\", r.Method, scheme, r.Host, r.URL.EscapedPath())"
      " \t\tlogArgs := []any{"
      " \t\t\tr.Context(),"
      " \t\t\tmessage,"
      "@@ -48,10 +47,7 @@"
      " \t\t\t\"httpStatus\", ww.Status(),"
      " \t\t\t\"responseSize\", ww.BytesWritten(),"
      " \t\t}"
      "-\t\tif log.IsGreaterOrEqualTo(log.LevelTrace) {"
      "-\t\t\theaders, _ := json.Marshal(r.Header)"
      "-\t\t\tlogArgs = append(logArgs, \"header\", string(headers))"
      "-\t\t} else if log.IsGreaterOrEqualTo(log.LevelDebug) {"
      "+\t\tif log.IsGreaterOrEqualTo(log.LevelDebug) {"
      " \t\t\tlogArgs = append(logArgs, \"userAgent\", r.UserAgent())"
      " \t\t}"
      " "
      "--- a/server/auth.go"
      "+++ b/server/auth.go"
      "@@ -55,7 +55,7 @@"
      " \t\treturn"
      " \t}"
      " \tif user == nil {"
      "-\t\tlog.Warn(r, \"Unsuccessful login\", \"username\", username, \"request\", r.Header)"
      "+\t\tlog.Warn(r, \"Unsuccessful login\", \"username\", username)"
      " \t\t_ = rest.RespondWithError(w, http.StatusUnauthorized, \"Invalid username or password\")"
      " \t\treturn"
      " \t}"
      ""
    ]);
  runtimePackage = (pkgs.navidrome.override { ffmpeg-headless = runtimeFfmpeg; }).overrideAttrs (old: {
  patches = old.patches ++ [ privacyPatch ];
  postPatch = old.postPatch + ''
    substituteInPlace go.mod \
      --replace-fail 'github.com/go-chi/chi/v5 v5.3.2' 'github.com/go-chi/chi/v5 v5.4.0' \
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
  vendorHash = "sha256-XSqZCTEF9pj+dOuvDkHahBJk81GnVScpzsP1NeoOs1Y=";
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
    port = lib.mkOption { type = lib.types.port; default = (import ../../networking/ports.nix).navidrome.port; };
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
