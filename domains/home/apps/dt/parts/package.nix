# domains/home/apps/dt/parts/package.nix
#
# Builds the `dt` CLI from the vendored TypeScript source. esbuild bundles
# src/cli/index.ts into a single ESM file with native deps externalized; the
# wrapper invokes Node directly with the package manifest entry — this
# avoids the double-shebang trap (the source keeps its own shebang for dev,
# and `node` cleanly ignores a line-1 shebang).
{ lib, buildNpmPackage, nodejs, python3, pkg-config, sqlite, makeWrapper, poppler-utils }:

let
  manifest = builtins.fromJSON (builtins.readFile ../source/package.json);
in
buildNpmPackage {
  pname = manifest.name;
  version = manifest.version;

  src = ../source;

  npmDepsHash = "sha256-hh5XpmEsC3EveEikP2fwXYtdKAZZ9OlzYnCQBPckDhw=";

  # better-sqlite3 needs a build toolchain (gyp/python/sqlite headers).
  nativeBuildInputs = [ python3 pkg-config makeWrapper ];
  buildInputs = [ sqlite ];

  # The explicit buildPhase runs the same build.mjs entry as npm run build.
  dontNpmBuild = true;

  buildPhase = ''
    runHook preBuild
    node build.mjs
    runHook postBuild
  '';

  doCheck = true;
  nativeCheckInputs = [ poppler-utils ];
  checkPhase = ''
    runHook preCheck
    node --import tsx --test --test-concurrency=2 src/__tests__/*.test.ts
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/dt $out/bin
    cp -r dist node_modules package.json $out/lib/dt/

    makeWrapper ${nodejs}/bin/node $out/bin/dt \
      --add-flags "$out/lib/dt/${manifest.bin.dt}"

    runHook postInstall
  '';

  meta = with lib; {
    description = "DataX time tracker (CLI + TUI) for invoicing";
    mainProgram = "dt";
    platforms = platforms.linux;
  };
}
