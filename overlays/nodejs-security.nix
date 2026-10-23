# overlays/nodejs-security.nix
# Node.js October 2026 security release (2026-10-21) ahead of the channels.
#
# 24.22.1 / 22.23.4 fix the Brotli decoder RCE (CVE-2026-111497), three TLS
# hostname bypasses, and drop the compromised eMudhra emSign roots/keys from
# Node's compiled-in store. nixpkgs links Node against the SHARED system
# brotli, so the vendored deps/brotli fix never reaches our binary: Node also
# gets a brotli carrying the upstream fix (google/brotli 0ed4268a, the same
# patch nixpkgs master applies for nodejs_22). The patched brotli is scoped to
# Node; other brotli consumers wait for brotli 1.2.1 in the channel.
#
# Overriding nodejs-slim_* carries through nodejs, nodejs_22/24 and every
# package built with them (one rebuild cascade, no per-module edits).
# Existing git.nix chose runtime selection to spare bootstrap toolchains; Node
# is not in bootstrap and its build-time uses run untrusted input too.
#
# TEMPORARY (tracked). Each half retires itself: the version bump stops once
# the channel's slim version reaches the target, the brotli patch once the
# channel's brotli reaches 1.2.1. Delete this file and its two wire-ins in
# flake.nix when, with it removed,
#   nix eval .#nixosConfigurations.hwc-work.pkgs.nodejs_22.version  >= 22.23.4
#   nix eval .#nixosConfigurations.hwc-work.pkgs.nodejs_24.version  >= 24.22.1
#   nix eval .#nixosConfigurations.hwc-work.pkgs.brotli.version     >= 1.2.1
# and the same three hold for hwc-laptop.

