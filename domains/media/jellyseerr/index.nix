{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.jellyseerr;
  appVersion = "3.1.0";
  nodeVersion = "22.23.4";
  upstreamImage = "ghcr.io/seerr-team/seerr@sha256:b35ba0461c4a1033d117ac1e5968fd4cbe777899e4cbfbdeaf3d10a42a0eb7e9";
  nodeSourceImage = "ghcr.io/seerr-team/seerr@sha256:d8fab675b55ad293ded98fd71efcfd46054cbad9746534ae1cc4794a88c0b3be";
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  # Temporary: retain the 3.1 schema because 3.5 drops discordId and breaks
  # old-code authentication recovery (brain-w8phr6). Backport the three named
  # upstream fixes without their unrelated schema/dependency changes. Retire
  # when a vendor image passes these security and current-data recovery checks.
  # Same-branch signed musl/OpenSSL/zlib updates retain the app and Node ABI.
  baseRuntime = helpers.mkNodeRuntimeImage {
    name = "seerr";
    inherit appVersion nodeVersion upstreamImage nodeSourceImage;
  };
  runtimeInputs = builtins.fromJSON ''
    {"schemaVersion":1,"advisories":["GHSA-mc6w-69r3-62h8","GHSA-8j73-j6rc-q8xh","GHSA-xc6j-6p6h-p799"],"upstreamSources":{"v3.4.0/server/lib/imageproxy.ts":{"url":"https://raw.githubusercontent.com/seerr-team/seerr/v3.4.0/server/lib/imageproxy.ts","sha256":"97404633db8be647dc2d89920164e55437981d71b2dbcd2c13c6ecad86f43a5a"},"v3.5.0/server/lib/imageproxy.ts":{"url":"https://raw.githubusercontent.com/seerr-team/seerr/v3.5.0/server/lib/imageproxy.ts","sha256":"2eb1c0eb2d7bdca374f9e33e0f777e8c2fea6a583b4f223c559be2b5f699b5cc"},"v3.5.0/server/entity/User.ts":{"url":"https://raw.githubusercontent.com/seerr-team/seerr/v3.5.0/server/entity/User.ts","sha256":"0d640dfa0f310d7e8fb5bb8da4801ce4eaa52c6ad88493935714f58764744981"},"v3.5.0/server/entity/UserSettings.ts":{"url":"https://raw.githubusercontent.com/seerr-team/seerr/v3.5.0/server/entity/UserSettings.ts","sha256":"dd2eda4d3dd1090cd678499ec7ff6017bc89ee2f0652ceb74dfbeaaaab6a0ceb"},"v3.5.0/server/routes/auth.ts":{"url":"https://raw.githubusercontent.com/seerr-team/seerr/v3.5.0/server/routes/auth.ts","sha256":"1bfe7e51ad3da83c7831d5d2cdc1d5194836fc3c2a1e7dd42d07b86e4eace994"},"v3.5.0/server/routes/movie.ts":{"url":"https://raw.githubusercontent.com/seerr-team/seerr/v3.5.0/server/routes/movie.ts","sha256":"80a5fe3f9fef1bb1dc18ff865b306f2e7f5f24d9007689ea704415bdcf61484b"},"v3.5.0/server/routes/tv.ts":{"url":"https://raw.githubusercontent.com/seerr-team/seerr/v3.5.0/server/routes/tv.ts","sha256":"3e2b334513a8cc86126d8564593ef0d7b4faf626840053a3410b9687dc77852d"},"v3.5.0/server/entity/Media.ts":{"url":"https://raw.githubusercontent.com/seerr-team/seerr/v3.5.0/server/entity/Media.ts","sha256":"733660758605b6cebd40eabb0259e1fd64d2ad942d03d5459e20517b048a777d"}},"backports":{"dist/lib/imageproxy.js":{"sourceSha256":"5252b51827bf830fbaa4e7c54059fc23834fbb0fa8a8140a021356f5d92e8492","patchedSha256":"4396c9995a62403546941199a08c485afc0e7ffbfb1c7050d598601273766235","replacements":[["const extension = lite_1.default.getExtension(contentType) || ''';","const extension = (lite_1.default.getExtension(contentType) || ''').replace(/[^\\w-]/g, ''');"],["const etag = (response.headers.etag ?? ''').replace(/\"/g, ''');","const etag = (response.headers.etag ?? ''').replace(/[^\\w-]/g, ''');"]]},"dist/entity/User.js":{"sourceSha256":"4ad6ee03d6942be79852a04e449e2b1e5edcff29a99b14d6bc8624eead4f7c7b","patchedSha256":"0b54f6be56cc6d727b81324e0e254fa8564c2715f1dacb45315f1a630d2e23e0","replacements":[["    hasPermission(permissions, options) {","    toJSON() {\n        return Object.assign({}, ...Object.keys(this)\n            .filter((k) => !User_1.serializationExcludedFields.includes(k))\n            .map((k) => ({ [k]: this[k] })));\n    }\n    hasPermission(permissions, options) {"],["User.filteredFields = [","User.serializationExcludedFields = ['settings'];\nUser.filteredFields = ["]]},"dist/entity/Media.js":{"sourceSha256":"7a4a17b657768d7e493c8181405a163a3dbaf46f716f095308914a5d559c6031","patchedSha256":"9aaf301eca22354894969089c69dd5e9ced27c0d3aff519ff8924497b19f4028","replacements":[["const settings_1 = require(\"../lib/settings\");","const permissions_1 = require(\"../lib/permissions\");\nconst settings_1 = require(\"../lib/settings\");"],["    constructor(init) {","    filter(user) {\n        const canViewIssues = user?.hasPermission([\n            permissions_1.Permission.MANAGE_ISSUES,\n            permissions_1.Permission.VIEW_ISSUES,\n            permissions_1.Permission.CREATE_ISSUES,\n        ], { type: 'or' }) ?? false;\n        return {\n            ...this,\n            requests: (this.requests ?? []).map((request) => ({\n                ...request,\n                requestedBy: request.requestedBy?.filter(),\n                modifiedBy: request.modifiedBy?.filter(),\n            })),\n            issues: canViewIssues\n                ? (this.issues ?? []).map(({ comments, problemSeason, problemEpisode, ...issue }) => ({\n                    ...issue,\n                    createdBy: issue.createdBy?.filter(),\n                    modifiedBy: issue.modifiedBy?.filter(),\n                }))\n                : [],\n        };\n    }\n    constructor(init) {"]]},"dist/routes/auth.js":{"sourceSha256":"95d40e7453903ec0caae788ba67ac2134d967d62ae554b30f1b3ad664b9ebd98","patchedSha256":"3df1d482d54714680ea2fa26751af53d9e648ea086a675995f20656b9a6a45d0","replacements":[["    return res.status(200).json(user);","    return res.status(200).json({\n        ...user.toJSON(),\n        settings: user.settings && {\n            locale: user.settings.locale,\n            discoverRegion: user.settings.discoverRegion,\n            streamingRegion: user.settings.streamingRegion,\n            originalLanguage: user.settings.originalLanguage,\n            notificationTypes: user.settings.notificationTypes,\n            watchlistSyncMovies: user.settings.watchlistSyncMovies,\n            watchlistSyncTv: user.settings.watchlistSyncTv,\n        },\n    });"]]},"dist/routes/movie.js":{"sourceSha256":"c2bee43fe6a675e059824a0660388c8d8992bd9404fa5ff7efeddb03df17cd3a","patchedSha256":"6ef6da90d180d5620dc3741fdb511b9ac47ae8fe044839ba6048575126a24371","replacements":[["(tmdbMovie, media, onUserWatchlist);","(tmdbMovie, media?.filter(req.user), onUserWatchlist);"]]},"dist/routes/tv.js":{"sourceSha256":"bf05646979266e8907cdd1e446362093c8f838cf4bf104507895f85badad8cd7","patchedSha256":"c74a5ff26e206f68d62795bfdcbe0ac4a9e2c09de1c5eb702817c92fe9cdde47","replacements":[["(tv, media, onUserWatchlist);","(tv, media?.filter(req.user), onUserWatchlist);"]]}},"apks":[{"name":"libcrypto3","version":"3.5.9-r0","file":"libcrypto3-3.5.9-r0.apk","url":"https://dl-cdn.alpinelinux.org/alpine/v3.22/main/x86_64/libcrypto3-3.5.9-r0.apk","hash":"sha256-P1glztX94cZqU3aj9gdrPAhTitUtnvI/BphX4hLZF1o="},{"name":"libssl3","version":"3.5.9-r0","file":"libssl3-3.5.9-r0.apk","url":"https://dl-cdn.alpinelinux.org/alpine/v3.22/main/x86_64/libssl3-3.5.9-r0.apk","hash":"sha256-aAHHQLl2C1sI2o22Nn68GLLMTbrzcfcUhClTi4uwTiM="},{"name":"musl","version":"1.2.5-r13","file":"musl-1.2.5-r13.apk","url":"https://dl-cdn.alpinelinux.org/alpine/v3.22/main/x86_64/musl-1.2.5-r13.apk","hash":"sha256-NZiQvHxNxf7nqFGS3mCkccmH5GZHZyiFeL7KYKRNssg="},{"name":"musl-utils","version":"1.2.5-r13","file":"musl-utils-1.2.5-r13.apk","url":"https://dl-cdn.alpinelinux.org/alpine/v3.22/main/x86_64/musl-utils-1.2.5-r13.apk","hash":"sha256-D7UtHXLzTNaQJyWK3KSNtddbIIcjdMX2vQBgDwJ53dY="},{"name":"zlib","version":"1.3.2-r1","file":"zlib-1.3.2-r1.apk","url":"https://dl-cdn.alpinelinux.org/alpine/v3.22/main/x86_64/zlib-1.3.2-r1.apk","hash":"sha256-ryTlAmReKzksroM4Vtd2aRrCFlU2Ll22nXuJ8Uf3YhY="}]}
  '';
  applyBackports = pkgs.writeText "seerr-security-backports.cjs" ''
'use strict';
const fs=require('fs'),path=require('path'),{createHash}=require('crypto');
const manifest=JSON.parse(fs.readFileSync(path.join(__dirname,'manifest.json'),'utf8'));
if(manifest.schemaVersion!==1)throw Error('SEERR_BACKPORT_FORMAT_INVALID');
const sha=raw=>createHash('sha256').update(raw).digest('hex');
const writes=[];
for(const [name,spec] of Object.entries(manifest.backports)){
 const target=path.resolve('/app',name);
 if(!target.startsWith('/app/dist/'))throw Error('SEERR_BACKPORT_PATH_INVALID');
 const original=fs.readFileSync(target);
 if(sha(original)!==spec.sourceSha256)throw Error('SEERR_BACKPORT_SOURCE_MISMATCH:'+name);
 let text=original.toString('utf8');
 for(const [before,after] of spec.replacements){
  if(text.split(before).length!==2)throw Error('SEERR_BACKPORT_HUNK_MISMATCH:'+name);
  text=text.replace(before,after);
 }
 const changed=Buffer.from(text);
 if(sha(changed)!==spec.patchedSha256)throw Error('SEERR_BACKPORT_RESULT_MISMATCH:'+name);
 writes.push([target,changed]);
}
for(const [target,changed] of writes)fs.writeFileSync(target,changed);
  '';
  manifest = pkgs.writeText "seerr-security-backports.json" (builtins.toJSON runtimeInputs);
  runtime = helpers.mkRuntimeImage {
    name = "seerr";
    version = "${appVersion}-node${nodeVersion}";
    recipe = baseRuntime.recipe + ''
      # Security backports ${builtins.hashString "sha256" (builtins.toJSON runtimeInputs + builtins.readFile applyBackports)}
      USER root
      COPY --chown=node:node . /tmp/hwc-seerr/
      RUN apk verify ${lib.concatMapStringsSep " " (p: lib.escapeShellArg "/tmp/hwc-seerr/${p.file}") runtimeInputs.apks} && apk --repositories-file /dev/null --no-network --no-cache add ${lib.concatMapStringsSep " " (p: lib.escapeShellArg "/tmp/hwc-seerr/${p.file}") runtimeInputs.apks} && node /tmp/hwc-seerr/apply-backports.cjs && rm -r /tmp/hwc-seerr
      USER node:node
    '';
  };
  runtimeContext = pkgs.runCommand "seerr-runtime-context" {} ''
    mkdir -p "$out"
    cp ${runtime.dockerfile} "$out/Dockerfile"
    cp ${manifest} "$out/manifest.json"
    cp ${applyBackports} "$out/apply-backports.cjs"
    ${lib.concatMapStrings (p: let archive = pkgs.fetchurl { inherit (p) url hash; }; in ''
      cp ${archive} "$out/${p.file}"
    '') runtimeInputs.apks}
  '';
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.jellyseerr = {
    enable = lib.mkEnableOption "jellyseerr container";
    image = lib.mkOption { type = lib.types.str; default = runtime.image; description = "Qualified container image; local default built from system.build.seerrRuntimeImageContext"; };
    network.mode = lib.mkOption { type = lib.types.enum [ "media" "vpn" ]; default = "media"; };
    gpu.enable = lib.mkOption { type = lib.types.bool; default = false; };
  };

  imports = [
    ./sys.nix
    ./parts/config.nix
    ./parts/setup.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    system.build.seerrRuntimeImageRecipe = runtime.dockerfile;
    system.build.seerrRuntimeImageContext = runtimeContext;
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Add assertions and validation logic here
}
