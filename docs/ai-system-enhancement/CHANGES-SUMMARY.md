# AI System Enhancement - Changes Summary (v2)

## Overview

This enhancement fixes the broken ai-chat CLI and adds Open WebUI as a modern web interface for your local Ollama instance, properly integrated with your centralized routing system.

## Files Modified

### 1. `domains/home/environment/shell/options.nix`
**Line 124:**
```diff
- "ai-chat" = "ollama run llama3.2:3b";
+ "ai-chat" = "ai-chat";  # Use the actual Python CLI tool with conversation history
```

**Already merged to main**

---

### 2. `domains/server/ai/local-workflows/options.nix`
**Line 159:**
```diff
- default = "You are a helpful AI assistant. Be concise.";
+ default = "You are an AI assistant running on the HWC home server, a NixOS-based system managed by Eric...";
```

**Already merged to main**

---

### 3. `domains/server/routes.nix`
**Added route entry for Open WebUI:**

```nix
# Open WebUI - AI chat interface (subpath mode)
{
  name = "openwebui";
  mode = "subpath";
  path = "/ai";
  upstream = "http://127.0.0.1:3000";
  needsUrlBase = false;  # Strip /ai prefix - Open WebUI works without URL base
  headers = { "X-Forwarded-Prefix" = "/ai"; };
}
```

**Why:** Integrates with your centralized routing system instead of creating standalone Caddy config.

---

### 4. `profiles/ai.nix`
**Added import:**

```nix
imports = [
  ../domains/server/ai/ollama
  ../domains/server/ai/mcp
  ../domains/server/ai/local-workflows
  ../domains/server/ai/ai-bible
  ../domains/server/ai/open-webui  # Added
];
```

**Why:** Makes Open WebUI available when AI profile is imported.

---

## Files Created

### New Module: `domains/server/ai/open-webui/`

#### 5. `domains/server/ai/open-webui/options.nix`
**Purpose:** Configuration options for Open WebUI

**Key Changes from v1:**
- ❌ Removed `domain` option (not needed with centralized routing)
- ✅ Kept all other options (port, auth, RAG, etc.)

**Options provided:**
```nix
hwc.server.ai.open-webui = {
  enable                 # Enable/disable module
  port                   # Internal port (default: 3000)
  ollamaEndpoint         # Ollama API URL
  dataDir                # Data storage location
  enableAuth             # User authentication
  defaultModel           # Default model for chats
  enableRAG              # Document upload features
  ragChunkSize           # RAG chunk size
  ragOverlap             # RAG overlap size
  imageTag               # Docker image version
  extraEnv               # Additional environment variables
}
```

---

#### 6. `domains/server/ai/open-webui/default.nix`
**Purpose:** Module entry point with container configuration

**Key Changes from v1:**
- ✅ Fixed imports-in-config violation
- ✅ Inline container configuration (no separate parts files)
- ❌ Removed standalone Caddy configuration
- ✅ Proper 3-section structure (OPTIONS, IMPLEMENTATION, VALIDATION)

**Structure:**
```nix
{
  imports = [ ./options.nix ];  # At module level, not in config
  
  config = lib.mkIf cfg.enable {
    # Container configuration inline
    virtualisation.oci-containers.containers.open-webui = { ... };
    
    # Podman enablement
    virtualisation.podman = { ... };
    
    # Service dependencies
    systemd.services.podman-open-webui = { ... };
    
    # Data directory
    systemd.tmpfiles.rules = [ ... ];
  };
  
  config.assertions = [ ... ];  # Validation
}
```

---

## Architecture Changes

### v1 (Incorrect)
```
Open WebUI → Standalone Caddy Config → Subdomain
```
**Problems:**
- Bypassed centralized routing
- Created subdomain config
- Violated Charter routing patterns

### v2 (Correct)
```
Open WebUI → Centralized Routing (routes.nix) → Subpath
```
**Benefits:**
- Integrates with existing routing system
- Uses subpath mode (/ai)
- Follows Charter patterns
- Consistent with other services

---

## Deployment

### Enable in Server Config

```nix
# In machines/server/config.nix or similar
hwc.server.ai.open-webui = {
  enable = true;
};
```

### Rebuild

```bash
sudo nixos-rebuild switch
```

### Access

- **CLI:** `ai-chat`
- **Web:** https://hwc.ocelot-wahoo.ts.net/ai

---

## Testing Checklist

After deployment, verify:

- [ ] ai-chat CLI works with `ai-chat` command
- [ ] AI has server context (ask "what services are running?")
- [ ] Conversation history persists across sessions
- [ ] Open WebUI container is running (`sudo podman ps`)
- [ ] Web UI accessible at https://hwc.ocelot-wahoo.ts.net/ai
- [ ] Can create account in Web UI (if auth enabled)
- [ ] Can switch models in both CLI and Web UI
- [ ] Can export conversations
- [ ] Routing works through centralized system

---

## Charter Compliance

| Aspect              | v1 Status | v2 Status | Notes                                      |
|---------------------|-----------|-----------|-------------------------------------------|
| Namespace alignment | ✅ Pass    | ✅ Pass    | domains/server/ai/open-webui → hwc.server.ai.open-webui |
| options.nix pattern | ✅ Pass    | ✅ Pass    | All options in dedicated file              |
| 3-section structure | ❌ Fail    | ✅ Pass    | Fixed imports-in-config violation          |
| Validation section  | ✅ Pass    | ✅ Pass    | Good assertions present                    |
| Domain boundaries   | ✅ Pass    | ✅ Pass    | Server domain, no HM leakage               |
| Lane purity         | ✅ Pass    | ✅ Pass    | No cross-lane imports                      |
| Routing integration | ❌ Fail    | ✅ Pass    | Now uses centralized routing system        |

---

## Rollback Instructions

If you need to revert changes:

### Disable Open WebUI
```nix
hwc.server.ai.open-webui.enable = false;
```

### Remove Route (optional)
Comment out the Open WebUI entry in `domains/server/routes.nix`

### Remove Import (optional)
Comment out the import in `profiles/ai.nix`

Then rebuild:
```bash
sudo nixos-rebuild switch
```

---

## Summary

**v2 Fixes:**
- ✅ Removed standalone Caddy config
- ✅ Integrated with centralized routing (routes.nix)
- ✅ Fixed imports-in-config violation
- ✅ Removed unnecessary domain option
- ✅ Added to AI profile imports
- ✅ Updated documentation

**Result:**
A Charter-compliant Open WebUI integration that follows your existing routing patterns and works seamlessly with your infrastructure.
