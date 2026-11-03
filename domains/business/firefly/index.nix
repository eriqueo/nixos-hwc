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
  picoPhpVersion = "8.2.35-r0";
  phpVersion = "8.5.12";
  # Temporary same-app PHP correction: retire once qualified upstream images
  # preserve the current app/schema and meet the PHP security floor.
  # The donor supplies PHP and its extensions only, never application bytes.
  phpRuntimeDonor = "docker.io/fireflyiii/core@sha256:321dc39c1d956aaf67d8adbfa48485190361d6d51640bafb9c029c48f296374d";
  # Same-release vendor security updates, authenticated by APT during acquisition.
  # Temporary: remove with the runtime overlay once upstream passes qualification.
  debianManifest = ./debian-runtime-packages.json;
  debianPackages = map (p: p // {
    source = pkgs.fetchurl { inherit (p) url hash; };
  }) (builtins.fromJSON (builtins.readFile debianManifest));
  phpRuntimes = lib.mapAttrs (_: app: helpers.mkRuntimeImage {
    name = app.name;
    version = "${app.version}-php${phpVersion}";
    recipe = ''
      # Debian package selection ${builtins.hashFile "sha256" debianManifest}
      FROM ${phpRuntimeDonor} AS secure-php
      FROM ${app.image}
      USER root
      COPY *.deb /tmp/hwc-runtime-debs/
      RUN DEBIAN_FRONTEND=noninteractive apt-get --no-download --yes -o Dpkg::Options::=--force-confold install /tmp/hwc-runtime-debs/*.deb && test -z "$(dpkg --audit)" && rm -r /tmp/hwc-runtime-debs
      COPY --from=secure-php /usr/local/bin/php /usr/local/bin/php-config /usr/local/bin/phpize /usr/local/bin/
      COPY --from=secure-php /usr/local/sbin/php-fpm /usr/local/sbin/php-fpm
      COPY --from=secure-php /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
      ENV PHP_VERSION=${phpVersion} PHP_URL=https://www.php.net/distributions/php-${phpVersion}.tar.xz PHP_ASC_URL=https://www.php.net/distributions/php-${phpVersion}.tar.xz.asc PHP_SHA256=08bc2eba2a588654ade1357174aa646b761556c862dda0678345ee29ed481209
      USER www-data
    '';
  }) {
    core = {
      name = "firefly";
      version = "6.6.6";
      image = "docker.io/fireflyiii/core@sha256:6515902b1a7c5b9a0b0a3b4db02a4c917aef7b3152a65d14aace5faf0ffee0bc";
    };
    importer = {
      name = "firefly-importer";
      version = "2.3.4";
      image = "docker.io/fireflyiii/data-importer@sha256:ca64bb047cc9a0fc261af0ca07fe74e01bb0a0d5e9a0a3564248c69620a2c7e9";
    };
  };
  # Temporary same-app security correction. Retire when an upstream image
  # passes actual Node/shared-library/trust and current-data recovery checks.
  # Exact signed Alpine packages also fix PHP's real shared consumers.
  picoPackages = map (p: p // rec {
    file = "${p.name}-${p.version}.apk";
    url = "https://dl-cdn.alpinelinux.org/alpine/v3.22/${p.repository or "main"}/x86_64/${file}";
    source = pkgs.fetchurl { inherit url; inherit (p) hash; };
  }) ((builtins.fromJSON (builtins.readFile ./alpine-runtime-packages.json)) ++ [
    { name = "c-ares"; version = "1.34.9-r0"; hash = "sha256-myOqB5Ae1kveC+fsVE+NKynegNmWJ33IYSGMVP/4vJc="; }
    { name = "brotli-libs"; version = "1.1.1-r0"; hash = "sha256-nlJhhFd2L2W/Jz9C1x24CEYzoenZOP8mEQFbog1EqM8="; }
    { name = "libcrypto3"; version = picoOpenSSLVersion; hash = "sha256-P1glztX94cZqU3aj9gdrPAhTitUtnvI/BphX4hLZF1o="; }
    { name = "libssl3"; version = picoOpenSSLVersion; hash = "sha256-aAHHQLl2C1sI2o22Nn68GLLMTbrzcfcUhClTi4uwTiM="; }
    { name = "ca-certificates"; version = picoCertificatesVersion; hash = "sha256-jddThpmWGSejYyfWIrO56fXJRP19SGoMuLa4M9x0z78="; }
    { name = "ca-certificates-bundle"; version = picoCertificatesVersion; hash = "sha256-01IWoKmt3nkDHfJGdZutA/I1zyAb8K/4Q2uIv/WVlOs="; }
    { name = "php82"; version = picoPhpVersion; repository = "community"; hash = "sha256-XbwjF26fwQjBXdSoAdy0K6ZOoJBbwB5E+5XKqzCMm28="; }
    { name = "php82-common"; version = picoPhpVersion; repository = "community"; hash = "sha256-kpxuWa2IhAaVjRdR0rig4JH5l1/M2Z/0ChGm6Z/kMEU="; }
    { name = "php82-ctype"; version = picoPhpVersion; repository = "community"; hash = "sha256-YYRQaDsT9HOJbW1BKtgbVZr7pHM3oYAszlLhsIvAy5c="; }
    { name = "php82-curl"; version = picoPhpVersion; repository = "community"; hash = "sha256-Y84JNVNa2N5PlB6SktW3Go/UrJt+Ncm21w830c5H2Sc="; }
    { name = "php82-dom"; version = picoPhpVersion; repository = "community"; hash = "sha256-Z34TXl2qvYjTNMgICGq9pVNtLGbCoRyF1CExFpB2cAc="; }
    { name = "php82-fileinfo"; version = picoPhpVersion; repository = "community"; hash = "sha256-ZYEByJ8ayO60fqnEJS6TRs554Np6owxx8howr8BCQbE="; }
    { name = "php82-fpm"; version = picoPhpVersion; repository = "community"; hash = "sha256-iVwLOt5yyA0ZRLbVJY7PxbGlCmiWXON1R7rmOYOEiag="; }
    { name = "php82-iconv"; version = picoPhpVersion; repository = "community"; hash = "sha256-s9rGHwvwNLK6kVpTC2977XbEc886IYi6A1AG/uu6nzs="; }
    { name = "php82-mbstring"; version = picoPhpVersion; repository = "community"; hash = "sha256-Akh5BY8uy/kps7ic/RuwirsKkwSXdKIHZKxKLK/Cynw="; }
    { name = "php82-mysqlnd"; version = picoPhpVersion; repository = "community"; hash = "sha256-kYIRmcwBxlnlky6/+BQxG+xjO5OZg3HxQ37vt+uFNEo="; }
    { name = "php82-opcache"; version = picoPhpVersion; repository = "community"; hash = "sha256-oIRCt4VuIo67pACZIFGdzdfS1x8yRPX+nyZuKBubvgs="; }
    { name = "php82-openssl"; version = picoPhpVersion; repository = "community"; hash = "sha256-QU8Z/r6psS++QZDvXGzBKpYK5FaJNmpPH0ZjgdHFAtg="; }
    { name = "php82-pdo"; version = picoPhpVersion; repository = "community"; hash = "sha256-rSVlF2OIVixZfu2T/M2NAY9pQIiddUl7SlkoBhMDgxU="; }
    { name = "php82-pdo_mysql"; version = picoPhpVersion; repository = "community"; hash = "sha256-/43YZBzyQz56pPhLuNcXnJk0bHIyoMAo2g18uZ/yKLk="; }
    { name = "php82-pdo_pgsql"; version = picoPhpVersion; repository = "community"; hash = "sha256-qRj+TsDCHattj2fQkVT9u4EgvuZQ6rrABdToWHKRk2Y="; }
    { name = "php82-pdo_sqlite"; version = picoPhpVersion; repository = "community"; hash = "sha256-Aam3CVO3qswFRwch41xY+pI5/b4MUas/aik9TKdyPGU="; }
    { name = "php82-phar"; version = picoPhpVersion; repository = "community"; hash = "sha256-A4RbWaLFuAAWqo1daXR/PgOduFChHQrNncBpC55eDYc="; }
    { name = "php82-session"; version = picoPhpVersion; repository = "community"; hash = "sha256-TNy/8961HYO5DpEgwvvgRgzyjP98ASRgtYHEeJaC9vY="; }
    { name = "php82-simplexml"; version = picoPhpVersion; repository = "community"; hash = "sha256-PJyaPWBZRgSIP1lkIfI2wZ8i6Vq+MHqpSsD/8AiLris="; }
    { name = "php82-tokenizer"; version = picoPhpVersion; repository = "community"; hash = "sha256-YcQxIbWdmJwC/Zs8ZcVO+zpuuOs/jVGOOYIfpZgCGbw="; }
    { name = "php82-xml"; version = picoPhpVersion; repository = "community"; hash = "sha256-eSK44JhAUyATlcNBKZZO0po2jdIsxbJ13drCEnuata4="; }
    { name = "php82-xmlwriter"; version = picoPhpVersion; repository = "community"; hash = "sha256-C4BumwxAcKlQ2KiTLMb4QT/nlbc+P8tsoyO7MJu1i/Q="; }
    { name = "php82-zip"; version = picoPhpVersion; repository = "community"; hash = "sha256-aQn/UFHlZU8goo8SFB19Bbxg/E8dv6fs5URmT0iOI+c="; }
  ]);
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
        default = phpRuntimes.core.image;  # critical tier: same app, qualified PHP runtime
        description = "Firefly III core container image";
      };

      pico = lib.mkOption {
        type = lib.types.str;
        default = picoRuntime.image;  # critical tier: immutable app/runtime/library inputs
        description = "Qualified Pico image built from system.build.fireflyPicoRuntimeImageContext";
      };

      importer = lib.mkOption {
        type = lib.types.str;
        default = phpRuntimes.importer.image;  # critical tier: same app, qualified PHP runtime
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
    system.build.fireflyCoreRuntimeImageContext = pkgs.runCommand "firefly-core-runtime-context" {} ''
      mkdir -p "$out"
      cp ${phpRuntimes.core.dockerfile} "$out/Dockerfile"
      cp ${debianManifest} "$out/manifest.json"
      ${lib.concatMapStrings (p: "cp ${p.source} \"$out/${p.file}\"\n") debianPackages}
    '';
    system.build.fireflyImporterRuntimeImageContext = pkgs.runCommand "firefly-importer-runtime-context" {} ''
      mkdir -p "$out"
      cp ${phpRuntimes.importer.dockerfile} "$out/Dockerfile"
      cp ${debianManifest} "$out/manifest.json"
      ${lib.concatMapStrings (p: "cp ${p.source} \"$out/${p.file}\"\n") debianPackages}
    '';
    system.build.fireflyPicoRuntimeImageContext = picoContext;
    system.build.fireflyPicoRuntimeImageRecipe = picoRuntime.dockerfile;
    # Keep explicit image overrides usable for compatible current-data recovery.
    # Prebuild during deployment; startup never builds or downloads an image.
    virtualisation.oci-containers.containers = lib.mkMerge (
      lib.mapAttrsToList (kind: runtime: lib.mkIf ((kind == "core" || cfg.importer.enable) && cfg.images.${kind} == runtime.image) {
        ${if kind == "core" then "firefly" else "firefly-importer"}.pull = lib.mkForce "never";
      }) phpRuntimes ++ [
        (lib.mkIf (cfg.pico.enable && cfg.images.pico == picoRuntime.image) {
          firefly-pico.pull = lib.mkForce "never";
        })
      ]);
    systemd.services = lib.mkMerge (
      lib.mapAttrsToList (kind: runtime: lib.mkIf ((kind == "core" || cfg.importer.enable) && cfg.images.${kind} == runtime.image) {
        ${if kind == "core" then "podman-firefly" else "podman-firefly-importer"}.preStart = lib.mkBefore ''
          ${pkgs.podman}/bin/podman image exists ${lib.escapeShellArg runtime.image} || {
            echo "Firefly ${kind} requires its reviewed PHP runtime image before startup" >&2
            exit 1
          }
        '';
      }) phpRuntimes ++ [
        (lib.mkIf (cfg.pico.enable && cfg.images.pico == picoRuntime.image) {
          podman-firefly-pico.preStart = lib.mkBefore ''
            ${pkgs.podman}/bin/podman image exists ${lib.escapeShellArg picoRuntime.image} || {
              echo "Firefly-Pico requires the reviewed image from ${picoContext} before startup" >&2
              exit 1
            }
          '';
        })
      ]);
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Assertions are defined in parts/config.nix alongside the implementation
}
