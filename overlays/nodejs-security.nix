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
        args: buildNodejs (args // lib.optionalAttrs bump { inherit version sha256; });
    };
in {
  # sha256 from https://nodejs.org/dist/v<version>/SHASUMS256.txt
  nodejs-slim_22 = secure prev.nodejs-slim_22 "22.23.4"
    "7b9adc82d612d0a2a863d96c46de2292552e250cee51956ebbe0146c42aacae9";
  nodejs-slim_24 = secure prev.nodejs-slim_24 "24.22.1"
    "4f5379796280cdaeb0c2f358fd04b6a16cc4fb7dfa83b5a8c91a9d963b435231";
}
