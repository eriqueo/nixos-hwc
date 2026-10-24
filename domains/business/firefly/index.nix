# domains/business/firefly/index.nix
#
# Firefly III Personal Finance Manager
# Includes both Firefly III core and Firefly-Pico mobile companion
{ lib, config, pkgs, inputs, ... }:

let
  cfg = config.hwc.business.firefly;
  paths = config.hwc.paths;
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  picoAppVersion = "1.10.1";
  picoNodeVersion = "22.23.4";
  picoOpenSSLVersion = "3.5.9-r0";
  picoCertificatesVersion = "20261020-r0";
  # Temporary same-app security correction. Retire when an upstream image
  # passes actual Node/shared-library/trust and current-data recovery checks.
  # Exact signed Alpine packages also fix PHP's real shared consumers.
  picoPackages = map (p: p // rec {
    file = "${p.name}-${p.version}.apk";
    url = "https://dl-cdn.alpinelinux.org/alpine/v3.22/main/x86_64/${file}";
    source = pkgs.fetchurl { inherit url; inherit (p) hash; };
  }) [
    { name = "c-ares"; version = "1.34.9-r0"; hash = "sha256-myOqB5Ae1kveC+fsVE+NKynegNmWJ33IYSGMVP/4vJc="; }
    { name = "brotli-libs"; version = "1.1.1-r0"; hash = "sha256-nlJhhFd2L2W/Jz9C1x24CEYzoenZOP8mEQFbog1EqM8="; }
    { name = "libcrypto3"; version = picoOpenSSLVersion; hash = "sha256-P1glztX94cZqU3aj9gdrPAhTitUtnvI/BphX4hLZF1o="; }
    { name = "libssl3"; version = picoOpenSSLVersion; hash = "sha256-aAHHQLl2C1sI2o22Nn68GLLMTbrzcfcUhClTi4uwTiM="; }
    { name = "ca-certificates"; version = picoCertificatesVersion; hash = "sha256-jddThpmWGSejYyfWIrO56fXJRP19SGoMuLa4M9x0z78="; }
    { name = "ca-certificates-bundle"; version = picoCertificatesVersion; hash = "sha256-01IWoKmt3nkDHfJGdZutA/I1zyAb8K/4Q2uIv/WVlOs="; }
  ];
  picoRuntime = helpers.mkRuntimeImage {
    name = "firefly-pico";
    version = "${picoAppVersion}-node${picoNodeVersion}";
    # Bind every APK byte selection to the recipe-derived image identity.
    recipe = lib.concatMapStrings (p: "# APK ${p.file} ${p.hash}\n") picoPackages + ''
      FROM docker.io/library/node@sha256:9fee3a1d85a49993660c8ffc774ceafadc0b52eda69b4c981f6b6a1cfabcfe98 AS secure-node
      FROM docker.io/cioraneanu/firefly-pico@sha256:2bc76980f6be5a4e36581dbed8c381e119a2318031d2f1cf5d9cb14b7286a633
      COPY *.apk /tmp/hwc-runtime-apks/
      RUN apk add --no-network --no-cache --repositories-file /dev/null /tmp/hwc-runtime-apks/*.apk && update-ca-certificates --fresh && rm -r /tmp/hwc-runtime-apks
      COPY --from=secure-node /usr/local/bin/node /usr/bin/node
      ENV NODE_VERSION=${picoNodeVersion}
    '';
  };
  picoManifest = pkgs.writeText "firefly-pico-runtime-manifest.json" (builtins.toJSON {
    schemaVersion = 1;
    packages = map (p: builtins.removeAttrs p [ "source" ]) picoPackages;
  });
  # REPLACEABLE: regenerated from fixed-hash package sources and the recipe.
  picoContext = pkgs.runCommand "firefly-pico-runtime-context" {} ''
    mkdir -p "$out"
    cp ${picoRuntime.dockerfile} "$out/Dockerfile"
    cp ${picoManifest} "$out/manifest.json"
    ${lib.concatMapStrings (p: "cp ${p.source} \"$out/${p.file}\"\n") picoPackages}
  '';
in
{
  # OPTIONS
  options.hwc.business.firefly = {
    enable = lib.mkEnableOption "Firefly III personal finance manager (containerized)";

    # Container images
    images = {
      core = lib.mkOption {
        type = lib.types.str;
        default = "docker.io/fireflyiii/core:version-6.6.6";  # critical tier (Law 15 v12.4): financial data — pinned
        description = "Firefly III core container image";
      };

      pico = lib.mkOption {
        type = lib.types.str;
        default = picoRuntime.image;  # critical tier: immutable app/runtime/library inputs
        description = "Qualified Pico image built from system.build.fireflyPicoRuntimeImageContext";
      };

      importer = lib.mkOption {
        type = lib.types.str;
        default = "docker.io/fireflyiii/data-importer:version-2.3.4";  # critical tier (Law 15 v12.4): financial data — pinned
        description = "Firefly III data importer container image";
      };
    };

    # Firefly III settings
    settings = {
      appUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://firefly.${config.hwc.networking.shared.vhostDomain}";
        description = "External URL for Firefly III (used for OAuth and redirects)";
      };

      timezone = lib.mkOption {
        type = lib.types.str;
        default = "America/Denver";
        description = "Timezone for Firefly III";
      };

      locale = lib.mkOption {
        type = lib.types.str;
        default = "en_US";
        description = "Default locale for Firefly III";
      };

      trustedProxies = lib.mkOption {
        type = lib.types.str;
        default = "**";
        description = ''
          Trusted proxy configuration.
          "**" trusts all proxies (safe behind Tailscale).
        '';
      };
    };

    # Firefly-Pico settings
    pico = {
      enable = lib.mkEnableOption "Firefly-Pico mobile companion" // { default = true; };

      appUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://firefly-pico.${config.hwc.networking.shared.vhostDomain}";
        description = "External URL for Firefly-Pico";
      };

      fireflyUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://firefly:8080";
        description = "Internal URL to Firefly III (container network)";
      };
    };

    # Data importer (CSV / SimpleFIN / GoCardless → Firefly III)
    importer = {
      enable = lib.mkEnableOption "Firefly III data importer" // { default = true; };

      appUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://firefly-import.${config.hwc.networking.shared.vhostDomain}";
        description = "External URL for the data importer";
      };

      fireflyUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://firefly:8080";
        description = "Internal URL to Firefly III (container network)";
      };

      internalPort = lib.mkOption {
        type = lib.types.port;
        default = 8087;
        description = "Internal HTTP port for the data importer container";
      };
    };

    # Workbench Finance area: recurring-payment explorer backed by Firefly's
    # REST API. The service is socket-activated behind Caddy and never exposes
    # a TCP listener of its own.
    explorer = {
      enable = lib.mkEnableOption "Firefly recurring-payment explorer" // { default = true; };

      package = lib.mkOption {
        type = lib.types.package;
        default = inputs.pnc-statement-pipeline.packages.${pkgs.stdenv.hostPlatform.system}.default;
        defaultText = "inputs.pnc-statement-pipeline.packages.<system>.default";
        description = "Immutable Firefly Explorer application package.";
      };

      appUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://firefly-explorer.${config.hwc.networking.shared.vhostDomain}";
        description = "Public same-origin URL used for CSRF validation.";
      };

      patFile = lib.mkOption {
        type = lib.types.str;
        default = "/run/agenix/firefly-explorer-pat";
        description = "Dedicated Firefly personal access token path.";
      };

      socketPath = lib.mkOption {
        type = lib.types.str;
        default = "/run/firefly-explorer.sock";
        description = "Root-owned Unix socket used only by Caddy.";
      };

      assetAccountId = lib.mkOption {
        type = lib.types.ints.positive;
        default = 12;
        description = "Firefly asset-account id explored by this app.";
      };

      accountName = lib.mkOption {
        type = lib.types.str;
        default = "Dad - Checking";
        description = "Account label shown in the explorer.";
      };

      historyStart = lib.mkOption {
        type = lib.types.strMatching "[0-9]{4}-[0-9]{2}-[0-9]{2}";
        default = "2019-08-19";
        description = "Earliest Firefly date fetched for recurrence analysis.";
      };

      allowedLogin = lib.mkOption {
        type = lib.types.str;
        default = "eriqueo@github";
        description = "Exact Tailscale WhoIs LoginName allowed to use the API.";
      };

      cacheSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 60;
        description = "Bounded in-memory Firefly read cache lifetime.";
      };

      protectedTags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "dad-pnc-statements" ];
        description = "Existing Firefly tags the explorer may never remove.";
      };

      coverageNote = lib.mkOption {
        type = lib.types.str;
        default = "Firefly includes imported activity from August 2019, with known bank-source gaps after 2023-12-18 and in early 2025 and early 2026.";
        description = "Visible warning explaining the limits of imported history.";
      };
    };

    # Automation timers (cron + daily digest into hwc-notify)
    automation = {
      cron = {
        enable = lib.mkEnableOption "Firefly III daily cron (recurring transactions, bills, auto-budgets)" // { default = true; };

        onCalendar = lib.mkOption {
          type = lib.types.str;
          default = "*-*-* 03:10:00";
          description = "systemd OnCalendar spec for the Firefly cron hit";
        };
      };

      digest = {
        enable = lib.mkEnableOption "daily finance digest posted to hwc-notify" // { default = true; };

        onCalendar = lib.mkOption {
          type = lib.types.str;
          default = "*-*-* 07:15:00";
          description = "systemd OnCalendar spec for the finance digest";
        };

        patFile = lib.mkOption {
          type = lib.types.str;
          default = "/run/agenix/firefly-pat";
          description = ''
            Path to a Firefly III personal access token. The digest exits
            cleanly (with a journal note) until this file exists, so the
            timer can ship before the token is provisioned.
          '';
        };
      };
    };

    # Database configuration
    database = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "10.89.0.1";  # media-network gateway
        description = "PostgreSQL host (containers can't use localhost)";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 5432;
        description = "PostgreSQL port";
      };

      name = lib.mkOption {
        type = lib.types.str;
        default = "firefly";
        description = "Database name for Firefly III";
      };

      picoName = lib.mkOption {
        type = lib.types.str;
        default = "firefly_pico";
        description = "Database name for Firefly-Pico";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "eric";
        description = "Database user";
      };
    };

    # Storage configuration
    storage = {
      dataDir = lib.mkOption {
        type = lib.types.path;
        default = "${paths.apps.root}/firefly";
        description = "Data directory for Firefly III";
      };

      uploadDir = lib.mkOption {
        type = lib.types.path;
        default = "${paths.apps.root}/firefly/upload";
        description = "Upload directory for Firefly III attachments";
      };
    };

    # Reverse proxy configuration (port mode)
    reverseProxy = {
      corePort = lib.mkOption {
        type = lib.types.port;
        default = 10443;
        description = "External TLS port for Firefly III";
      };

      coreInternalPort = lib.mkOption {
        type = lib.types.port;
        default = 8085;
        description = "Internal HTTP port for Firefly III container";
      };

      picoPort = lib.mkOption {
        type = lib.types.port;
        default = 11443;
        description = "External TLS port for Firefly-Pico";
      };

      picoInternalPort = lib.mkOption {
        type = lib.types.port;
        default = 8086;
        description = "Internal HTTP port for Firefly-Pico container";
      };
    };

    # Network configuration
    network = {
      mode = lib.mkOption {
        type = lib.types.enum [ "media" "host" ];
        default = "media";
        description = "Network mode: media (podman network) or host";
      };
    };

    # Resource limits
    resources = {
      core = {
        memory = lib.mkOption {
          type = lib.types.str;
          default = "1g";
          description = "Memory limit for Firefly III container";
        };

        cpus = lib.mkOption {
          type = lib.types.str;
          default = "1.0";
          description = "CPU limit for Firefly III container";
        };
      };

      pico = {
        memory = lib.mkOption {
          type = lib.types.str;
          default = "512m";
          description = "Memory limit for Firefly-Pico container";
        };

        cpus = lib.mkOption {
          type = lib.types.str;
          default = "0.5";
          description = "CPU limit for Firefly-Pico container";
        };
      };
    };
  };

  imports = [
    ./sys.nix
    ./parts/config.nix
    ./parts/automation.nix
    ./parts/explorer.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    system.build.fireflyPicoRuntimeImageContext = picoContext;
    system.build.fireflyPicoRuntimeImageRecipe = picoRuntime.dockerfile;
    # Keep explicit image overrides usable for compatible current-data recovery.
    # Prebuild during deployment; startup never builds or downloads an image.
    virtualisation.oci-containers.containers = lib.mkIf
      (cfg.pico.enable && cfg.images.pico == picoRuntime.image) {
        firefly-pico.pull = lib.mkForce "never";
      };
    systemd.services = lib.mkIf
      (cfg.pico.enable && cfg.images.pico == picoRuntime.image) {
        podman-firefly-pico.preStart = lib.mkBefore ''
          ${pkgs.podman}/bin/podman image exists ${lib.escapeShellArg picoRuntime.image} || {
            echo "Firefly-Pico requires the reviewed image from ${picoContext} before startup" >&2
            exit 1
          }
        '';
      };
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Assertions are defined in parts/config.nix alongside the implementation
}
