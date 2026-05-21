# domains/home/apps/dt/parts/package.nix
#
# Builds the `dt` CLI from the vendored TypeScript source. esbuild bundles
# src/cli/index.ts into a single ESM file with native deps externalized; the
# wrapper invokes Node directly with `node $out/lib/dt/dist/dt.mjs` — this
# avoids the double-shebang trap (the source keeps its own shebang for dev,
# and `node` cleanly ignores a line-1 shebang).
{ lib, buildNpmPackage, nodejs, python3, pkg-config, sqlite, makeWrapper }:

buildNpmPackage rec {
  pname = "dt";
  version = "1.0.0";

  src = ../source;

  npmDepsHash = "sha256-hh5XpmEsC3EveEikP2fwXYtdKAZZ9OlzYnCQBPckDhw=";

  # better-sqlite3 needs a build toolchain (gyp/python/sqlite headers).
  nativeBuildInputs = [ python3 pkg-config makeWrapper ];
  buildInputs = [ sqlite ];

  # Skip the package.json "build" script — we run our own esbuild pipeline.
  dontNpmBuild = true;

  buildPhase = ''
    runHook preBuild
    node build.mjs
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/dt $out/bin
    cp -r dist node_modules package.json $out/lib/dt/

    makeWrapper ${nodejs}/bin/node $out/bin/dt \
      --add-flags "$out/lib/dt/dist/dt.mjs"

    runHook postInstall
  '';

  meta = with lib; {
    description = "DataX time tracker (CLI + TUI) for invoicing";
    mainProgram = "dt";
    platforms = platforms.linux;
  };
}
