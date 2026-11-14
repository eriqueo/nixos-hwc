# The Rust tracker (`hwc-tracker`: hub and client CLI) from the pinned harness.
# Pure function, the one build recipe. Two callers:
#   - index.nix: `tracker.package`, built with the host's packages, no tests.
#   - domains/home/verification/checks.nix: `tracker-rust-contracts`, built
#     with the check packages and `doCheck = true`.
# The contract tests compare the crate with the Python hub through `python3`.
# Two of them (fromisoformat, JSON value semantics) pass against Python 3.14
# and fail against 3.13, which is the stable channel's python3 (measured
# 2026-11-13), so a stable host cannot run them in its own build.
# The parity tests read the hub page at ../index.html beside the crate, as the
# Python server does, so the source is lifecycle/tracker with the crate inside.
{ pkgs, harness, doCheck ? false }:
pkgs.rustPlatform.buildRustPackage {
  pname = "hwc-tracker";
  version = "0.1.0";
  src = harness + "/lifecycle/tracker";
  cargoRoot = "rust";
  buildAndTestSubdir = "rust";
  cargoLock.lockFile = harness + "/lifecycle/tracker/rust/Cargo.lock";
  nativeCheckInputs = [ pkgs.python3 ];
  inherit doCheck;
  preCheck = ''
    export PYTHONPATH="${harness}/lifecycle/tracker"
  '';
}
