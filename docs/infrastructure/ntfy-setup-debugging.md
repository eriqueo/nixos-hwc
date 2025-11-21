# ntfy Setup Summary - Current State and Issues

**Date**: 2025-11-21
**Issue**: Phone app cannot connect to ntfy server

---

## 🔍 What's Currently Configured

### 1. ntfy CLI Client (WORKING)
**Location**: `domains/system/services/ntfy/`

**Module**: Creates `hwc-ntfy-send` command for SENDING notifications
- **Purpose**: Client tool to send notifications TO an ntfy server
- **Installed on**: Both laptop and server
- **Configured in**:
  - `machines/server/config.nix`: `hwc.system.services.ntfy.enable = true`
  - `machines/laptop/config.nix`: `hwc.system.services.ntfy.enable = true`

**Current Settings**:
```nix
# Server
serverUrl = "https://hwc.ocelot-wahoo.ts.net/notify";
defaultTopic = "hwc-server-events";

# Laptop
serverUrl = "https://hwc.ocelot-wahoo.ts.net/notify";
defaultTopic = "hwc-laptop-events";
```

### 2. ntfy Server Container (PROBABLY RUNNING)
**Location**: `domains/server/networking/parts/ntfy.nix`

**Container Configuration**:
```nix
virtualisation.oci-containers.containers.ntfy = {
  image = "binwiederhier/ntfy:latest";
  ports = [ "8080:80" ];  # Exposed on localhost:8080
  volumes = [
    "/var/lib/hwc/ntfy:/var/cache/ntfy"
    "/var/lib/hwc/ntfy/etc:/etc/ntfy"
  ];
};
```

**Enabled by**: `hwc.services.ntfy.enable = true;` (in options.nix)

---

## ❌ What's MISSING - THE PROBLEM!

### **NO REVERSE PROXY ROUTE CONFIGURED!**

**The ntfy container is running on `localhost:8080`, but there's NO Caddy route to expose it!**

**File**: `domains/server/routes.nix`
**What's needed**: A route entry for ntfy at `/notify` path

**Expected entry** (MISSING):
```nix
{
  name = "ntfy";
  mode = "subpath";
  path = "/notify";
  upstream = "http://127.0.0.1:8080";
  needsUrlBase = false;  # ntfy handles subpath natively
}
```

---

## 🏗️ Current Architecture (INCOMPLETE)

```
┌─────────────────────────────────────────────────────────────┐
│  Phone App                                                    │
│  Tries: https://hwc.ocelot-wahoo.ts.net/notify/hwc-alerts   │
└─────────────────────────┬─────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│  Caddy Reverse Proxy (hwc-server)                           │
│  ❌ NO ROUTE for /notify → FAILS HERE!                      │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼ (Should go to)
┌─────────────────────────────────────────────────────────────┐
│  ntfy Container (hwc-server)                                │
│  localhost:8080                                              │
│  ✅ Running but not exposed                                 │
└─────────────────────────────────────────────────────────────┘
```

---

## 📋 Current File Configuration

### 1. Client Configuration (hwc-ntfy-send)

**File**: `domains/system/services/ntfy/index.nix`
- Creates CLI tool that sends notifications
- Uses `cfg.serverUrl` to determine where to send
- Constructs URLs as: `$serverUrl/$topic`

**File**: `machines/server/config.nix` (lines 67-83)
```nix
hwc.system.services.ntfy = {
  enable = true;
  serverUrl = "https://hwc.ocelot-wahoo.ts.net/notify";
  defaultTopic = "hwc-server-events";
  defaultTags = [ "hwc" "server" "production" ];
  defaultPriority = 4;
  hostTag = true;
  auth.enable = false;
};
```

**File**: `machines/laptop/config.nix` (lines 74-90)
```nix
hwc.system.services.ntfy = {
  enable = true;
  serverUrl = "https://hwc.ocelot-wahoo.ts.net/notify";
  defaultTopic = "hwc-laptop-events";
  defaultTags = [ "hwc" "laptop" ];
  defaultPriority = 3;
  hostTag = true;
  auth.enable = false;
};
```

### 2. Server Container Configuration

**File**: `domains/server/networking/parts/ntfy.nix`
```nix
config = lib.mkIf cfg.enable {
  virtualisation.oci-containers.containers.ntfy = {
    image = "binwiederhier/ntfy:latest";
    ports = [ "${toString cfg.port}:80" ];  # Default port: 8080
    volumes = [
      "${cfg.dataDir}:/var/cache/ntfy"
      "${cfg.dataDir}/etc:/etc/ntfy"
    ];
    environment = {
      TZ = "America/Denver";
    };
  };

  networking.firewall.allowedTCPPorts = [ cfg.port ];
};
```

**File**: `domains/server/networking/options.nix` (lines 51-65)
```nix
options.hwc.services.ntfy = {
  enable = lib.mkEnableOption "ntfy notification service";

  port = lib.mkOption {
    type = lib.types.port;
    default = 8080;
    description = "ntfy web port";
  };

  dataDir = lib.mkOption {
    type = lib.types.path;
    default = "${paths.state}/ntfy";  # /var/lib/hwc/ntfy
    description = "Data directory";
  };
};
```

### 3. Reverse Proxy Configuration (MISSING ROUTE!)

**File**: `domains/server/routes.nix`
- Has routes for jellyseerr, navidrome, immich, frigate, etc.
- **MISSING**: ntfy route at /notify

