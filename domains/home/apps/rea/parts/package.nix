# domains/home/apps/rea/parts/package.nix
#
# REA (Reverse Engineer Anything, github.com/morluto/rea), the published
# `rea-agents` npm release, pinned by the lockfile in ./src. The upstream
# tarball ships its compiled `dist/`, so nothing is built here: `npm ci`
# materialises the dependency tree and the wrapper runs the shipped entry
# script with the Nix node. Building from the GitHub source would pull the
# whole turbo/vitest dev tree for no gain.
#
# Analysis engines are not installed by REA; the wrapper hands it the Nix
# ones. Ghidra (nixpkgs layout: $out/lib/ghidra) with its JDK 21, Apktool on
# PATH, Binwalk by REA's own variable. Hopper and IDA are commercial and stay
# unconfigured; JADX needs REA's own headless-MCP jar rather than the nixpkgs
# jadx CLI, so Android decompilation is not wired. Unblob is left out: it is
# not in the binary cache and its 26.3.30 test suite fails locally (tar
# timestamp prefix case); set REA_UNBLOB_COMMAND yourself if you need it.
#
# Bumping: edit src/package.json to the new version, then in src/
#   npm install --package-lock-only --ignore-scripts
#   nix run nixpkgs#prefetch-npm-deps -- ./package-lock.json   # → npmDepsHash
{
  lib,
  buildNpmPackage,
  nodejs,
  makeWrapper,
  ghidra,
  openjdk21,
  apktool,
  binwalk,
  # Extra tools put on REA's PATH, for a host that needs more engines.
  extraTools ? [ ],
}:
# REA refuses other Ghidra lines at analysis time (`unsupported_version`), so
# fail here, where the message names the fix. Stable hosts get 12.1.x from
# overlays/ghidra.nix; bump this range together with the REA version.
assert lib.assertMsg (lib.versionAtLeast ghidra.version "12.1" && lib.versionOlder ghidra.version "12.2")
  "rea-agents 6.3.0 needs Ghidra 12.1.x, got ${ghidra.version}. Check overlays/ghidra.nix on stable hosts, or bump REA.";
buildNpmPackage {
  pname = "rea-agents";
  version = "6.3.0";

  src = ./src;

  npmDepsHash = "sha256-FF0i4amaXt5GElklrp420QyFscZxn2Fuo3rrtYmGLo8=";

  # The wrapper package has no build; rea-agents ships dist/. Native deps
  # (@lydell/node-pty) come as prebuilt platform packages, so no scripts run.
  dontNpmBuild = true;
  npmFlags = [ "--ignore-scripts" ];

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib" "$out/bin"
    cp -r node_modules "$out/lib/node_modules"

    makeWrapper ${nodejs}/bin/node "$out/bin/rea" \
      --add-flags "$out/lib/node_modules/rea-agents/scripts/rea.mjs" \
      --prefix PATH : ${lib.makeBinPath ([ nodejs openjdk21 apktool ] ++ extraTools)} \
      --set-default GHIDRA_INSTALL_DIR ${ghidra}/lib/ghidra \
      --set-default JAVA_HOME ${openjdk21.home} \
      --set-default REA_BINWALK_COMMAND ${binwalk}/bin/binwalk

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME="$(mktemp -d)"
    "$out/bin/rea" --help > /dev/null
    [ -f "$out/lib/node_modules/rea-agents/skills/reverse-engineer-anything/SKILL.md" ]
    runHook postInstallCheck
  '';

  passthru.skillDir = "lib/node_modules/rea-agents/skills/reverse-engineer-anything";

  meta = {
    description = "Reverse engineer anything: one CLI and MCP server across binaries, applications and runtime behavior";
    homepage = "https://rea.tools/";
    downloadPage = "https://www.npmjs.com/package/rea-agents";
    changelog = "https://github.com/morluto/rea/releases";
    license = lib.licenses.mit;
    mainProgram = "rea";
    platforms = lib.platforms.linux;
  };
}
