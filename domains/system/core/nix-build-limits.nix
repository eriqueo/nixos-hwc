# domains/system/core/nix-build-limits.nix
#
# Memory ceiling for nix-daemon and every build it forks.
#
# On 2026-08-26 a local CUDA rebuild on hwc-laptop (opencv, whisper-cpp,
# cudnn, triton — the laptop's per-package `cudaSupport = true` override
# misses cache.nixos-cuda.org) ran 37 concurrent cc1plus at ~800MB each,
# plus 15 cicc/cudafe++ CUDA front ends. Nix's defaults permit that: NixOS
# ships `max-jobs = auto` (22 here) with `cores = 0` (all 22 per job), so
# the ceiling is 484 compilers, not 22. Anonymous memory reached 24GB
# against 30GB RAM. The kernel global OOM killer ran for 12 minutes, took
# a dozen Chromium tabs, then dbus-broker, the portals, waybar, swaync,
# and finally `systemd --user` itself (PID 3294). The desktop died; the
# build survived.
#
# Capping max-jobs/cores instead was the other candidate and is worse: a
# job count is a guess at compiler RSS, which ranges from ~50MB to ~3GB.
# A cap low enough to survive a CUDA build wastes most of the cores on
# every ordinary build, and still says nothing about actual memory.
#
# A cgroup limit says the thing we actually mean: a build may not take the
# desktop with it. MemoryHigh throttles and forces reclaim first, so an
# expensive build slows rather than dies; MemoryMax is the hard stop, and
# the kill lands inside the build cgroup instead of on the session.
#
# Percentages, not absolutes — systemd reads these relative to installed
# physical memory, so the same numbers hold on the 30GB laptop and the
# server without a per-machine option to keep in sync.
#
# nix-daemon.service carries `Delegate=`, so builds land in sub-cgroups it
# creates. cgroup v2 limits are hierarchical, so the ceiling still binds
# the whole subtree.
{ ... }:
{
  systemd.services.nix-daemon.serviceConfig = {
    MemoryHigh = "40%";
    MemoryMax = "55%";
  };
}