---

## 🔧 How You're Trying to Configure the Phone

**Phone App**: ntfy Android/iOS app

**Your Configuration Attempts**:

1. **Server**: `https://hwc.ocelot-wahoo.ts.net/notify`
   - **Topic**: `hwc-alerts`
   - **Expected URL**: `https://hwc.ocelot-wahoo.ts.net/notify/hwc-alerts`
   - **Result**: ❌ "Unexpected response from server"

2. **Server**: `https://hwc.ocelot-wahoo.ts.net`
   - **Topic**: `hwc-alerts`
   - **Expected URL**: `https://hwc.ocelot-wahoo.ts.net/hwc-alerts`
   - **Result**: ❌ Same error

**Why it's failing**:
- Caddy doesn't have a route configured for `/notify/*`
- When the phone tries to connect to `https://hwc.ocelot-wahoo.ts.net/notify/hwc-alerts`, Caddy returns 404 or default page
- The ntfy container is running on `localhost:8080` but is NOT exposed via Caddy

---

## ✅ What curl Tests Showed

```bash
# Test 1: Root path
curl -v https://hwc.ocelot-wahoo.ts.net/test-topic
# Result: HTTP 200 (probably Caddy default response or another service)

# Test 2: /notify path
curl -v https://hwc.ocelot-wahoo.ts.net/notify/test-topic
# Result: HTTP 200 (same - NOT actually reaching ntfy!)
```

**Both returned 200** because:
- Caddy is responding (not 404), but
- It's NOT proxying to the ntfy container
- Probably returning a default page or catching all routes

---

## 🎯 THE FIX

### Step 1: Check if ntfy container is running

```bash
# On server
sudo podman ps | grep ntfy
# or
sudo docker ps | grep ntfy

# Check if port 8080 is listening
sudo ss -tlnp | grep 8080

# Test direct access
curl http://localhost:8080
# Should return ntfy web interface or JSON response
```

### Step 2: Add Reverse Proxy Route

**File**: `domains/server/routes.nix`

Add this entry to the routes list:

```nix
{
  name = "ntfy";
  mode = "subpath";
  path = "/notify";
  upstream = "http://127.0.0.1:8080";
  needsUrlBase = false;
  headers = {
    "X-Forwarded-For" = "$remote_addr";
    "X-Forwarded-Proto" = "$scheme";
  };
}
```

### Step 3: Enable ntfy Server Service

**Check if enabled**: Look for `hwc.services.ntfy.enable = true;` in:
- `profiles/server.nix`, OR
- `machines/server/config.nix`

**If NOT enabled**, add to `machines/server/config.nix`:

```nix
# ntfy notification server (container)
hwc.services.ntfy = {
  enable = true;
  port = 8080;  # Default
  dataDir = "/var/lib/hwc/ntfy";  # Default
};
```

### Step 4: Rebuild and Test

```bash
# Rebuild server
sudo nixos-rebuild switch --flake .#hwc-server

# Test local access
curl http://localhost:8080

# Test via Caddy
curl https://hwc.ocelot-wahoo.ts.net/notify

# Send test notification
curl -d "Test message" https://hwc.ocelot-wahoo.ts.net/notify/test-topic

# Or use CLI tool
hwc-ntfy-send test-topic "Test" "This is a test"
```

### Step 5: Phone Configuration (After Fix)

**Server**: `https://hwc.ocelot-wahoo.ts.net/notify`
**Topics**:
- `hwc-critical`
- `hwc-alerts`
- `hwc-backups`
- `hwc-media`

---

## 📁 Key Files to Check/Modify

1. **routes.nix** - Add ntfy route (MUST DO)
2. **profiles/server.nix** or **machines/server/config.nix** - Enable ntfy service
3. **Check container**: `sudo podman ps | grep ntfy`
4. **Check port**: `sudo ss -tlnp | grep 8080`

---

## 🐛 Debugging Commands

```bash
# Check if ntfy service is enabled in config
nix eval .#nixosConfigurations.hwc-server.config.hwc.services.ntfy.enable

# Check if container is running
sudo podman ps -a | grep ntfy

# Check ntfy container logs
sudo podman logs ntfy

# Check Caddy config
sudo cat /etc/caddy/Caddyfile | grep -A 10 notify

# Test direct container access
curl http://localhost:8080

# Test through Caddy
curl https://hwc.ocelot-wahoo.ts.net/notify
```

---

## 📱 Expected Phone App Behavior (After Fix)

1. Open ntfy app
2. Tap "+" to add subscription
3. **Server**: `https://hwc.ocelot-wahoo.ts.net/notify`
4. **Topic**: `hwc-alerts` (or any topic)
5. Tap "Subscribe"
6. Should connect successfully
7. Send test: `hwc-ntfy-send hwc-alerts "Test" "Testing"`
8. Phone receives notification

---

## Summary

**The Problem**: The ntfy CLIENT is configured (hwc-ntfy-send), but the ntfy SERVER reverse proxy route is MISSING.

**What works**:
- ✅ CLI client tool (`hwc-ntfy-send`)
- ✅ ntfy container (probably running)
- ✅ Client configuration pointing to correct URL

**What's broken**:
- ❌ NO reverse proxy route in `domains/server/routes.nix`
- ❌ Phone can't reach ntfy because Caddy isn't proxying `/notify/*`

**Next step**: Add the route entry to `routes.nix` and rebuild!
