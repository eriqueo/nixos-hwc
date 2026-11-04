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
  # Temporary: Alpine 3.24 still ships 3.53.4. Remove when that branch's
  # signed sqlite-libs includes the 3.54 fixes and passes current-data recovery.
  sqliteNative = pkgs.pkgsMusl.stdenv.mkDerivation {
    pname = "sonarr-sqlite-native";
    version = "3.54.1";
    src = pkgs.fetchurl {
      url = "https://sqlite.org/2026/sqlite-autoconf-3540100.tar.gz";
      hash = "sha256-km740+q5P79uBgEZASc+7AdrJVlKThza3VDJh/T21k4=";
    };
    nativeBuildInputs = [ pkgs.patchelf ];
    # Reuse the pinned package's feature vocabulary; do not create a second list.
    env.NIX_CFLAGS_COMPILE = pkgs.pkgsMusl.sqlite.NIX_CFLAGS_COMPILE;
    dontConfigure = true;
    buildPhase = ''
      runHook preBuild
      $CC -fPIC -shared -O2 sqlite3.c -Wl,-soname,libsqlite3.so.0 -o libsqlite3.so.0 -lm
      runHook postBuild
    '';
    installPhase = ''
      mkdir -p "$out/lib"
      cp libsqlite3.so.0 "$out/lib/"
    '';
    postFixup = ''
      # Alpine and Nix name musl's same ABI differently; use the target's name.
      patchelf --replace-needed libc.so libc.musl-x86_64.so.1 --remove-rpath "$out/lib/libsqlite3.so.0"
    '';
  };
  dependencyInputs = builtins.fromJSON ''
{"schemaVersion":1,"nuget":[{"name":"SixLabors.ImageSharp","version":"3.2.0","url":"https://api.nuget.org/v3-flatcontainer/sixlabors.imagesharp/3.2.0/sixlabors.imagesharp.3.2.0.nupkg","hash":"sha256-MeTyx2EoMmytE5XUl+COl2JBWQFvyVBktG9ig9hbtE0=","dependencies":{},"asset":"lib/net6.0/SixLabors.ImageSharp.dll","sha512":"5h7v5TVMDuu1jKHCuI7l1Oy1MrrERA8d4fFM3AHRrfuu/lfC44RN1+/wFJ01u3uzXb2pc2jC3ex+ZMsgDcqZPg==","dllSha256":"60d345f55451db74bbefb3231950c2524c12fe038173b08dabce4a844f22b179"},{"name":"System.Text.Json","version":"6.0.10","url":"https://api.nuget.org/v3-flatcontainer/system.text.json/6.0.10/system.text.json.6.0.10.nupkg","hash":"sha256-UijYh0dxFjFinMPSTJob96oaRkNm+Wsa+7Ffg6mRnsc=","dependencies":{"System.Runtime.CompilerServices.Unsafe":"6.0.0","System.Text.Encodings.Web":"6.0.0"},"asset":"lib/net6.0/System.Text.Json.dll","sha512":"CaQcnKNSM0DnDcAldC/sEv6XnodjeOb4pl2ebxjkEXkDIq393oh6d7FqKsTaDExNflMamwF6BBksReZQ3ljibQ==","dllSha256":"1546a1a36e7a94b944d7754d57b00d31abb8afbc3fd21d069685f0b7461196cb"},{"name":"System.Security.Cryptography.Pkcs","version":"8.0.2","url":"https://api.nuget.org/v3-flatcontainer/system.security.cryptography.pkcs/8.0.2/system.security.cryptography.pkcs.8.0.2.nupkg","hash":"sha256-NytlLOsMNKd+/2U4HvJDW5vJPoJhIWz13nEfx9nqcgA=","dependencies":{"System.Formats.Asn1":"8.0.2"},"asset":"lib/net6.0/System.Security.Cryptography.Pkcs.dll","sha512":"b7bL+Ge4ysa+tTvMmCF4kH4dV9cHTchWUgWCWOwEpoUjEn0jS+YOsKelvrtdTEemF9w6qCJtgsPoNFntBkSsRg==","dllSha256":"9adabedab3e739f8c689c8b3cf688d3d2c0b8ff787e1e7e649e39926353fe878"},{"name":"Microsoft.IdentityModel.JsonWebTokens","version":"6.36.0","url":"https://api.nuget.org/v3-flatcontainer/microsoft.identitymodel.jsonwebtokens/6.36.0/microsoft.identitymodel.jsonwebtokens.6.36.0.nupkg","hash":"sha256-oqh2tUnCvSgJgh/q2OOi0gacEftQ6UcS8EVSawev2Yw=","dependencies":{"Microsoft.IdentityModel.Tokens":"6.36.0"},"asset":"lib/net6.0/Microsoft.IdentityModel.JsonWebTokens.dll","sha512":"aE1/AeaMAY6QHLtVbU00iJp2ahN8h6qtxhYm2n3gj3ABW0RyqtgKcWwA1cZj25GqJEDlSv8XsbMU5AL1EhLE0w==","dllSha256":"0f3423ef4fe42d41fc41dde31e9ba73c7ebe2a6e966ef0c06d519ed7aa54556f"},{"name":"Microsoft.IdentityModel.Logging","version":"6.36.0","url":"https://api.nuget.org/v3-flatcontainer/microsoft.identitymodel.logging/6.36.0/microsoft.identitymodel.logging.6.36.0.nupkg","hash":"sha256-tPf3KaXBUAJ1Ot5OOZNDgw0zvSFg8ETPF0brnFc88cc=","dependencies":{"Microsoft.IdentityModel.Abstractions":"6.36.0"},"asset":"lib/net6.0/Microsoft.IdentityModel.Logging.dll","sha512":"Wl7NsaKNg2+2eIV0n8etB4SZd/plcv00tO/k89c67U86zHjwkX4NSb9tlJBjbzlIv0c45IAOM5JhUWahemPvYA==","dllSha256":"7c5efdfa85d6ad4be4d469c3308a944ee74c735930c9ad062ee19d19c2f2f6d0"},{"name":"Microsoft.IdentityModel.Protocols","version":"6.36.0","url":"https://api.nuget.org/v3-flatcontainer/microsoft.identitymodel.protocols/6.36.0/microsoft.identitymodel.protocols.6.36.0.nupkg","hash":"sha256-9gEc4Cf8TAfw0LMml0NPOuPg5m3HLKQO+Bn4Zlme4LM=","dependencies":{"Microsoft.IdentityModel.Logging":"6.36.0","Microsoft.IdentityModel.Tokens":"6.36.0"},"asset":"lib/net6.0/Microsoft.IdentityModel.Protocols.dll","sha512":"iIVrtmrBbwKwdu53W6lT7mRNeX5cGyrj+92T+KNBlgY8I4f8LHNzoce//zmoW6Wy6mW9ld2ENQbehzoqzYcm7g==","dllSha256":"78fdb1220fae418f15c62eff37e389924be71cc8074e8a6b35da2f7eda44b65a"},{"name":"Microsoft.IdentityModel.Protocols.OpenIdConnect","version":"6.36.0","url":"https://api.nuget.org/v3-flatcontainer/microsoft.identitymodel.protocols.openidconnect/6.36.0/microsoft.identitymodel.protocols.openidconnect.6.36.0.nupkg","hash":"sha256-eDd4LlsG2I3M8V5R8udeJo9IfwLsBIO137mRO60WeSs=","dependencies":{"Microsoft.IdentityModel.Protocols":"6.36.0","System.IdentityModel.Tokens.Jwt":"6.36.0"},"asset":"lib/net6.0/Microsoft.IdentityModel.Protocols.OpenIdConnect.dll","sha512":"yVL3z7fuvpKGFmTCwoG+BEwIccCPsVAIaswEUmmwn2TiPTNV7Al6k4YbUopN+MW49u3CJdLtMMPI441ka8oh+Q==","dllSha256":"41a5a6b903816670f15870db1840136466faefb7b1230c7b42d2420fc3f6f005"},{"name":"Microsoft.IdentityModel.Tokens","version":"6.36.0","url":"https://api.nuget.org/v3-flatcontainer/microsoft.identitymodel.tokens/6.36.0/microsoft.identitymodel.tokens.6.36.0.nupkg","hash":"sha256-0hVk4HUGcxzOlrI2L9G6HBwaVSsa0k0wNd6ETNRvyL0=","dependencies":{"Microsoft.IdentityModel.Logging":"6.36.0","Microsoft.CSharp":"4.5.0","System.Security.Cryptography.Cng":"4.5.0"},"asset":"lib/net6.0/Microsoft.IdentityModel.Tokens.dll","sha512":"F81jfcaWSG2HSK7GqBM8mP4MATMXh38/Ew9EUKo0Gh9bqx5hfb1NOnOUiQfCy8WAm3YNQdXT6HUX7gHoNL42vQ==","dllSha256":"2c53c0466031c668ccb78cf0d6c66e648125d1fdd25ca08987d25f806bab6c50"},{"name":"Microsoft.IdentityModel.Abstractions","version":"6.36.0","url":"https://api.nuget.org/v3-flatcontainer/microsoft.identitymodel.abstractions/6.36.0/microsoft.identitymodel.abstractions.6.36.0.nupkg","hash":"sha256-4jnbHNxwAlzyrpWTqRbsbPNKEhih8PYnbJvluuv6eNs=","dependencies":{},"asset":"lib/net6.0/Microsoft.IdentityModel.Abstractions.dll","sha512":"wwy1M1iFUCJzOz8kiyToD0cshUgNcpxAOvYliRZklplxlW0qdB7jqGObvXlJkqKeK22CM5Ugs9b5W48lxiPA6Q==","dllSha256":"e6a6a1592dea2efb426773c30df4c8c7d1fb47486d70b2a915b0f27fe9ea8c1a"},{"name":"System.IdentityModel.Tokens.Jwt","version":"6.36.0","url":"https://api.nuget.org/v3-flatcontainer/system.identitymodel.tokens.jwt/6.36.0/system.identitymodel.tokens.jwt.6.36.0.nupkg","hash":"sha256-lxO4xMZjjb4NXfD+r+Ydiq/3BC62fx4lG9qx4k5/Vks=","dependencies":{"Microsoft.IdentityModel.JsonWebTokens":"6.36.0","Microsoft.IdentityModel.Tokens":"6.36.0"},"asset":"lib/net6.0/System.IdentityModel.Tokens.Jwt.dll","sha512":"8Yc5Jc0bQP5JKfLZ2jd6l0ypHn+sBJ+tQtmHinBYK85q0ZeDX2OCUuSpSSl6rR3RCzGT+oeKvcS0zzjhMVcfqQ==","dllSha256":"c1466f994356a36cb120246eda642981627415f176747ee523cd869867628d5c"},{"name":"System.Formats.Asn1","version":"8.0.2","url":"https://api.nuget.org/v3-flatcontainer/system.formats.asn1/8.0.2/system.formats.asn1.8.0.2.nupkg","hash":"sha256-TVoJN39csCza2XtzLEJ4zTis9CC5FFN5OqvIwhPkON8=","dependencies":{},"asset":"lib/net6.0/System.Formats.Asn1.dll","sha512":"X/gV01xizlbDzBXcO7rD78pC4kacScwKw1jp2RV5gvdVxThB3H1HNPzgPQCf20w5ePrLXEpeII2cSJf1e2GOcQ==","dllSha256":"d1f9e4d62664a43b348df6c3a27e49855790bc34ccc4b6282e77f8299fec7caa"}],"apks":[{"name":"curl","version":"8.23.0-r0","url":"https://dl-cdn.alpinelinux.org/alpine/v3.24/main/x86_64/curl-8.23.0-r0.apk","hash":"sha256-UxrimEUaTBxE9WP8Oy7twsHX4KJqM738Dv5vqv9qWUI=","file":"curl.apk"},{"name":"libcurl","version":"8.23.0-r0","url":"https://dl-cdn.alpinelinux.org/alpine/v3.24/main/x86_64/libcurl-8.23.0-r0.apk","hash":"sha256-H3DKQEgYgFpkZbYVu/6E74YUiKlj1+YwEI69f7qlFmU=","file":"libcurl.apk"}]}
  '';
  dependencyManifest = pkgs.writeText "sonarr-dependencies.json" (builtins.toJSON dependencyInputs.nuget);
  updateDepsText = ''