final: prev:
let
  lib = prev.lib;

  # TEMPORARY: explicit upstream runtimes avoid rebuilding every build-time
  # Node consumer. Remove when the pinned Nixpkgs Node packages include the
  # October fixes in both Node and its linked libraries and pass these checks.
  # Hashes were verified against Node's signed SHASUMS256.txt on 2026-10-23.
  runtimeReleases = {
    "22" = {
      version = "22.23.4";
      sha256 = "1805bcd35e6815559bd2eb97db438d3fdb0eb3a5e6a977b7c1badca76337e9ce";
      sourceSha256 = "7b9adc82d612d0a2a863d96c46de2292552e250cee51956ebbe0146c42aacae9";
    };
    "24" = {
      version = "24.22.1";
      sha256 = "6c172a9ab6718f7b801fb5a7bd486af2ee5e32758086a04b84fcce2aa77095e6";
      sourceSha256 = "4f5379796280cdaeb0c2f358fd04b6a16cc4fb7dfa83b5a8c91a9d963b435231";
    };
  };
  runtimeDependencies = { ares = "1.34.9"; openssl = "3.5.9"; sqlite = "3.53.4"; };
  runtimeCheck = prev.writeText "node-runtime-security-check.cjs" ''
    const assert = require('node:assert/strict');
    const { X509Certificate } = require('node:crypto');
    const dns = require('node:dns');
    const tls = require('node:tls');
    const zlib = require('node:zlib');
    const { DatabaseSync } = require('node:sqlite');
    const manifest = JSON.parse(process.argv[2]);
    for (const [name, expected] of Object.entries(manifest)) {
      assert.equal(process.versions[name], expected, name + ' dependency mismatch');
    }
    const emSignRoots = tls.rootCertificates
      .map(pem => new X509Certificate(pem).toLegacyObject().subject.CN)
      .filter(name => name?.startsWith('emSign ')).sort();
    assert.deepEqual(emSignRoots, ['emSign Root CA - G1']);
    assert.throws(() => dns.resolve('example\0.invalid', () => {}), { code: 'ERR_INVALID_ARG_VALUE' });
    assert(tls.checkServerIdentity('0x7f.0.0.1', { subjectaltname: 'DNS:0x7f.0.0.1' }));
    const data = Buffer.from('HWC native runtime security smoke test');
    assert.deepEqual(zlib.brotliDecompressSync(zlib.brotliCompressSync(data)), data);
    const db = new DatabaseSync(':memory:');
    assert.equal(db.prepare('select 42 as value').get().value, 42);
    db.close();
    // Preserve buildNpmPackage's existing node-gyp selection contract.
    process.env.NIX_NODEJS_BUILDNPMPACKAGE = '1';
    const setPath = require(process.argv[3] + '/lib/node_modules/npm/node_modules/@npmcli/run-script/lib/set-path.js');
    const paths = setPath('/isolated', ['/project-injected-bin'], { PATH: '/trusted-bin' }).PATH.split(':');
    assert(paths.indexOf('/trusted-bin') < paths.indexOf('/project-injected-bin'), 'Nix node-gyp PATH precedence missing');
    console.log(JSON.stringify({ result: 'pass', versions: process.versions }));
  '';
  mkRuntime = major:
    let release = runtimeReleases.${major}; in
    prev.stdenvNoCC.mkDerivation {
      pname = "nodejs-runtime";
      inherit (release) version;
      src = prev.fetchurl {
        url = "https://nodejs.org/dist/v${release.version}/node-v${release.version}-linux-x64.tar.xz";
        inherit (release) sha256;
      };
      nativeBuildInputs = [ prev.autoPatchelfHook ];
      buildInputs = [ prev.stdenv.cc.cc.lib ];
      # Reuse the pinned Nixpkgs npm compatibility patch; do not fork its logic.
      prePatch = ''
        mkdir deps
        mv lib/node_modules/npm deps/npm
      '';
      patches = [ (prev.path + "/pkgs/development/web/nodejs/node-npm-build-npm-package-logic.patch") ];
      postPatch = ''
        mv deps/npm lib/node_modules/npm
        rmdir deps
      '';
      dontBuild = true;
      dontStrip = true;
      installPhase = ''
        runHook preInstall
        mkdir -p "$out"
        cp -r bin include lib share CHANGELOG.md LICENSE README.md "$out/"
        runHook postInstall
      '';
      # fixup uses patchShebangs --host, which searches HOST_PATH, not PATH.
      # autoPatchelf fixes the interpreter itself before install checks run.
      preFixup = ''
        export HOST_PATH="$out/bin:$HOST_PATH"
      '';
      doInstallCheck = true;
      installCheckPhase = ''
        runHook preInstallCheck
        "$out/bin/node" ${runtimeCheck} ${lib.escapeShellArg (builtins.toJSON (runtimeDependencies // { node = release.version; }))} "$out"
        "$out/bin/npm" --version
        "$out/bin/npx" --version
        runHook postInstallCheck
      '';
      setupHook = prev.nodejs-slim_22.setupHook;
      passthru = {
        python = prev.python3;
        securityCheck = runtimeCheck;
        securityManifest = runtimeDependencies // { node = release.version; };
      };
      meta = {
        description = "Explicit native Node runtime from the verified upstream security release";
        homepage = "https://nodejs.org/";
        license = lib.licenses.mit;
        platforms = [ "x86_64-linux" ];
        mainProgram = "node";
      };
    };

  brotliNeedsFix = lib.versionOlder prev.brotli.version "1.2.1";

  brotliFixed = prev.brotli.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      # CVE-2026-111497: "Detect and report invalid stream earlier."
      (prev.fetchurl {
        url = "https://github.com/google/brotli/commit/0ed4268a4401abcb4472096340477cf4af7d1a2b.patch?full_index=1";
        hash = "sha256-1vliUJAAIj3vcGKVgim9CEV+XgMuftDR2U+3kLBUsfw=";
      })
    ];
  });

  # v2X.nix receives callPackage and uses it only to obtain buildNodejs from
  # nodejs.nix; wrapping it injects brotli and the release without copying
  # either file.
  secure = slim: version: sha256:
    let bump = lib.versionOlder slim.version version; in
    if !bump && !brotliNeedsFix then slim
    else slim.override {
      callPackage = fn: fnArgs:
        let
          buildNodejs = final.callPackage fn
            (fnArgs // lib.optionalAttrs brotliNeedsFix { brotli = brotliFixed; });
        in
        args: buildNodejs (args // lib.optionalAttrs bump {
          inherit version sha256;
          # Node 24.20+ includes emulator support upstream; older Nixpkgs
          # recipes still add its backport. Keep every other recipe patch.
          # Remove this filter when the source bump retires with the overlay.
          patches = lib.filter (patch:
            !(lib.versions.major version == "24"
              && lib.versionAtLeast version "24.20.0"
              && builtins.baseNameOf (toString patch) == "configure-emulator.patch")
          ) (args.patches or [ ]);
        });
    };
in {
  nodejsRuntime_22 = mkRuntime "22";
  nodejsRuntime_24 = mkRuntime "24";
  # sha256 from https://nodejs.org/dist/v<version>/SHASUMS256.txt
  nodejs-slim_22 = secure prev.nodejs-slim_22 runtimeReleases."22".version
    runtimeReleases."22".sourceSha256;
  nodejs-slim_24 = secure prev.nodejs-slim_24 runtimeReleases."24".version
    runtimeReleases."24".sourceSha256;
}
