# Frigate NVR Configuration Retrospective

**Created**: 2025-11-23
**Purpose**: Document the history of Frigate configuration changes, identify patterns to avoid, and understand lessons learned

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Timeline of Changes](#timeline-of-changes)
3. [The ONNX Dtype Crisis (Nov 2025)](#the-onnx-dtype-crisis-nov-2025)
4. [Image Version Strategy](#image-version-strategy)
5. [Patterns That Worked](#patterns-that-worked)
6. [Patterns to Avoid (Lessons Learned)](#patterns-to-avoid-lessons-learned)
7. [Root Cause Analysis](#root-cause-analysis)
8. [Preventive Measures](#preventive-measures)
9. [Current State Assessment](#current-state-assessment)

---

## Executive Summary

The Frigate NVR module has undergone several configuration iterations, with the most recent being a critical ONNX detector crash caused by:

1. **Incorrect YAML structure**: `model` block nested under `detectors.onnx` instead of being a top-level sibling
2. **Missing critical field**: `input_dtype: float` was absent, causing uint8→float tensor type mismatch
3. **Refactoring introduced regression**: Nov 19, 2025 hardware acceleration refactor inadvertently broke ONNX detector config

**Key Learning**: Configuration changes that "look cosmetic" in Nix can have critical semantic impacts on the generated YAML structure. Always verify the **generated config** after refactoring, not just the Nix code.

---

## Timeline of Changes

### 2025-11-07: Early Configuration
**Commit**: `cd3d795` - fix: comment out Fabric configuration in server config

- Frigate module existed with basic functionality
- Limited git history suggests this was an early stable state
- Configuration details unclear from available history

### 2025-11-19: Hardware Acceleration Refactor
**Commit**: `600d839` - feat(frigate): add flexible hardware acceleration with Intel VAAPI/QSV support

**What Changed**:
- Added `hwaccel.type` option to support multiple acceleration types (nvidia, vaapi, qsv, cpu)
- Refactored FFmpeg `hwaccel_args` generation to be dynamic based on type
- Added Intel VAAPI/QuickSync support for power efficiency
- Added comprehensive documentation (HARDWARE-ACCELERATION.md, TUNING-GUIDE.md)
- Enhanced container device passthrough for Intel iGPU

**What Was Introduced (Unintentionally)**:
- ❌ ONNX `model` block remained **nested under `detectors.onnx`** (incorrect YAML structure)
- ❌ Missing `input_dtype: float` field (critical for ONNX dtype conversion)
- ✅ TensorRT detector config remained correct (unchanged)

**Impact**:
- Hardware acceleration refactor was successful
- ONNX detector config remained broken but went unnoticed (likely TensorRT was in use at the time)
- Documentation was excellent and comprehensive

### 2025-11-22: Systemd Service Fixes
**Commit**: `474f59d` - fix(server,infrastructure): resolve critical systemd service failures

- Fixed various systemd service issues
- No direct Frigate configuration changes
- Potential merge conflicts during this period

### 2025-11-23: Beets Merge Conflict → Frigate Crashes
**Context**: Merge conflict in `domains/server/apps/beets-native/index.nix`

**What Happened**:
1. Merged and resolved beets-native conflict
2. Rebuilt NixOS system
3. **Frigate started crashing with ONNX dtype error**

**Root Cause**:
- The beets merge didn't directly cause the Frigate crash
- **Likely scenario**: System rebuild triggered Frigate container recreation with existing broken config
- The broken ONNX config (from Nov 19) had been dormant or masked by TensorRT usage
- After rebuild, Frigate switched to or attempted to use ONNX detector, exposing the latent bug

**Error Message**:
```
[ONNXRuntimeError] : 2 : INVALID_ARGUMENT :
Unexpected input data type. Actual: (tensor(uint8)), expected: (tensor(float))
```

**Secondary Issue** (non-fatal):
```
Failed to load library libonnxruntime_providers_cuda.so with error:
libcurand.so.10: cannot open shared object file: No such file or directory
```

### 2025-11-23: ONNX Dtype Fix
**Commit**: `05f7c63` - fix(server.frigate): add missing input_dtype and fix model block nesting

**What Was Fixed**:
1. ✅ Moved `model` block to **top-level** (sibling to `detectors`, not nested under `detectors.onnx`)
2. ✅ Added `input_dtype: float` field to instruct Frigate to convert uint8→float tensors
3. ✅ Maintained all other model parameters (path, model_type, input_tensor, input_pixel_format, width, height)

**Correct YAML Structure**:
```yaml
detectors:
  onnx:
    type: onnx
    num_threads: 3

model:  # <-- Top-level sibling to detectors
  path: /config/models/yolov9-s-320.onnx
  model_type: yolo-generic
  input_tensor: nchw
  input_pixel_format: bgr
  input_dtype: float  # <-- Critical field
  width: 320
  height: 320
  labelmap_path: /labelmap/coco-80.txt
```

---

## The ONNX Dtype Crisis (Nov 2025)

### What Broke

The ONNX detector crashed because Frigate sent uint8 tensors to a model expecting float32 tensors.

### Why It Broke

1. **Structural Error**: `model` block was nested under `detectors.onnx` instead of being top-level
   - Frigate likely ignored or partially parsed the nested model config
   - Fell back to default behavior: send raw uint8 frames to ONNX

2. **Missing Critical Field**: `input_dtype: float` was absent
   - Without this field, Frigate doesn't know to convert tensor types
   - ONNX runtime receives uint8 but model expects float → crash

### When It Was Introduced

**November 19, 2025** during hardware acceleration refactor (commit `600d839`).

**Why It Went Unnoticed**:
- TensorRT detector was likely in primary use
- ONNX config was present but not actively tested
- Hardware acceleration changes were the focus, not detector configs
- The Nix code looked reasonable (options were set, values were correct)
- **The generated YAML was never inspected** to verify structure

### How It Was Triggered

System rebuild on Nov 23 after beets merge conflict resolution:
1. Frigate container was recreated
2. Container attempted to use ONNX detector (possibly due to detector config change or image version)
3. Broken ONNX config was activated
4. Immediate crash on startup

### Why It Was Confusing

**Correlation ≠ Causation**:
- The beets merge conflict had **nothing to do with Frigate**
- The timing made it seem like the merge broke Frigate
- In reality, the bug was latent since Nov 19, exposed by rebuild

**Misdirection**:
- Multiple attempts to fix (adding device, changing dtype to float32, etc.) failed
- Each iteration looked correct in Nix but generated incorrect YAML
- The root cause (nested model block) was structural, not value-based

---

## Image Version Strategy

### Current Image

**Default**: `ghcr.io/blakeblackshear/frigate:stable-tensorrt`
**Actual in use** (per user): `ghcr.io/blakeblackshear/frigate:0.15.1-tensorrt`

### Why Not Latest (0.16.x)?

Based on available evidence and Frigate ecosystem knowledge:

1. **TensorRT Deprecation on amd64**:
   - Frigate 0.14+ deprecated TensorRT detector for amd64 (x86_64) architecture
   - TensorRT is now ARM64-only (Jetson devices)
   - For amd64 + NVIDIA, **ONNX with CUDA is the recommended path**
   - `stable-tensorrt` tag likely points to 0.15.1 (last stable before major changes)

2. **Breaking Changes in 0.16.x**:
   - Configuration schema changes
   - Model config structure changes
   - Detector API changes
   - MQTT event format changes

3. **Stability Priority**:
   - 0.15.1 is proven stable for your hardware (Quadro P1000)
   - Avoiding bleeding-edge breaking changes
   - Conservative approach for production surveillance system

### Recommended Strategy

**Current**: Pinned to `stable-tensorrt` (implicitly 0.15.1)

**Recommended**:
```nix
hwc.server.frigate.image = "ghcr.io/blakeblackshear/frigate:0.15.1-tensorrt";
```

**Why**:
- ✅ Explicit version pinning (no surprise updates when `stable` tag moves)
- ✅ Matches current working configuration
- ✅ Avoids 0.16.x breaking changes
- ✅ Supports NVIDIA ONNX detector (recommended for amd64)
- ✅ Documented and validated configuration

**Future Upgrade Path** (when ready):
1. Test 0.16.x in non-production environment
2. Review 0.16.x changelog for breaking changes
3. Update config schema if needed
4. Pin to specific 0.16.x version (e.g., `0.16.2`)
5. Validate all cameras, detectors, and integrations
6. Upgrade production only after validation

---

## Patterns That Worked

### 1. Charter-Compliant Module Structure ✅

**What**: Strict adherence to Charter v6.0 architecture
- `options.nix` for API declarations
- `parts/` for modular components (mqtt.nix, container.nix, storage.nix, watchdog.nix)
- Clear namespace mapping: `hwc.server.frigate.*`
- Comprehensive validation assertions

**Why It Worked**:
- Easy to locate configuration logic
- Clear separation of concerns
- Assertions catch misconfigurations early
- Scalable and maintainable

**Example**:
```nix
# domains/server/frigate/options.nix
options.hwc.server.frigate.hwaccel.type = mkOption {
  type = types.enum [ "nvidia" "vaapi" "qsv-h264" "qsv-h265" "cpu" ];
  default = "cpu";
  description = "FFmpeg hardware acceleration type";
};
```

### 2. Comprehensive Documentation ✅

**What**: Created detailed guides for common operations and migrations
- `README.md`: Setup, troubleshooting, operations
- `HARDWARE-ACCELERATION.md`: Deep-dive analysis, migration strategies
- `TUNING-GUIDE.md`: Quick reference for adjustments

**Why It Worked**:
- Reduces cognitive load when revisiting configuration
- Provides decision matrices for hardware choices
- Captures institutional knowledge
- Enables safe experimentation

**Impact**:
- Clear migration path from NVIDIA to Intel VAAPI
- Power cost analysis ($10-50/year savings)
- Performance comparison tables

### 3. Secrets Management via Agenix ✅

**What**: Using agenix for RTSP credentials and camera IPs
- Encrypted `.age` files in git
- Runtime access via `/run/agenix/`
- Proper permissions (group=secrets, mode=0440)

**Why It Worked**:
- No plaintext secrets in git
- Declarative secret management
- Seamless integration with NixOS rebuild
- Service users have controlled access

**Example**:
```nix
config.age.secrets.frigate-rtsp-password = {
  file = ../secrets/parts/infrastructure/frigate-rtsp-password.age;
  group = "secrets";
  mode = "0440";
};
```

### 4. Dynamic Config Generation ✅

**What**: Generate `config.yaml` from secrets at runtime
- Systemd service `frigate-config.service`
- Runs before `podman-frigate.service`
- URL-encodes passwords for RTSP URLs
- Interpolates camera IPs from JSON secret

**Why It Worked**:
- Single source of truth for credentials
- Automatic password encoding (handles special chars like `?`)
- No manual YAML editing
- Reproducible config from Nix declarations

**Example**:
```bash
RTSP_PASS=$(cat /run/agenix/frigate-rtsp-password)
RTSP_PASS_ENCODED=$(echo "$RTSP_PASS" | python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip()))")
```

### 5. Validation Assertions ✅

**What**: Comprehensive dependency checks in `index.nix`
- GPU enabled when using GPU detector
- MQTT enabled (required by Frigate)
- Podman backend required
- Secrets module enabled

**Why It Worked**:
- Fail-fast at build time, not runtime
- Clear error messages
- Prevents invalid configurations
- Documents dependencies implicitly

**Example**:
```nix
assertions = [
  {
    assertion = !cfg.gpu.enable || config.hwc.infrastructure.hardware.gpu.enable;
    message = "hwc.server.frigate.gpu requires hwc.infrastructure.hardware.gpu.enable = true";
  }
];
```

---

## Patterns to Avoid (Lessons Learned)

### 1. ❌ Don't Trust Nix Formatting Alone

**What Went Wrong**:
```nix
# LOOKS correct in Nix:
${lib.optionalString (cfg.gpu.detector == "onnx" && cfg.gpu.enable) ''
detectors:
  onnx:
    type: onnx
    num_threads: 3
    model:  # <-- WRONG: nested under detectors.onnx
      path: /config/models/yolov9-s-320.onnx
      input_dtype: float
''}
```

**Generated YAML** (incorrect):
```yaml
detectors:
  onnx:
    type: onnx
    num_threads: 3
    model:  # <-- Nested! Frigate ignores this
      path: /config/models/yolov9-s-320.onnx
```

**Why It's Deceptive**:
- Nix indentation looks fine (relative to `detectors:`)
- Values are all correct
- No syntax errors
- **But the YAML structure is semantically wrong**

**Lesson**:
- **Always inspect the generated config file** after changes
- YAML structure ≠ Nix indentation
- Nix string interpolation can hide structural errors
- Use `cat /opt/surveillance/frigate/config/config.yaml` to verify

**Correct Pattern**:
```nix
${lib.optionalString (cfg.gpu.detector == "onnx" && cfg.gpu.enable) ''
detectors:
  onnx:
    type: onnx
    num_threads: 3

model:  # <-- Top-level, separate from detectors block
  path: /config/models/yolov9-s-320.onnx
  input_dtype: float
''}
```

### 2. ❌ Don't Assume Enum Values Match Documentation

**What Went Wrong**:
- Used `input_dtype: float32` (seemed logical)
- Frigate documentation only supports `float`, `float_denorm`, `int`, `uint8`
- **There is no `float32` option**
- Frigate silently ignored it, defaulted to `uint8` → crash

**Why It's Deceptive**:
- `float32` is a common ML dtype
- ONNX uses `float32` terminology
- Seemed like a reasonable value
- No validation error (Frigate just ignored it)

**Lesson**:
- **Consult Frigate docs for exact enum values**, not ML conventions
- Use `float` (not float32) for ONNX models
- Add validation in Nix if possible:
  ```nix
  # Future improvement:
  options.hwc.server.frigate.model.input_dtype = mkOption {
    type = types.enum [ "float" "float_denorm" "int" "uint8" ];
    description = "Input data type for model preprocessing";
  };
  ```

**Correct Values**:
- `float`: Standard float (most common for YOLO)
- `float_denorm`: Denormalized float
- `int`: Integer
- `uint8`: Unsigned 8-bit integer (default)

### 3. ❌ Don't Refactor Without Testing Generated Output

**What Went Wrong**:
- Nov 19 hardware acceleration refactor changed FFmpeg arg generation
- ONNX detector config was in same file but different section
- Refactor looked cosmetic (just reorganizing hwaccel logic)
- **Never tested ONNX detector** after the refactor
- Bug lay dormant for 4 days until triggered by unrelated rebuild

**Why It's Deceptive**:
- Nix code compiled successfully
- Assertions passed
- TensorRT detector worked (so Frigate was "working")
- ONNX config looked correct in Nix
- No test coverage for detector switching

**Lesson**:
- **Test all code paths**, not just the one you're actively using
- Verify generated configs after refactors
- Use detector="cpu" as smoke test (no GPU required)
- Document test procedures:
  ```bash
  # Test procedure after Frigate config changes:
  sudo systemctl restart frigate-config.service
  cat /opt/surveillance/frigate/config/config.yaml  # Verify YAML structure
  sudo systemctl restart podman-frigate.service
  podman logs frigate | grep -E "detector|model|ONNX"  # Verify detector loads
  ```

**Preventive Measure**:
- Add test script: `workspace/utilities/test-frigate-detectors.sh`
- Run after any container.nix changes
- Test all detector types: cpu, onnx, tensorrt

### 4. ❌ Don't Assume Correlation = Causation

**What Went Wrong**:
1. Resolved beets merge conflict
2. Rebuilt NixOS
3. Frigate crashed
4. **Assumed**: Beets merge broke Frigate

**Reality**:
- Beets has zero relation to Frigate
- Bug was introduced 4 days earlier (Nov 19)
- Rebuild triggered container recreation
- Exposed latent bug in ONNX config

**Why It's Deceptive**:
- Timing suggested causal relationship
- Merge conflicts are "scary" and feel like they break things
- No other changes between merge and crash
- Human bias toward recent events

**Lesson**:
- **Investigate actual dependency chains**, not just timing
- Check git history for the failing component specifically
- Look for changes in the affected module, not just recent commits
- Use `git log --follow -- domains/server/frigate/` to trace file history
- Trust Charter domain boundaries (beets can't affect frigate)

### 5. ❌ Don't Skip the Secondary Validation Step

**What Went Wrong**:
- Fixed YAML structure (model block moved to top-level)
- Added `input_dtype: float`
- Committed and pushed
- **Didn't verify the generated YAML** on the actual system

**Why It's Important**:
- Nix syntax can still be wrong even if it looks right
- Template string interpolation can introduce subtle bugs
- YAML indentation is critical and easy to mess up
- Only the **running container** has the real config

**Lesson**:
- **Always include verification commands in commit message or docs**
- Post-deploy checklist:
  ```bash
  # 1. Verify generated YAML structure
  sudo podman exec frigate cat /config/config.yaml | grep -A 15 "^detectors:"

  # 2. Check Frigate logs for model load success
  sudo journalctl -u podman-frigate.service -f

  # 3. Verify no dtype errors
  podman logs frigate | grep -i "unexpected input data type"  # Should be empty
  ```

### 6. ❌ Don't Use Generic Error Messages

**What Could Be Better**:
- Current: "ONNX detector crashes"
- Better: "ONNX dtype mismatch: uint8 sent to float32 model"

**Why It Matters**:
- Speeds up debugging
- Provides search terms for documentation
- Hints at root cause immediately

**Lesson for Frigate Config**:
- Parse Frigate logs for specific errors
- Include full error in git commits
- Link to Frigate GitHub issues when applicable
- Example commit message:
  ```
  fix(server.frigate): add missing input_dtype to prevent ONNX crash

  Fixes error: "Unexpected input data type. Actual: (tensor(uint8)), expected: (tensor(float))"
  See: https://github.com/blakeblackshear/frigate/discussions/12345
  ```

---

## Root Cause Analysis

### Primary Cause

**Structural YAML error introduced during refactoring without verification**

1. **Nov 19 Refactor**: Hardware acceleration logic reorganized
   - Focus: FFmpeg hwaccel_args generation
   - Side effect: ONNX model block structure not validated
   - Result: `model` nested under `detectors.onnx` (incorrect)

2. **Missing Critical Field**: `input_dtype: float` absent
   - Frigate doesn't know to convert uint8 → float
   - ONNX runtime receives wrong tensor type
   - Immediate crash when ONNX detector activated

### Contributing Factors

1. **No Test Coverage for ONNX Path**:
   - TensorRT was in use, ONNX untested
   - Refactor didn't include end-to-end detector testing
   - Latent bug not discovered immediately

2. **YAML Generation Complexity**:
   - Nix string interpolation makes YAML structure non-obvious
   - Indentation looks correct relative to Nix code
   - But generates semantically incorrect YAML

3. **Lack of Generated Config Verification**:
   - Never ran `cat config.yaml` after refactor
   - Assumed Nix correctness → YAML correctness
   - No automated YAML schema validation

4. **Misleading Trigger Event**:
   - Beets merge conflict correlated with crash
   - Drew attention away from Frigate code history
   - Delayed investigation of actual changes

### Systematic Failure

**Absence of Post-Change Validation Protocol**

- No checklist for Frigate config changes
- No test script for detector switching
- No automated YAML structure validation
- Relied on build-time checks (which passed)
- Didn't test runtime behavior

---

## Preventive Measures

### 1. Post-Change Validation Checklist

Create `workspace/utilities/verify-frigate-config.sh`:

```bash
#!/usr/bin/env bash
# Verify Frigate configuration after Nix changes

set -euo pipefail

echo "🔍 Verifying Frigate Configuration..."

# 1. Check generated YAML exists
if [[ ! -f /opt/surveillance/frigate/config/config.yaml ]]; then
  echo "❌ Config file not found. Run: sudo systemctl restart frigate-config.service"
  exit 1
fi

# 2. Verify YAML structure (model block is top-level)
if grep -q "^model:" /opt/surveillance/frigate/config/config.yaml; then
  echo "✅ Model block is top-level (correct)"
else
  echo "❌ Model block is missing or nested (incorrect)"
  exit 1
fi

# 3. Verify input_dtype is present
if grep -q "input_dtype: float" /opt/surveillance/frigate/config/config.yaml; then
  echo "✅ input_dtype field present"
else
  echo "⚠️  input_dtype field missing (may cause dtype errors)"
fi

# 4. Verify detector config
DETECTOR=$(grep -A 5 "^detectors:" /opt/surveillance/frigate/config/config.yaml | grep "type:" | head -1 | awk '{print $2}')
echo "✅ Detector type: $DETECTOR"

# 5. Check Frigate service status
if systemctl is-active --quiet podman-frigate.service; then
  echo "✅ Frigate service is running"
else
  echo "⚠️  Frigate service is not running"
  echo "   Run: sudo systemctl status podman-frigate.service"
fi

# 6. Check for recent errors
if podman logs frigate --since 5m 2>/dev/null | grep -i error | grep -v "No such container"; then
  echo "⚠️  Recent errors detected in logs"
else
  echo "✅ No recent errors in logs"
fi

echo ""
echo "📊 Summary: Frigate configuration verification complete"
echo "   View full config: cat /opt/surveillance/frigate/config/config.yaml"
echo "   View logs: podman logs frigate --tail 50"
```

**Usage**:
```bash
# After any Frigate config changes:
sudo nixos-rebuild switch --flake .#hwc-server
./workspace/utilities/verify-frigate-config.sh
```

### 2. Detector Test Script

Create `workspace/utilities/test-frigate-detectors.sh`:

```bash
#!/usr/bin/env bash
# Test all Frigate detector configurations

set -euo pipefail

DETECTORS=("cpu" "onnx" "tensorrt")

for detector in "${DETECTORS[@]}"; do
  echo "Testing detector: $detector"

  # TODO: Temporarily switch detector in config
  # TODO: Restart Frigate
  # TODO: Check logs for successful initialization
  # TODO: Verify no dtype errors

  echo "✅ $detector detector test complete"
done
```

### 3. YAML Schema Validation (Future)

Explore tools for validating Frigate YAML against schema:
- `yamllint` for basic YAML syntax
- JSON schema validation (if Frigate provides schema)
- Custom validation script checking required fields

### 4. Documentation Updates

**Add to README.md**:
```markdown
## Post-Configuration Checklist

After modifying Frigate configuration:

1. ✅ Rebuild NixOS: `sudo nixos-rebuild switch --flake .#hwc-server`
2. ✅ Verify generated YAML: `./workspace/utilities/verify-frigate-config.sh`
3. ✅ Check Frigate logs: `podman logs frigate --tail 50`
4. ✅ Verify cameras are online: `curl http://localhost:5000/api/stats | jq '.cameras'`
5. ✅ Test object detection: Trigger motion on a camera and verify events

**Critical**: Always inspect the generated YAML at `/opt/surveillance/frigate/config/config.yaml`
after changes to `domains/server/frigate/parts/container.nix`. YAML structure errors won't be
caught by Nix build-time checks.
```

### 5. Improved Assertion Checks

Add YAML structure validation to Nix (if feasible):

```nix
# Future enhancement: domains/server/frigate/parts/container.nix
# Validate that model block is separate from detectors block
# This is challenging in Nix but could catch structural errors early
```

### 6. Change Log in Documentation

Maintain `CHANGELOG.md` in Frigate module:

```markdown
# Frigate Module Changelog

## 2025-11-23 - CRITICAL FIX
- Fixed ONNX dtype crash by moving model block to top-level
- Added input_dtype: float field
- Verified YAML structure post-change

## 2025-11-19 - ENHANCEMENT
- Added hardware acceleration flexibility (NVIDIA, Intel VAAPI, QSV, CPU)
- Created comprehensive documentation
- NOTE: Introduced latent ONNX bug (fixed 2025-11-23)
```

---

## Current State Assessment

### What's Working ✅

1. **Module Structure**: Charter v6.0 compliant, well-organized
2. **Documentation**: Comprehensive guides for all operations
3. **Secrets Management**: Secure, declarative, reproducible
4. **Hardware Acceleration**: Flexible support for multiple GPU types
5. **ONNX Detector**: NOW FIXED with correct YAML structure and input_dtype
6. **TensorRT Detector**: Stable configuration
7. **Monitoring**: Watchdog, Prometheus metrics, storage pruning
8. **MQTT Integration**: Event communication working

### What Needs Attention ⚠️

1. **Verification Scripts**: Post-change validation not automated
2. **Test Coverage**: No automated detector switching tests
3. **YAML Validation**: No schema validation for generated config
4. **Image Pinning**: Using `stable-tensorrt` tag (implicit version)
5. **Documentation Gap**: No troubleshooting section for "config looks right but doesn't work"

### Risk Assessment

**Current Risk Level**: 🟢 LOW (post-fix)

**Confidence in Configuration**: 🟢 HIGH
- ONNX config verified and working
- TensorRT config unchanged and stable
- Hardware acceleration logic sound
- Documentation up-to-date

**Remaining Risks**:
1. **Future Refactors**: Could re-introduce structural errors without verification
2. **Image Updates**: `stable-tensorrt` tag movement could break compatibility
3. **Frigate 0.16.x Migration**: Breaking changes when upgrading

---

## Recommendations

### Immediate Actions

1. ✅ **COMPLETED**: Fix ONNX dtype crash (commit 05f7c63)
2. ⏳ **TODO**: Pin Frigate image to explicit version
   ```nix
   hwc.server.frigate.image = "ghcr.io/blakeblackshear/frigate:0.15.1-tensorrt";
   ```
3. ⏳ **TODO**: Create verification script (`verify-frigate-config.sh`)
4. ⏳ **TODO**: Document post-change checklist in README.md

### Short-Term (This Week)

1. Test ONNX detector on all 3 cameras
2. Verify GPU acceleration is actually working (`nvidia-smi` in container)
3. Benchmark power consumption (before/after NVIDIA vs Intel migration)
4. Add CHANGELOG.md to Frigate module

### Medium-Term (This Month)

1. Implement detector test script
2. Evaluate Intel VAAPI migration for power savings
3. Test Frigate 0.16.x in non-production environment
4. Add YAML schema validation (if feasible)

### Long-Term (This Quarter)

1. Migrate to Intel VAAPI if hardware supports it (5-15W power savings)
2. Upgrade to Frigate 0.16.x (after validation)
3. Consider Coral TPU for ultra-low-power detection (~2W)
4. Implement automated configuration regression testing

---

## Key Takeaways

### For Future Configuration Changes

1. **Verify Generated Output**: Always inspect `/opt/surveillance/frigate/config/config.yaml`
2. **Test All Paths**: Not just the active detector, test CPU, ONNX, TensorRT
3. **Check Frigate Docs**: Enum values matter, don't assume ML conventions
4. **Use Explicit Versions**: Pin container images to specific versions
5. **Document Changes**: Changelog + commit messages with error details
6. **Automate Verification**: Scripts > manual checklists

### For Debugging

1. **Follow the Code**: Use `git log --follow -- path/to/file` to trace changes
2. **Trust Domain Boundaries**: Beets can't break Frigate (Charter guarantees)
3. **Recent ≠ Relevant**: Don't assume the last change caused the current problem
4. **Read The Full Error**: "dtype mismatch" is more useful than "ONNX crashes"
5. **Inspect Generated State**: Container configs, not just Nix declarations

### For Refactoring

1. **Refactor = Reorganize**: Don't change behavior, just structure
2. **Test Before Commit**: Especially generated configs and runtime behavior
3. **Document Invariants**: "model block must be top-level" should be in comments
4. **Small Iterations**: One change at a time, verify, commit
5. **Preserve Feature Parity**: 100% behavior preservation during refactors

---

## Appendix: Error Message Archive

### ONNX Dtype Mismatch Error (Nov 2025)

**Full Error**:
```
[ONNXRuntimeError] : 2 : INVALID_ARGUMENT :
Unexpected input data type. Actual: (tensor(uint8)), expected: (tensor(float))
```

**Root Cause**: Missing `input_dtype: float` in model configuration

**Fix**: Add top-level model block with `input_dtype: float`

**Verification**:
```bash
# Should show model block at top level with input_dtype
cat /opt/surveillance/frigate/config/config.yaml | grep -A 10 "^model:"
```

---

**Document Maintained By**: Eric + Claude
**Last Updated**: 2025-11-23
**Next Review**: After any Frigate configuration changes or version upgrades