$packages[0] as $ps |
def package($name): first($ps[] | select(.name==$name));
def target($p): {dependencies:$p.dependencies,runtime:{($p.asset):{}}};
def library($p): {type:"package",serviceable:true,sha512:("sha512-"+$p.sha512),path:(($p.name|ascii_downcase)+"/"+$p.version),hashPath:(($p.name|ascii_downcase)+"."+$p.version+".nupkg.sha512")};
(.targets[] |= (with_entries(
 (.key | split("/")[0]) as $name |
 if any($ps[]; .name==$name) then package($name) as $p | .key=($p.name+"/"+$p.version) | .value=target($p) else . end
) | if has("Microsoft.IdentityModel.Logging/"+package("Microsoft.IdentityModel.Logging").version) then package("Microsoft.IdentityModel.Abstractions") as $p | . + {($p.name+"/"+$p.version):target($p)} else . end
| .[] |= (if has("dependencies") then .dependencies |= with_entries(.key as $name | if any($ps[];.name==$name) then .value=package($name).version else . end) else . end))) |
(.libraries |= (with_entries(
 (.key | split("/")[0]) as $name |
 if any($ps[];.name==$name) then package($name) as $p | .key=($p.name+"/"+$p.version) | .value=library($p) else . end
) | if has("Microsoft.IdentityModel.Logging/"+package("Microsoft.IdentityModel.Logging").version) then package("Microsoft.IdentityModel.Abstractions") as $p | . + {($p.name+"/"+$p.version):library($p)} else . end))
  '';
  updateDeps = pkgs.writeText "sonarr-update-deps.jq" updateDepsText;
  dependencyPayload = pkgs.runCommand "sonarr-dependency-payload" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    mkdir -p "$out"
    python3 - "$out" <<'PYTHON'
    import pathlib,zipfile,hashlib,sys
    out=pathlib.Path(sys.argv[1])
    ${lib.concatMapStrings (p: let package = pkgs.fetchurl { inherit (p) url hash; }; in ''
    with zipfile.ZipFile('${package}') as z:
      data=z.read('${p.asset}')
      assert hashlib.sha256(data).hexdigest()=='${p.dllSha256}'
      (out/'${p.name}.dll').write_bytes(data)
    '' ) dependencyInputs.nuget}
    PYTHON
    ${lib.concatMapStrings (p: let package = pkgs.fetchurl { inherit (p) url hash; }; in ''
      cp ${package} "$out/${p.file}"
    '' ) dependencyInputs.apks}
  '';
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
    cd /tmp/hwc-sonarr
    jq -r '.[] | .dllSha256 + "  " + .name + ".dll"' manifest.json | sha256sum -c -
    apk verify ./*.apk
    apk --repositories-file /dev/null --no-network --no-cache add ./*.apk
    for file in /app/sonarr/bin/*.deps.json; do
      jq --slurpfile packages manifest.json -f update-deps.jq "$file" > "$file.new"
      mv "$file.new" "$file"
    done
    cp ./*.dll /app/sonarr/bin/
    apk --repositories-file /dev/null --no-network del sqlite-libs
    cp libsqlite3.so.0 /usr/lib/libsqlite3.so.0
    cd /
    rm -r /tmp/hwc-sonarr /tmp/runtime-owned.txt /tmp/app-owned.txt
  '';
  applyRuntime = pkgs.writeText "sonarr-apply-runtime.sh" applyRuntimeText;
  runtime = helpers.mkRuntimeImage {
    name = "sonarr";
    version = "${appVersion}-dotnet${runtimeVersion}";
    recipe = ''
      FROM ${upstreamImage}
      # Bound payload: ${builtins.hashString "sha256" (applyRuntimeText + toString archive + builtins.toJSON dependencyInputs + updateDepsText + toString sqliteNative)}
      COPY . /tmp/hwc-sonarr/
      RUN sh /tmp/hwc-sonarr/apply-runtime.sh
    '';
  };
  runtimeContext = pkgs.runCommand "sonarr-runtime-context" {} ''
    mkdir -p "$out"
    cp ${runtime.dockerfile} "$out/Dockerfile"
    cp ${applyRuntime} "$out/apply-runtime.sh"
    cp ${archive} "$out/runtime.tar.gz"
    cp ${dependencyManifest} "$out/manifest.json"
    cp ${updateDeps} "$out/update-deps.jq"
    cp ${dependencyPayload}/* "$out/"
    cp ${sqliteNative}/lib/libsqlite3.so.0 "$out/libsqlite3.so.0"
    printf '%s\n' '${sqliteNative.version}' > "$out/sqlite-version"
    sha256sum "$out/libsqlite3.so.0" | cut -d' ' -f1 > "$out/sqlite-sha256"
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
