# The Rust tracker (`hwc-tracker`: hub and client CLI) from the pinned harness.
# Pure function, the one build recipe. Two callers:
#   - index.nix: `tracker.package`, built with the host's packages, no tests.
#   - domains/home/verification/checks.nix: `tracker-rust-contracts`, built
#     with the check packages and `doCheck = true`.
# The contract tests compare the crate with the Python hub through `python3`.
# Two of them (fromisoformat, JSON value semantics) pass against Python 3.14
# and fail against 3.13, which is the stable channel's python3 (measured
# 2026-11-13), so a stable host cannot run them in its own build.
# Source: the harness's lifecycle/ and guards/lib/ with the crate at
# lifecycle/tracker/rust. The parity tests read the hub page at ../index.html
# and import the Python hub beside the crate; tests/ws.rs runs the real
# lifecycle/ws (which sources guards/lib/workspace.sh and runs closeout.py)
# against the real hub, with jq and git from PATH.
# Release: the hub and the client refuse a write between two different
# releases (426 release-mismatch, client exit 7). The release names the crate
# source, not the harness revision: a harness change outside the crate (a
# skill, a guard) published to one host must not cut that host's agents off
# from the hub. A crate change is a hub change: deploy the hub host first.
{ pkgs, harness, doCheck ? false }:
let
  lib = pkgs.lib;
  root = toString harness;
  keep = path: type:
    let rel = lib.removePrefix "${root}/" (toString path);
    in rel == "lifecycle" || rel == "guards" || rel == "guards/lib"
      || lib.hasPrefix "lifecycle/" rel || lib.hasPrefix "guards/lib/" rel;
  crate = builtins.path { path = harness + "/lifecycle/tracker/rust"; name = "hwc-tracker-crate"; };
in
pkgs.rustPlatform.buildRustPackage {
  pname = "hwc-tracker";
  version = "0.1.0";
  src = builtins.path { path = harness; name = "hwc-tracker-source"; filter = keep; };
  cargoRoot = "lifecycle/tracker/rust";
  buildAndTestSubdir = "lifecycle/tracker/rust";
  cargoLock.lockFile = harness + "/lifecycle/tracker/rust/Cargo.lock";
  # Read at compile time; /health reports it and the client sends it.
  HWC_TRACKER_RELEASE = builtins.substring 0 12 (baseNameOf crate);
  nativeCheckInputs = [ pkgs.python3 pkgs.jq pkgs.git ];
  inherit doCheck;
  preCheck = ''
    export PYTHONPATH="${harness}/lifecycle/tracker"
  '';
}
