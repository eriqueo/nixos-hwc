{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.sonarr;
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  appVersion = "4.0.20.3014";
  runtimeVersion = "10.0.14";
  upstreamImage = "lscr.io/linuxserver/sonarr@sha256:386c962ee6e260e3a5656b25df2ed056bcc9b6410e197d075f9547fd14c23bca";
  archive = pkgs.fetchurl {
    url = "https://builds.dotnet.microsoft.com/dotnet/aspnetcore/Runtime/10.0.14/aspnetcore-runtime-10.0.14-linux-musl-x64.tar.gz";
    hash = "sha512-LPMIg8C6jKGpahWBpwcs7CKaGafcJVjInSqp2YmOLPiv6mu4489ZaHWFxm6tfauif+Yx4kHXKQ+7KUQl7XTFjg==";
  };
  # Temporary: the vendor still bundles EOL .NET 6. Remove this rehosting
  # boundary when its image uses a supported patched runtime and passes the
  # current-data old/new/old/new recovery and native SQLite/API checks.
  applyRuntimeText = ''
    set -eu
    cd /app/sonarr/bin
    printf '%s\n' '59249a28421932787ff6dc96904cacbc7126d8678a8592401651dff18d2e722b  Sonarr.deps.json' '76bb233960042c712ba12c5c7f2e86bfdd19d39d58ebb10a00cf3128a6f4aa6a  Sonarr.runtimeconfig.json' | sha256sum -c -
    # Ownership comes from the hash-bound vendor manifest. Never delete an
    # app-owned assembly even if a future vendor manifest changes ownership.
    jq -r '.targets[] | to_entries[] | select(.key | startswith("runtimepack.")) | .value | (.runtime // {}, .native // {}) | keys[]' Sonarr.deps.json | sort -u > /tmp/runtime-owned.txt
    jq -r '.targets[] | to_entries[] | select(.key | startswith("runtimepack.") | not) | .value | (.runtime // {}, .native // {}) | keys[]' Sonarr.deps.json | sort -u > /tmp/app-owned.txt
    test "$(wc -l < /tmp/runtime-owned.txt)" -eq 302
    test -z "$(comm -12 /tmp/runtime-owned.txt /tmp/app-owned.txt)"
    while IFS= read -r name; do
      case "$name" in ""|*/*|*..*) echo SONARR_RUNTIME_PATH_INVALID >&2; exit 1;; esac
      test -f "$name"
      rm -- "$name"
    done < /tmp/runtime-owned.txt
    jq '(.targets[] |= with_entries(select(.key | startswith("runtimepack.") | not))) | (.libraries |= with_entries(select(.key | startswith("runtimepack.") | not)))' Sonarr.deps.json > Sonarr.deps.json.new
    mv Sonarr.deps.json.new Sonarr.deps.json
    jq --arg version '${runtimeVersion}' '.runtimeOptions |= (del(.includedFrameworks) | .frameworks = [{name:"Microsoft.NETCore.App",version:$version},{name:"Microsoft.AspNetCore.App",version:$version}])' Sonarr.runtimeconfig.json > Sonarr.runtimeconfig.json.new
    mv Sonarr.runtimeconfig.json.new Sonarr.runtimeconfig.json
    mkdir -p /opt/hwc-dotnet
    tar -xzf /tmp/hwc-sonarr/runtime.tar.gz -C /opt/hwc-dotnet
    printf '%s\n' '#!/bin/sh' 'exec /opt/hwc-dotnet/dotnet /app/sonarr/bin/Sonarr.dll "$@"' > Sonarr
    chmod 0755 Sonarr
    case "$(/opt/hwc-dotnet/dotnet --list-runtimes)" in
      *"Microsoft.AspNetCore.App ${runtimeVersion} "*) ;; *) exit 1;;
    esac
    rm -r /tmp/hwc-sonarr /tmp/runtime-owned.txt /tmp/app-owned.txt
  '';
  applyRuntime = pkgs.writeText "sonarr-apply-runtime.sh" applyRuntimeText;
  runtime = helpers.mkRuntimeImage {
    name = "sonarr";
    version = "${appVersion}-dotnet${runtimeVersion}";
    recipe = ''
      FROM ${upstreamImage}
      # Bound payload: ${builtins.hashString "sha256" (applyRuntimeText + toString archive)}
      COPY . /tmp/hwc-sonarr/
      RUN sh /tmp/hwc-sonarr/apply-runtime.sh
    '';
  };
  runtimeContext = pkgs.runCommand "sonarr-runtime-context" {} ''
    mkdir -p "$out"
    cp ${runtime.dockerfile} "$out/Dockerfile"
    cp ${applyRuntime} "$out/apply-runtime.sh"
    cp ${archive} "$out/runtime.tar.gz"
  '';

in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.sonarr = {
    enable = lib.mkEnableOption "sonarr container";
    image = lib.mkOption { type = lib.types.str; default = runtime.image; description = "Qualified local image built from system.build.sonarrRuntimeImageContext"; };
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
    system.build.sonarrRuntimeImageRecipe = runtime.dockerfile;
    system.build.sonarrRuntimeImageContext = runtimeContext;
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Add assertions and validation logic here
}
