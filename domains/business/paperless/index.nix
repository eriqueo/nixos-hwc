{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.business.paperless;
  paths = config.hwc.paths;
  # Temporary browser patch: retire when a qualified vendor image includes
  # Chromium >=156.0.8078.79 and passes the Paperless conversion contracts.
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  gotenbergPackages = builtins.fromJSON ''
    [{"name":"chromium-common","version":"156.0.8078.79-1~deb13u1","file":"chromium-common_156.0.8078.79-1~deb13u1_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/c/chromium/chromium-common_156.0.8078.79-1~deb13u1_amd64.deb","hash":"sha256-KdmjMSO8xaukd0briactlzv3pzfjggQlx0lpBPcjX70="},{"name":"chromium","version":"156.0.8078.79-1~deb13u1","file":"chromium_156.0.8078.79-1~deb13u1_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/c/chromium/chromium_156.0.8078.79-1~deb13u1_amd64.deb","hash":"sha256-kyV3f7hC6vo/mSIJ7m8babrXbDMRqI79TXdyzsIuN5U="},{"name":"libnss3","version":"2:3.110-1+deb13u5","file":"libnss3_2%3a3.110-1+deb13u5_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/n/nss/libnss3_3.110-1+deb13u5_amd64.deb","hash":"sha256-cFmDkWXDnnNP9ZxxL96D716gEyiHKBnfur0cCOdfMRY="},{"name":"tzdata","version":"2026f-0+deb13u1","file":"tzdata_2026f-0+deb13u1_all.deb","url":"https://deb.debian.org/debian/pool/main/t/tzdata/tzdata_2026f-0+deb13u1_all.deb","hash":"sha256-LBxWEJFAKINDDQ1HxXo8CqALRK/IpiOSZQZahyEaXBE="}]
  '';
  gotenbergRuntime = helpers.mkRuntimeImage {
    name = "paperless-gotenberg";
    version = "8.39.0-chromium156.0.8078.79";
    recipe = ''
      FROM docker.io/gotenberg/gotenberg@sha256:5a9c6b8e5e65c35236f99ff1b55f16a3bbc2fb6d9518292a7c15ca433d5bab24
      # Fixed APT inputs ${builtins.hashString "sha256" (builtins.toJSON gotenbergPackages)}
      USER root
      COPY debian/ /tmp/hwc-gotenberg-debs/
      RUN DEBIAN_FRONTEND=noninteractive apt-get --no-download --yes -o Dir::Cache::archives=/tmp/hwc-gotenberg-debs -o Dpkg::Options::=--force-confold install /tmp/hwc-gotenberg-debs/*.deb && test -z "$(dpkg --audit)" && rm -r /tmp/hwc-gotenberg-debs
      USER gotenberg
    '';
  };
  gotenbergManifest = pkgs.writeText "gotenberg-runtime-packages.json" (builtins.toJSON gotenbergPackages);
  gotenbergContext = pkgs.runCommand "gotenberg-runtime-context" {} ''
    mkdir -p "$out/debian"
    cp ${gotenbergRuntime.dockerfile} "$out/Dockerfile"
    cp ${gotenbergManifest} "$out/manifest.json"
    ${lib.concatMapStrings (p: let source = pkgs.fetchurl { inherit (p) url hash; }; in ''
      cp ${source} "$out/debian/${p.file}"
    '') gotenbergPackages}
  '';
  # Keep the application/schema at 3.1.3 while its supported client speaks
  # Tika 4's fixed CXF and changed wire protocol. Remove this overlay when a
  # qualified vendor Paperless image includes tika-client >=2 and the actual
  # Office/mail/metadata and recovery contracts pass against Tika >=4.2.0.
  tikaClientWheel = pkgs.fetchurl {
    url = "https://files.pythonhosted.org/packages/81/fe/ee25b47093fc1a71fa49bffdf8ede1f6dc0fde3212fa3568fac20d63e2ac/tika_client-2.0.0-py3-none-any.whl";
    hash = "sha256-RN16UierLSW8iLj/KCA5YC6qwFkuVC7gSG2VNewb6bI=";
  };
  paperlessRuntime = helpers.mkRuntimeImage {
    name = "paperless";
    version = "3.1.3-tika-client2.0.0";
    recipe = ''
      FROM ghcr.io/paperless-ngx/paperless-ngx@sha256:aa810a36942c63d4ee70d00eda7236cd3d6acfb7eb3f7987fb568ed14df8817a
      # Fixed client wheel ${tikaClientWheel.outputHash}
      COPY tika_client-2.0.0-py3-none-any.whl /tmp/
      RUN python3 -m pip install --no-index --no-deps --no-cache-dir --force-reinstall /tmp/tika_client-2.0.0-py3-none-any.whl && rm /tmp/tika_client-2.0.0-py3-none-any.whl
    '';
  };
  paperlessContext = pkgs.runCommand "paperless-runtime-context" {} ''
    mkdir -p "$out"
    cp ${paperlessRuntime.dockerfile} "$out/Dockerfile"
    cp ${tikaClientWheel} "$out/tika_client-2.0.0-py3-none-any.whl"
  '';
in
{
  # OPTIONS
  options.hwc.business.paperless = {
    enable = lib.mkEnableOption "Paperless-NGX document management (containerized)";

    image = lib.mkOption {
      type = lib.types.str;
      # v3 renamed or requires several env vars (see parts/config.nix) and only
      # migrates a database already at 2.20.15 — do not jump from older 2.x.
      default = if cfg.officeIngest.enable then paperlessRuntime.image else "ghcr.io/paperless-ngx/paperless-ngx:3.1.3";
      description = "Paperless-NGX container image";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8102;
      description = "Internal HTTP port for Paperless";
    };

    network.mode = lib.mkOption {
      type = lib.types.enum [ "media" "host" ];
      default = "media";
      description = "Network mode for the container";
    };

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
        default = "paperless";
        description = "PostgreSQL database name";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "eric";
        description = "PostgreSQL user";
      };
    };

    redis = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "10.89.0.1";  # media-network gateway
        description = "Redis host";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 6379;
        description = "Redis port";
      };
    };

    storage = {
      consumeDir = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = if paths.hot.root != null then "${paths.hot.root}/documents/consume" else null;
        description = "Consume directory (drop zone for auto-import)";
      };

      exportDir = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = if paths.hot.root != null then "${paths.hot.root}/documents/export" else null;
        description = "Export directory";
      };

      stagingDir = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = if paths.hot.root != null then "${paths.hot.root}/documents/staging" else null;
        description = "Staging directory for pre-processing";
      };

      mediaDir = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = if paths.media.root != null then "${paths.media.root}/documents/paperless" else null;
        description = "Archive storage (originals, archive, thumbnails)";
      };

      dataDir = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = if paths.apps.root != null then "${paths.apps.root}/paperless/data" else null;
        description = "Paperless data directory (index, db cache)";
      };
    };

    ocr = {
      languages = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "eng" ];
        description = "Tesseract OCR language codes";
      };

      outputType = lib.mkOption {
        type = lib.types.enum [ "pdf" "pdfa" "pdfa-2" ];
        default = "pdfa";
        description = "OCR output format (pdf, pdfa, pdfa-2)";
      };

      # Ghostscript refuses to write a PDF/A copy of a PDF that breaks the
      # PDF/A rules — two Cancer Cell papers carry images with `Interpolate
      # true`, which PDF/A forbids — and ocrmypdf then fails the whole import.
      # This tells ocrmypdf to keep going after such a rejection, so the file
      # becomes a document. Only the archive copy can differ from the source;
      # the original file is stored either way. Upstream names this setting as
      # the fix for "Ghostscript PDF/A rendering failed" (docs/troubleshooting.md).
      continueOnSoftRenderError = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Import a PDF even when Ghostscript rejects its PDF/A archive copy";
      };

      # v3 default is "auto", which skips the archive copy for born-digital PDFs.
      # "always" keeps the v2 behaviour, where every document got a PDF/A archive.
      archiveFileGeneration = lib.mkOption {
        type = lib.types.enum [ "auto" "always" "never" ];
        default = "always";
        description = "When paperless creates a PDF/A archive copy (PAPERLESS_ARCHIVE_FILE_GENERATION)";
      };
    };

    consumer = {
      polling = lib.mkOption {
        type = lib.types.int;
        default = 60;
        description = "Seconds between consume folder scans";
      };

      deleteOriginals = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Delete originals after successful import";
      };

      # v2 rejected a file whose hash matched an existing document. v3 imports
      # it as a second document unless this is on, in which case the duplicate
      # is deleted from the consume dir. On keeps one document per file.
      deleteDuplicates = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Delete consume-dir files that duplicate an existing document instead of importing them";
      };

      # Subdirectory handling for bulk imports. With both on, a file dropped at
      # consume/230_admin/housing/lease.pdf is tagged `230_admin` and `housing`.
      # subdirsAsTags does nothing without recursive — paperless never looks
      # below the consume root — so the assertion in parts/config.nix ties them.
      recursive = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Consume files in subdirectories of the consume dir";
      };

      subdirsAsTags = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Tag consumed files with the names of their subdirectories";
      };
    };

    # Office-document ingest. Paperless parses PDFs and images on its own and
    # SKIPS everything else, silently — a .docx dropped in the consume dir is
    # not an error, it just never becomes a document. Tika extracts the text and
    # metadata; Gotenberg renders the file to PDF for the archive copy. Both are
    # sidecars on the private bridge reached by container DNS, so they publish no host
    # port and claim nothing in domains/networking/routes.nix.
    officeIngest = {
      enable = lib.mkEnableOption "Tika + Gotenberg sidecars for Office document ingest" // { default = true; };

      tikaImage = lib.mkOption {
        type = lib.types.str;
        default = "docker.io/apache/tika@sha256:b99f19c4fd76237dafe7d22f719b9bddfa9a449da687c597a41e2f6d9a595418"; # 4.2.0, CXF 4.2.4
        description = "Apache Tika server container image";
      };

      gotenbergImage = lib.mkOption {
        type = lib.types.str;
        # Qualified with the installed Paperless client: HTML/DOCX -> PDF/A-2B.
        default = gotenbergRuntime.image;
        description = "Gotenberg container image";
      };
    };

    # Mail ingest: expose Proton Bridge IMAP (loopback-only) on the podman
    # gateway so the paperless container's mail fetcher can poll it.
    mailIngest = {
      enable = lib.mkEnableOption "IMAP proxy for paperless mail ingest (Proton Bridge → podman gateway)" // { default = true; };

      gatewayAddr = lib.mkOption {
        type = lib.types.str;
        default = "10.89.0.1";
        description = "Podman media-network gateway address to bind the IMAP proxy on";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 1143;
        description = "IMAP port (same on loopback source and gateway bind)";
      };
    };

    # Phone receipts: watch the Syncthing mobile-inbox receipts folder and
    # move drops into the consume dir for OCR ingestion.
    serverAlias = lib.mkOption {
      type = lib.types.str;
      default = "work";  # service split wave 3
      description = ''
        hwc.networking.hosts alias of the host that runs Paperless. A receipts
        watcher on another host forwards into that host's consume dir, read
        from its evaluated config (one producer of the path).
      '';
    };
    receipts = {
      # Independent of `enable`: it runs on the host that holds the phone
      # folder, which need not be the host that runs Paperless.
      enable = lib.mkEnableOption "the phone receipts folder watcher (enable on the host that holds receipts.mobileDir)";

      mobileDir = lib.mkOption {
        type = lib.types.str;
        default = "/mnt/vaults/inbox-mobile/receipts";
        description = "Phone-synced folder watched for receipt photos/PDFs";
      };
    };

    admin = {
      user = lib.mkOption {
        type = lib.types.str;
        default = "eric";
        description = "Initial admin username";
      };

      email = lib.mkOption {
        type = lib.types.str;
        default = "eric@hwc.local";
        description = "Initial admin email";
      };
    };

    reverseProxy = {
      path = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = ''
          Reverse proxy subpath. Empty is correct for the current name-based
          vhost (paperless.<vhostDomain>), where paperless serves at root; the
          option stays so it can be put back behind a prefix without a code
          change. When non-empty it emits PAPERLESS_FORCE_SCRIPT_NAME, which
          Django uses to prefix every generated URL — so it must match the
          route's `path` exactly or the app links to pages that do not route.
        '';
      };
    };

    resources = {
      memory = lib.mkOption {
        type = lib.types.str;
        default = "4g";
        description = "Memory limit for Paperless container";
      };

      cpus = lib.mkOption {
        type = lib.types.str;
        default = "2.0";
        description = "CPU limit for Paperless container";
      };
    };

    retention = {
      cleanup = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable Paperless staging/export cleanup timer";
        };

        schedule = lib.mkOption {
          type = lib.types.str;
          default = "daily";
          description = "systemd OnCalendar schedule for cleanup";
        };

        stagingDays = lib.mkOption {
          type = lib.types.int;
          default = 7;
          description = "Delete staging files older than N days";
        };

        exportDays = lib.mkOption {
          type = lib.types.int;
          default = 30;
          description = "Delete export files older than N days";
        };
      };
    };
  };

  imports = [
    ./sys.nix
    ./parts/config.nix
    ./parts/directories.nix
    ./parts/receipts.nix
  ];

  #=========================================================================
  # IMPLEMENTATION
  #=========================================================================
  config = lib.mkIf cfg.enable {
    system.build.paperlessRuntimeImageContext = paperlessContext;
    system.build.paperlessRuntimeImageRecipe = paperlessRuntime.dockerfile;
    system.build.gotenbergRuntimeImageContext = gotenbergContext;
    system.build.gotenbergRuntimeImageRecipe = gotenbergRuntime.dockerfile;
    virtualisation.oci-containers.containers = lib.mkMerge [
      (lib.mkIf (cfg.image == paperlessRuntime.image) {
        paperless.pull = lib.mkForce "never";
      })
      (lib.mkIf
      (cfg.officeIngest.enable && cfg.officeIngest.gotenbergImage == gotenbergRuntime.image) {
      paperless-gotenberg.pull = lib.mkForce "never";
      })
    ];
    systemd.services.podman-paperless = lib.mkIf (cfg.image == paperlessRuntime.image) {
      preStart = lib.mkBefore ''
        ${pkgs.podman}/bin/podman image exists ${lib.escapeShellArg paperlessRuntime.image} || {
          echo "Paperless requires the qualified client image from ${paperlessContext}" >&2
          exit 1
        }
      '';
    };
    systemd.services.podman-paperless-gotenberg = lib.mkIf
      (cfg.officeIngest.enable && cfg.officeIngest.gotenbergImage == gotenbergRuntime.image) {
      preStart = lib.mkBefore ''
        ${pkgs.podman}/bin/podman image exists ${lib.escapeShellArg gotenbergRuntime.image} || {
          echo "Gotenberg requires the qualified image from ${gotenbergContext}" >&2
          exit 1
        }
      '';
    };
  };

  #=========================================================================
  # VALIDATION
  #=========================================================================
  # Add assertions and validation logic here
}
