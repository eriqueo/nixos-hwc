# Plan: Integrate Ollama with Transcript API via AI Domain

## Task Overview
Incorporate Ollama into the transcript API service using the new AI domain and profile architecture, enabling LLM-based transcript polishing.

## Current Status: Investigation

### What We Know
- Transcript API currently shows: `ERROR - ❌ Ollama not found in PATH! LLM polishing will fail`
- There is now an AI domain (`domains/ai/`) and AI profile (`profiles/ai.nix`)
- Transcript API has LLM polishing capability but can't find Ollama

### Investigation Needed
1. How is Ollama configured in the AI domain?
2. What options are exposed via `hwc.ai.*` namespace?
3. How should transcript API access Ollama?
4. What's the proper dependency chain?

---

## Investigation Complete

### Key Findings

**Ollama Configuration**:
- Runs as Podman container (`ollama/ollama:latest`) on port 11434
- Binary added to `environment.systemPackages` (available system-wide)
- Namespace: `hwc.ai.ollama.*`
- Models auto-pulled on boot via `ollama-pull-models.service`

**Transcript API Current Issue**:
- Python LLM polisher calls `ollama` CLI command via subprocess
- Transcript API service has no `ollama` in its PATH
- No dependency on `ollama.service` declared

**Existing Pattern** (from `local-workflows`):
```nix
systemd.services.hwc-ai-workflows-api = {
  after = [ "network.target" "ollama.service" ];
  wants = [ "ollama.service" ];
}
assertions = [{
  assertion = cfg.enable -> config.hwc.ai.ollama.enable;
  message = "requires Ollama to be enabled";
}];
```

---

## User Requirements Confirmed

✅ **Optional dependency**: LLM polishing with graceful fallback if Ollama unavailable
✅ **HTTP API**: Modernize from CLI subprocess to HTTP calls
✅ **Enable AI profile**: Add `profiles/ai.nix` to server machine configuration

---

## Recommended Solution

### Strategy Overview

**Three-Phase Implementation**:
1. **Profile Integration**: Enable AI domain on server
2. **Service Dependency**: Add optional Ollama dependency to transcript API
3. **Code Modernization**: Refactor Python LLM polisher from CLI to HTTP API

### Phase 1: Enable AI Profile on Server

**Goal**: Make Ollama available on the server machine

**File**: `machines/server/config.nix`

**Change**: Add AI profile to imports
```nix
imports = [
  ./hardware.nix
  ../../profiles/server.nix
  ../../profiles/ai.nix        # ADD THIS LINE
];
```

**What This Enables**:
- `hwc.ai.ollama.enable = true` (default from `profiles/ai.nix`)
- Ollama container on port 11434
- Auto-pull models: `["phi3.5:3.8b", "llama3.2:3b"]`
- Ollama binary in system PATH
- Health checks and monitoring

**Charter Compliance**: ✓ Machine imports profiles (valid pattern)

---

### Phase 2: Add Optional Ollama Dependency to Transcript API

**Goal**: Make transcript API aware of Ollama without hard requirement

**File**: `domains/server/networking/parts/transcript-api.nix`

**Changes**:

**2a. Add Environment Variable** (line ~66):
```nix
environment = {
  API_HOST = "0.0.0.0";
  API_PORT = toString cfg.port;
  TRANSCRIPTS_ROOT = cfg.dataDir;
  LANGS = "en,en-US,en-GB";
  COUCHDB_URL = "http://127.0.0.1:5984";
  COUCHDB_DATABASE = "sync_transcripts";

  # ADD: Ollama configuration (optional)
  OLLAMA_HOST = "http://127.0.0.1:11434";
};
```

**2b. Add Service Dependency** (line ~54):
```nix
systemd.services.transcript-api = {
  description = "YouTube Transcript API";
  wantedBy = [ "multi-user.target" ];
  after = [ "network.target" ];  # CHANGE to:
  after = [ "network.target" ]
    ++ lib.optional config.hwc.ai.ollama.enable "podman-ollama.service";
  wants = lib.optional config.hwc.ai.ollama.enable "podman-ollama.service";
```

