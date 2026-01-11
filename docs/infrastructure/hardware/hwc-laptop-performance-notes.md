# HWC-Laptop Performance/NPU Notes

Audience: CLI agents working on `hwc-laptop` in this repo. Summarizes active tunings and how to extend them safely.

## Current State
- Hybrid scheduling: `services.system76-scheduler.enable = true` (Auto-VIP foreground priority).
- GPU power: `hardware.nvidia.powerManagement = { enable = true; finegrained = true; }` for PRIME Ada. Watch suspend/offload stability when changing.
- Storage: NVMe schedulers forced to `kyber` via udev rule in `machines/laptop/config.nix`.
- NPU: Upstream module imported (`hardware/cpu/intel-npu.nix`) with `hardware.cpu.intel.npu.enable = true;` → loads `intel_vpu`, firmware, Level Zero loader, render-group perms on `/dev/accel*`.

## NPU Tooling
- Level Zero loader is in PATH (`libze_loader.so`). The module does **not** add `intel-compute-runtime`; add it explicitly if iGPU Level Zero/OpenCL is needed.
- OpenVINO is available in the store; tools are not on PATH by default. Source its `setupvars.sh` or prepend the tool dirs for tests.
  - Store root example: `/nix/store/*-openvino-*/setupvars.sh`
  - Tools example: `/nix/store/*-openvino-*/tools/compile_tool/compile_tool`

## Validation Tips
- NPU device: `ls -l /dev/accel*` should show `root:render 0660`; `lsmod | grep intel_vpu`.
- Schedulers: `cat /sys/block/nvme0n1/queue/scheduler` should bracket `kyber`.
- Scheduler daemon: `sudo systemctl status system76-scheduler`.
- GPU PM: after suspend/resume, verify PRIME offload (`prime-run glxinfo`) still works; revert `finegrained` if black screens appear.
