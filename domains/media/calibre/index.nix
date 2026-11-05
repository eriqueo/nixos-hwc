{ lib, config, pkgs, ... }:

let
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  cfg = config.hwc.media.calibre;
  paths = config.hwc.paths;
  httpSourceSha256 = "016aa7664201a82f0f37ddfb11ed662dd1f07aa23c9470c6a3cb3278aa479230";
  httpSource = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/python/cpython/v3.14.8/Lib/http/client.py";
    sha256 = httpSourceSha256;
  };
  httpBackport = helpers.mkFrozenPythonHttpFramingBackport {
    python = "/opt/calibre/calibre-debug";
    pythonVersion = [ 3 14 8 ];
    frozenBundle = "/opt/calibre/lib/calibre-extensions/python-lib.bypy.frozen";
    frozenBundleSha256 = "558037f93bef7df037ff1c38519680ed1083263b9e86b38407c4e819a2acffb2";
    sourcePath = "/tmp/hwc-calibre-http/client.py";
    sourceSha256 = httpSourceSha256;
    rootPath = "/opt/hwc-calibre-http";
    selectionVariable = "CALIBRE_DEVELOP_FROM";
    environment = {
      CALIBRE_CONFIG_DIRECTORY = "/tmp/hwc-frozen-config";
      XDG_CACHE_HOME = "/tmp/hwc-frozen-cache";
    };
  };
  # Temporary: vendor 9.17's frozen Python still accepts malformed chunks.
  # Retire after the unmodified vendor browser passes the framing/data contract.
  runtime = helpers.mkRuntimeImage {
    name = "calibre";
    version = "9.17.0-http-framing";
    recipe = ''
      FROM lscr.io/linuxserver/calibre@sha256:b198fc03a6abc6be7e251a9958e50e74634b00e447c7b25e92c191c8077ba378
      COPY client.py /tmp/hwc-calibre-http/client.py
    '' + httpBackport.recipe + "RUN rm -rf /tmp/hwc-calibre-http /tmp/hwc-frozen-config /tmp/hwc-frozen-cache\n";
  };
  runtimeManifest = pkgs.writeText "calibre-http-framing.json" (builtins.toJSON httpBackport.manifest);
  runtimeContext = pkgs.runCommand "calibre-runtime-context" {} ''
    mkdir -p "$out"
    cp ${runtime.dockerfile} "$out/Dockerfile"
    cp ${httpSource} "$out/client.py"
    cp ${runtimeManifest} "$out/manifest.json"
  '';
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.calibre = {
    enable = lib.mkEnableOption "Calibre ebook management container";
    # Critical library state: upgrade this immutable vendor image only after
    # current-data startup and compatible-code recovery checks pass.
    image = lib.mkOption { type = lib.types.str; default = runtime.image; description = "Qualified Calibre 9.17.0 with frozen HTTP framing repair"; };
    network.mode = lib.mkOption { type = lib.types.enum [ "media" "vpn" ]; default = "media"; description = "Network mode"; };
    gpu.enable = lib.mkOption { type = lib.types.bool; default = false; description = "Enable GPU support for Calibre"; };
    ports = {
      desktop = lib.mkOption { type = lib.types.int; default = 8083; description = "Port for Calibre desktop interface (KasmVNC)"; };
      webserver = lib.mkOption { type = lib.types.int; default = 8181; description = "Port for Calibre content server"; };
    };
    library = lib.mkOption { type = lib.types.path; default = "${paths.media.books}/ebooks"; description = "Path to ebooks library"; };
  };

  imports = [
    ./sys.nix
    ./parts/config.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    system.build.calibreRuntimeImageRecipe = runtime.dockerfile;
    system.build.calibreRuntimeImageContext = runtimeContext;
    systemd.services.podman-calibre.preStart = lib.mkIf (cfg.image == runtime.image) (lib.mkBefore ''
      ${pkgs.podman}/bin/podman image exists ${lib.escapeShellArg runtime.image} || {
        echo "Prebuild Calibre from ${runtime.dockerfile} before activation" >&2
        exit 1
      }
    '');
    # Container definition is in sys.nix
    # Service dependencies are in parts/config.nix

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = helpers.mkVpnAssertions {
      name = "calibre";
      networkMode = cfg.network.mode;
      gluetunInstances = config.hwc.networking.gluetun.instances;
    } ++ [
      {
        assertion = config.hwc.paths.hot.root != null;
        message = "calibre container requires hwc.paths.hot.root to be defined (for downloads)";
      }
      {
        assertion = config.hwc.paths.media.root != null;
        message = "calibre container requires hwc.paths.media.root to be defined (for book libraries)";
      }
    ];
  };
}