**Rationale**:
- **Optional**: Only adds dependency if Ollama enabled
- **Graceful**: Service starts even if Ollama not available
- **Ordered**: Waits for Ollama to be ready before starting
- Uses `podman-ollama.service` (the actual container service)

**Note**: No assertion needed since it's optional. Python code handles fallback.

---

### Phase 3: Modernize Python LLM Polisher

**Goal**: Replace subprocess `ollama run` with HTTP API calls

**File**: `workspace/productivity/transcript-formatter/cleaners/llm.py`

**Changes**:

**3a. Update Imports** (top of file):
```python
import asyncio
import logging
import re
import os                    # ADD
from typing import List, Set
import httpx                 # ADD (already available via transcript-api deps)
```

**3b. Update `__init__`** (line ~22):
```python
def __init__(self, model: str = "llama3:8b", temperature: float = 0.3, max_concurrent: int = 2):
    self.model = model
    self.temperature = temperature
    self.max_concurrent = max_concurrent
    self.logger = logging.getLogger(__name__)

    # ADD: Get Ollama host from environment
    self.ollama_host = os.getenv("OLLAMA_HOST", "http://127.0.0.1:11434")

    # Chunking parameters
    self.chunk_size = 6000
    self.chunk_overlap = 400
    self._semaphore = asyncio.Semaphore(max_concurrent)
```

**3c. Replace `_polish_chunk` method** (line ~106-119):

**Before** (subprocess approach):
```python
proc = await asyncio.create_subprocess_exec(
    "ollama", "run", self.model, "--temperature", str(self.temperature),
    stdin=asyncio.subprocess.PIPE,
    stdout=asyncio.subprocess.PIPE,
    stderr=asyncio.subprocess.PIPE
)
stdout, stderr = await asyncio.wait_for(
    proc.communicate(prompt.encode()),
    timeout=180.0
)
```

**After** (HTTP API approach):
```python
async with httpx.AsyncClient(timeout=180.0) as client:
    response = await client.post(
        f"{self.ollama_host}/api/generate",
        json={
            "model": self.model,
            "prompt": prompt,
            "stream": False,
            "options": {
                "temperature": self.temperature,
            }
        }
    )
    response.raise_for_status()
    result = response.json()
    polished = result["response"].strip()
```

**Error Handling** (update exception handling):
```python
except httpx.HTTPError as e:
    self.logger.error(f"Ollama HTTP request failed: {e}")
    raise RuntimeError(f"Ollama API error: {e}")
except httpx.TimeoutException:
    self.logger.error(f"Ollama request timed out for chunk {chunk_num}")
    raise RuntimeError("Ollama request timed out")
```

**3d. Add Availability Check** (new method):
```python
async def is_available(self) -> bool:
    """Check if Ollama is available and has the required model."""
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            # Check Ollama is running
            response = await client.get(f"{self.ollama_host}/api/tags")
            response.raise_for_status()

            # Check model is available
            tags = response.json()
            models = [m["name"] for m in tags.get("models", [])]

            # Model name might include tag (e.g., "llama3.2:3b" vs "llama3.2")
            model_base = self.model.split(":")[0]
            available = any(model_base in m for m in models)

            if not available:
                self.logger.warning(f"Model {self.model} not found in Ollama")

            return available
    except Exception as e:
        self.logger.warning(f"Ollama not available: {e}")
        return False
```

**3e. Update Main API** (`yt-transcript-api.py` startup):

Find where `LLMTranscriptPolisher` is initialized (around line 279-337) and add availability check:

```python
@app.on_event("startup")
async def startup_event():
    logger.info("Starting HWC Transcript API...")
    logger.info("=" * 70)
    logger.info("✓ Basic cleaner initialized")

    # ADD: Check Ollama availability
    try:
        llm_polisher = LLMTranscriptPolisher()
        if await llm_polisher.is_available():
            logger.info(f"✓ Ollama available with model: {llm_polisher.model}")
        else:
            logger.warning("⚠ Ollama not available - LLM polishing disabled")
    except Exception as e:
        logger.error(f"❌ Ollama check failed: {e}")

    logger.info("=" * 70)
```

---

### Benefits of This Approach

