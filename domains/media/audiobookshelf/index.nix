# domains/media/audiobookshelf/index.nix
{ lib, config, pkgs, ... }:

let
  inherit (lib) mkOption mkEnableOption types;
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  cfg = config.hwc.media.audiobookshelf;
  paths = config.hwc.paths;
  name = "audiobookshelf";
  appVersion = "2.37.2";
  nodeVersion = "24.22.2";
  npmPackages = builtins.fromJSON ''
    [{"name":"form-data","version":"4.0.6","path":"form-data","file":"form-data-4.0.6.tgz","url":"https://registry.npmjs.org/form-data/-/form-data-4.0.6.tgz","hash":"sha512-vKatAh4SlVfgbv+YtmhiRjhEMJsYpsG1Y2rMQtR+SVSbytsSD1YGzDIcrAJmdFec88u/+VoGmxnl+80gL1tRCQ==","dependencies":{"hasown":"^2.0.4","asynckit":"^0.4.0","mime-types":"^2.1.35","combined-stream":"^1.0.8","es-set-tostringtag":"^2.1.0"}},{"name":"proxy-addr","version":"2.0.8","path":"proxy-addr","file":"proxy-addr-2.0.8.tgz","url":"https://registry.npmjs.org/proxy-addr/-/proxy-addr-2.0.8.tgz","hash":"sha512-5nnx0yGyVUcY6t9RnWcARWtwT9F1D8O9rt08htPvnd49W1IgZtmLkhu9WfMzQj1cFxjHIO6connUNVW5k7AVyQ==","dependencies":{"forwarded":"0.2.0","ipaddr.js":"1.9.1"}},{"name":"hasown","version":"2.0.4","path":"form-data/node_modules/hasown","file":"hasown-2.0.4.tgz","url":"https://registry.npmjs.org/hasown/-/hasown-2.0.4.tgz","hash":"sha512-T2UbfbBEF32wiepXIsMlTW9+dDYC6wMh/t/vYA4tuOMKqWz/n3vr1NFSxQiyP+zk2mXsoMA/i/7qV6LKut1t1A==","dependencies":{"function-bind":"^1.1.2"}},{"name":"es-set-tostringtag","version":"2.1.0","path":"form-data/node_modules/es-set-tostringtag","file":"es-set-tostringtag-2.1.0.tgz","url":"https://registry.npmjs.org/es-set-tostringtag/-/es-set-tostringtag-2.1.0.tgz","hash":"sha512-j6vWzfrGVfyXxge+O0x5sh6cvxAog0a/4Rdd2K36zCMV5eJ+/+tOAngRO8cODMNWbVRdVlmGZQL2YS3yR8bIUA==","dependencies":{"hasown":"^2.0.2","es-errors":"^1.3.0","get-intrinsic":"^1.2.6","has-tostringtag":"^1.0.2"}},{"name":"es-errors","version":"1.3.0","path":"form-data/node_modules/es-errors","file":"es-errors-1.3.0.tgz","url":"https://registry.npmjs.org/es-errors/-/es-errors-1.3.0.tgz","hash":"sha512-Zf5H2Kxt2xjTvbJvP2ZWLEICxA6j+hAmMzIlypy4xcBg1vKVnx89Wy0GbS+kf5cwCVFFzdCFh2XSCFNULS6csw==","dependencies":{}},{"name":"get-intrinsic","version":"1.3.0","path":"form-data/node_modules/get-intrinsic","file":"get-intrinsic-1.3.0.tgz","url":"https://registry.npmjs.org/get-intrinsic/-/get-intrinsic-1.3.0.tgz","hash":"sha512-9fSjSaos/fRIVIp+xSJlE6lfwhES7LNtKaCBIamHsjr2na1BiABJPo0mOjjz8GJDURarmCPGqaiVg5mfjb98CQ==","dependencies":{"gopd":"^1.2.0","hasown":"^2.0.2","es-errors":"^1.3.0","get-proto":"^1.0.1","has-symbols":"^1.1.0","function-bind":"^1.1.2","es-object-atoms":"^1.1.1","math-intrinsics":"^1.1.0","es-define-property":"^1.0.1","call-bind-apply-helpers":"^1.0.2"}},{"name":"has-tostringtag","version":"1.0.2","path":"form-data/node_modules/has-tostringtag","file":"has-tostringtag-1.0.2.tgz","url":"https://registry.npmjs.org/has-tostringtag/-/has-tostringtag-1.0.2.tgz","hash":"sha512-NqADB8VjPFLM2V0VvHUewwwsw0ZWBaIdgo+ieHtK3hasLz4qeCRjYcqfB6AQrBggRKppKF8L52/VqdVsO47Dlw==","dependencies":{"has-symbols":"^1.0.3"}},{"name":"gopd","version":"1.2.0","path":"form-data/node_modules/gopd","file":"gopd-1.2.0.tgz","url":"https://registry.npmjs.org/gopd/-/gopd-1.2.0.tgz","hash":"sha512-ZUKRh6/kUFoAiTAtTYPZJ3hw9wNxx+BIBOijnlG9PnrJsCcSjs1wyyD6vJpaYtgnzDrKYRSqf3OO6Rfa93xsRg==","dependencies":{}},{"name":"get-proto","version":"1.0.1","path":"form-data/node_modules/get-proto","file":"get-proto-1.0.1.tgz","url":"https://registry.npmjs.org/get-proto/-/get-proto-1.0.1.tgz","hash":"sha512-sTSfBjoXBp89JvIKIefqw7U2CCebsc74kiY6awiGogKtoSGbgjYE/G/+l9sF3MWFPNc9IcoOC4ODfKHfxFmp0g==","dependencies":{"dunder-proto":"^1.0.1","es-object-atoms":"^1.0.0"}},{"name":"has-symbols","version":"1.1.0","path":"form-data/node_modules/has-symbols","file":"has-symbols-1.1.0.tgz","url":"https://registry.npmjs.org/has-symbols/-/has-symbols-1.1.0.tgz","hash":"sha512-1cDNdwJ2Jaohmb3sg4OmKaMBwuC48sYni5HUw2DvsC8LjGTLK9h+eb1X6RyuOHe4hT0ULCW68iomhjUoKUqlPQ==","dependencies":{}},{"name":"es-object-atoms","version":"1.1.2","path":"form-data/node_modules/es-object-atoms","file":"es-object-atoms-1.1.2.tgz","url":"https://registry.npmjs.org/es-object-atoms/-/es-object-atoms-1.1.2.tgz","hash":"sha512-HWcBoN6NileqtSydK2FqHbS/LoDd2pqrnQHLyJzBj4kOp/ky2MWMN694xOfkK8/SnUsW2DH7EfyVlydKCsm1Zw==","dependencies":{"es-errors":"^1.3.0"}},{"name":"math-intrinsics","version":"1.1.0","path":"form-data/node_modules/math-intrinsics","file":"math-intrinsics-1.1.0.tgz","url":"https://registry.npmjs.org/math-intrinsics/-/math-intrinsics-1.1.0.tgz","hash":"sha512-/IXtbwEk5HTPyEwyKX6hGkYXxM9nbj64B+ilVJnC/R6B0pH5G4V3b0pVbL7DBj4tkhBAppbQUlf6F6Xl9LHu1g==","dependencies":{}},{"name":"es-define-property","version":"1.0.1","path":"form-data/node_modules/es-define-property","file":"es-define-property-1.0.1.tgz","url":"https://registry.npmjs.org/es-define-property/-/es-define-property-1.0.1.tgz","hash":"sha512-e3nRfgfUZ4rNGL232gUgX06QNyyez04KdjFrF+LTRoOXmrOgFKDg4BCdsjW8EnT69eqdYGmRpJwiPVYNrCaW3g==","dependencies":{}},{"name":"call-bind-apply-helpers","version":"1.0.2","path":"form-data/node_modules/call-bind-apply-helpers","file":"call-bind-apply-helpers-1.0.2.tgz","url":"https://registry.npmjs.org/call-bind-apply-helpers/-/call-bind-apply-helpers-1.0.2.tgz","hash":"sha512-Sp1ablJ0ivDkSzjcaJdxEunN5/XvksFJ2sMBFfq6x0ryhQV/2b/KwFe21cMpmHtPOSij8K99/wSfoEuTObmuMQ==","dependencies":{"es-errors":"^1.3.0","function-bind":"^1.1.2"}},{"name":"dunder-proto","version":"1.0.1","path":"form-data/node_modules/dunder-proto","file":"dunder-proto-1.0.1.tgz","url":"https://registry.npmjs.org/dunder-proto/-/dunder-proto-1.0.1.tgz","hash":"sha512-KIN/nDJBQRcXw0MLVhZE9iQHmG68qAVIBg9CqmUYjmQIhgij9U5MFvrqkUL5FbtyyzZuOeOt0zdeRe4UY7ct+A==","dependencies":{"gopd":"^1.2.0","es-errors":"^1.3.0","call-bind-apply-helpers":"^1.0.1"}}]
  '';
  runtimeInputs = { schemaVersion = 1; packages = npmPackages; };
  # Temporary supported runtime for the pinned app. Retire when an upstream
  # image contains these dependency fixes and passes actual runtime/native/
  # trust and current-data recovery checks.
  baseRuntime = helpers.mkNodeRuntimeImage {
    inherit name appVersion nodeVersion;
    upstreamImage = "ghcr.io/advplyr/audiobookshelf@sha256:37c2057e150694970442579815c646fe6bdc01c95b9d1547c4c9068be8844ef3";
    nodeSourceImage = "docker.io/library/node@sha256:4eefa1bfce4197942661ef9148247d779ddf1bb0ee006d3294a467609de60724";
  };
  runtime = helpers.mkRuntimeImage {
    inherit name;
    version = "${appVersion}-node${nodeVersion}";
    recipe = baseRuntime.recipe + ''
      # Fixed dependency inputs ${builtins.hashString "sha256" (builtins.toJSON runtimeInputs)}
      COPY npm/ /tmp/hwc-audiobookshelf-npm/
      RUN ${lib.concatMapStringsSep " && " (p: let destination = "/app/node_modules/${p.path}"; in "rm -rf ${lib.escapeShellArg destination} && mkdir -p ${lib.escapeShellArg destination} && tar -xzf ${lib.escapeShellArg "/tmp/hwc-audiobookshelf-npm/${p.file}"} -C ${lib.escapeShellArg destination} --strip-components=1 --no-same-owner") npmPackages} && rm -r /tmp/hwc-audiobookshelf-npm
    '';
  };
  runtimeManifest = pkgs.writeText "audiobookshelf-runtime-packages.json" (builtins.toJSON runtimeInputs);
  runtimeContext = pkgs.runCommand "audiobookshelf-runtime-context" {} ''
    mkdir -p "$out/npm"
    cp ${runtime.dockerfile} "$out/Dockerfile"
    cp ${runtimeManifest} "$out/manifest.json"
    ${lib.concatMapStrings (p: let source = pkgs.fetchurl { inherit (p) url hash; }; in ''
      cp ${source} "$out/npm/${p.file}"
    '') npmPackages}
  '';
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./sys.nix
    ./parts/config.nix
  ];

  options.hwc.media.audiobookshelf = {
    enable = mkEnableOption "Audiobookshelf audiobook and podcast server";

    dataDir = mkOption {
      type = types.str;
      default = "${paths.apps.root}/audiobookshelf/config";
      description = "Application configuration and SQLite database directory";
    };

    image = mkOption {
      type = types.str;
      default = cfg._runtimeImage;  # critical tier: immutable app/runtime inputs
      description = "Qualified application/runtime image built from system.build.audiobookshelfRuntimeImageContext";
    };

    _runtimeImage = mkOption {
      type = types.str;
      default = runtime.image;
      internal = true;
      readOnly = true;
      description = "Generated image identity shared with the container definition";
    };

    network.mode = mkOption {
      type = types.enum [ "media" "vpn" ];
      default = "media";
      description = "Network mode: media or vpn (through Gluetun)";
    };

    port = mkOption {
      type = types.int;
      default = (import ../../networking/ports.nix).audiobookshelf.port;
      description = "Port for Audiobookshelf web interface";
    };

    library = mkOption {
      type = types.path;
      default = toString paths.media.audiobooks;
      description = "Path to audiobooks library";
    };

    podcasts = mkOption {
      type = types.path;
      default = toString paths.media.podcasts;
      description = "Path to podcasts library";
    };

    metadata = mkOption {
      type = types.path;
      default = "${paths.media.books}/.audiobookshelf-metadata";
      description = "Path to store metadata (cover images, descriptions, etc.)";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    system.build.audiobookshelfRuntimeImageRecipe = runtime.dockerfile;
    system.build.audiobookshelfRuntimeImageContext = runtimeContext;
    systemd.services.podman-audiobookshelf.preStart = lib.mkIf (cfg.image == runtime.image) (lib.mkBefore ''
      ${pkgs.podman}/bin/podman image exists ${lib.escapeShellArg runtime.image} || {
        echo "Prebuild Audiobookshelf from ${runtimeContext} before activation" >&2
        exit 1
      }
    '');
    # Container definition is in sys.nix
    # Service dependencies are in parts/config.nix

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = helpers.mkVpnAssertions {
      name = "audiobookshelf";
      networkMode = cfg.network.mode;
      gluetunInstances = config.hwc.networking.gluetun.instances;
    } ++ [
      {
        assertion = config.hwc.paths.media.root != null;
        message = "audiobookshelf container requires hwc.paths.media.root to be defined";
      }
    ];
  };
}