**Why HTTP API over CLI**:
1. **More Robust**: Better error handling, timeout control
2. **Standard Protocol**: REST API is Ollama's primary interface
3. **Better Logging**: Can inspect request/response details
4. **Performance**: No subprocess overhead
5. **Streaming Support**: Can add streaming responses later

**Why Optional Dependency**:
1. **Flexibility**: Service works without AI features
2. **Graceful Degradation**: Falls back to basic cleaning
3. **Easier Testing**: Can test transcript extraction without Ollama
4. **Resource Efficiency**: Don't require GPU if not needed

**Why Enable AI Profile**:
1. **Consistency**: AI services managed together
2. **Simplicity**: One profile for all AI features
3. **Maintainability**: Centralized AI configuration
4. **Future-Proof**: Easy to add more AI services later

---

## Implementation Steps

### Step 1: Enable AI Profile (5 minutes)
1. Edit `machines/server/config.nix`
2. Add `../../profiles/ai.nix` to imports
3. Rebuild: `sudo nixos-rebuild switch --flake .#hwc-server`
4. Verify Ollama running: `systemctl status podman-ollama.service`
5. Verify models pulled: `curl http://127.0.0.1:11434/api/tags | jq`

### Step 2: Add Service Dependency (10 minutes)
1. Edit `domains/server/networking/parts/transcript-api.nix`
2. Add `OLLAMA_HOST` environment variable
3. Add conditional service dependency on `podman-ollama.service`
4. Rebuild: `sudo nixos-rebuild switch --flake .#hwc-server`
5. Verify service starts: `systemctl status transcript-api.service`
6. Check logs for Ollama detection

### Step 3: Modernize Python Code (30 minutes)
1. Edit `workspace/productivity/transcript-formatter/cleaners/llm.py`
2. Add `httpx` imports and `ollama_host` configuration
3. Replace `_polish_chunk` subprocess code with HTTP API
4. Add `is_available()` method
5. Update error handling for HTTP errors
6. Test locally if possible

### Step 4: Update API Startup (10 minutes)
1. Edit `workspace/productivity/transcript-formatter/yt-transcript-api.py`
2. Add Ollama availability check in startup event
3. Ensure graceful fallback messaging

### Step 5: Testing (20 minutes)
1. Restart transcript API: `sudo systemctl restart transcript-api.service`
2. Check logs: `journalctl -u transcript-api.service -n 50`
3. Verify Ollama detected (should see ✓ not ❌)
4. Test API endpoint with `format=llm`:
   ```bash
   curl -X POST http://127.0.0.1:8099/api/transcript-text \
     -H "Content-Type: application/json" \
     -d '{"url":"https://www.youtube.com/watch?v=jNQXAC9IVRw","format":"llm"}' | jq
   ```
5. Verify LLM-polished output different from basic
6. Test fallback: stop Ollama, verify basic cleaning still works

### Step 6: Commit Changes (5 minutes)
1. Stage all changes
2. Commit with clear message
3. Document in commit what was changed and why

---

## Testing Strategy

### Test Case 1: Ollama Available
- **Setup**: AI profile enabled, Ollama running, model pulled
- **Expected**: LLM polishing works, high-quality output
- **Verify**: Log shows "✓ Ollama available"

### Test Case 2: Ollama Unavailable
- **Setup**: Stop Ollama container
- **Expected**: Falls back to basic cleaning, no errors
- **Verify**: Log shows "⚠ Ollama not available"

### Test Case 3: Model Missing
- **Setup**: Ollama running but model not pulled
- **Expected**: Warning logged, graceful fallback
- **Verify**: API returns basic cleaned transcript

### Test Case 4: Ollama Timeout
- **Setup**: Slow model response (simulate with large prompt)
- **Expected**: Timeout after 180s, error logged
- **Verify**: Proper error message returned

### Test Case 5: Service Startup Order
- **Setup**: Restart both services
- **Expected**: transcript-api waits for Ollama
- **Verify**: No race conditions in logs

---

## Rollback Strategy

**If AI profile causes issues**:
```bash
# Revert machine config
git checkout machines/server/config.nix
sudo nixos-rebuild switch --flake .#hwc-server
```

**If service dependency breaks**:
```bash
# Remove dependency, rebuild
sudo nixos-rebuild switch --rollback
```

**If Python HTTP code fails**:
- Revert `cleaners/llm.py` to subprocess version
- Service automatically restarts
- Falls back to basic cleaning

---

## Charter Compliance

### Domain Boundaries ✓
- **Server domain** manages transcript API service
- **AI domain** manages Ollama configuration
- No cross-domain violations (optional dependency via config)

### Namespace Alignment ✓
- `hwc.ai.ollama.*` → `domains/ai/ollama/`
- `hwc.services.transcriptApi.*` → `domains/server/networking/`

### Validation ✓
- No new assertions needed (optional dependency)
- Existing service validations remain

### Profile Usage ✓
- Machine imports profiles (valid pattern)
- Profiles set sensible defaults
- No implementation logic in profiles

---

## Critical Files

### Files to Modify:

1. **`machines/server/config.nix`**
   - Add `../../profiles/ai.nix` to imports

2. **`domains/server/networking/parts/transcript-api.nix`**
   - Add `OLLAMA_HOST` environment variable
   - Add optional service dependency on `podman-ollama.service`

3. **`workspace/productivity/transcript-formatter/cleaners/llm.py`**
   - Replace subprocess with HTTP API calls
   - Add `is_available()` method
   - Update error handling

4. **`workspace/productivity/transcript-formatter/yt-transcript-api.py`**
   - Add Ollama availability check in startup

### Files to Read (Reference):

5. **`domains/ai/ollama/default.nix`**
   - Understand Ollama service structure

6. **`profiles/ai.nix`**
   - Understand default AI configuration

7. **`domains/ai/local-workflows/default.nix`**
   - Reference for dependency patterns

---

## Success Criteria

**Immediate (after implementation)**:
- [ ] AI profile enabled on server
- [ ] Ollama container running on port 11434
- [ ] Models auto-pulled: `phi3.5:3.8b`, `llama3.2:3b`
- [ ] Transcript API logs show "✓ Ollama available"
- [ ] No "❌ Ollama not found" error
- [ ] Service dependency correct (starts after Ollama)

**Functional (after testing)**:
- [ ] `format=llm` produces polished transcripts
- [ ] `format=basic` still works (fallback)
- [ ] HTTP API calls successful (no subprocess errors)
- [ ] Proper error handling for timeouts
- [ ] Graceful fallback if Ollama stops

**Long-term (after 7 days)**:
- [ ] LLM polishing working consistently
- [ ] No service crashes or restart loops
- [ ] Reasonable resource usage (GPU if available)
- [ ] Model updates work correctly

---

## Estimated Time

- **Profile enablement**: 5 minutes
- **Service dependency**: 10 minutes
- **Python refactoring**: 30 minutes
- **API updates**: 10 minutes
- **Testing**: 20 minutes
- **Commit/docs**: 5 minutes
- **Total**: ~80 minutes (1.5 hours)

---

## Risk Assessment

**Risk Level**: **LOW-MEDIUM**

**Why Low-Medium**:
- Optional dependency (graceful degradation)
- Following existing patterns (local-workflows)
- HTTP API is standard approach
- Easy rollback via NixOS generations
- Python changes isolated to one module

**Mitigation**:
- Test with and without Ollama
- Verify fallback behavior
- Monitor service logs closely
- Keep previous generation available

---

## Future Enhancements (Out of Scope)

1. **Streaming responses**: Use Ollama's streaming API for real-time output
2. **Model selection**: Add API parameter to choose model per request
3. **Prompt tuning**: Make prompts configurable via options
4. **Caching**: Cache LLM outputs for identical transcripts
5. **Batch processing**: Process multiple transcripts in parallel
6. **Metrics**: Add Prometheus metrics for LLM usage
7. **Rate limiting**: Implement request queue for LLM calls

---

## Summary

**Simple, clean integration** following existing patterns:

1. ✅ Enable AI profile on server (one import line)
2. ✅ Add optional Ollama dependency (environment + service deps)
3. ✅ Modernize Python code (subprocess → HTTP API)

**Result**: Transcript API can use Ollama for high-quality polishing when available, gracefully falls back to basic cleaning when not.

**Charter-compliant**, low-risk, well-tested pattern matching local-workflows implementation.
