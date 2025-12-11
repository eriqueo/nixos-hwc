# Prometheus/Grafana Monitoring & Alerting System - Implementation Plan

**Date**: 2025-12-07
**Target**: nixos-hwc server monitoring infrastructure
**Charter**: v7.0 compliant

## Overview

Build a comprehensive, Charter-compliant monitoring and alerting system with:
- Prometheus metrics collection (already running)
- Grafana dashboards (already running, needs improvements)
- **Alertmanager** for alert routing (NEW)
- **n8n** for flexible alert processing and Slack integration (NEW)
- Caddy reverse proxy for Grafana web access
- Dashboard provisioning for Frigate, Immich, System health, Containers, Arr apps
- Multi-severity alerting (P5 Critical, P4 Warning, P3 Info)

## Architecture

```
Prometheus (port 9090) → Alert Rules → Alertmanager (port 9093)
                                              ↓
                                       n8n Webhook (port 5679)
                                              ↓
                                    Parse & Route by Severity
                                              ↓
                                     Slack (all alerts with tags)
                                              ↓
Grafana (port 3000) ← Prometheus         [P5]/[P4]/[P3]
        ↓
Caddy Port 4443
```

## User Requirements

- **Notifications**: Slack via n8n (flexible multi-channel routing)
- **Dashboards**: Frigate, Immich, System health, Container health, Arr apps
- **Access**: Caddy reverse proxy (port mode at 4443)
- **Severity**: P5 (Critical), P4 (Warning), P3 (Info)

## Current State

**Working:**
- ✅ Prometheus on port 9090, 90d retention
- ✅ Grafana on port 3000, Prometheus datasource configured
- ✅ Scraping: node-exporter, Frigate, Immich, transcript-api

**Missing (Charter Violations):**
- ❌ VALIDATION sections in prometheus.nix and grafana.nix
- ❌ Alertmanager module
- ❌ Grafana admin password via agenix
- ❌ Caddy reverse proxy for Grafana
- ❌ Dashboard provisioning

## Corrected Architecture: Separate Modules per Charter v7.0

### Module Structure

Each service gets its own full module directory:

```
domains/server/
├── monitoring/
│   ├── prometheus/
│   │   ├── index.nix       # Prometheus implementation
│   │   ├── options.nix     # hwc.server.monitoring.prometheus.*
│   │   └── parts/          # Config helpers
│   │       └── alerts.nix  # Alert rules
│   ├── grafana/
│   │   ├── index.nix       # Grafana implementation
│   │   ├── options.nix     # hwc.server.monitoring.grafana.*
│   │   └── parts/          # Config helpers
│   │       └── dashboards.nix
│   ├── alertmanager/
│   │   ├── index.nix       # Alertmanager implementation
│   │   ├── options.nix     # hwc.server.monitoring.alertmanager.*
│   │   └── parts/          # Config helpers
│   └── index.nix           # Monitoring domain aggregator
├── n8n/
│   ├── index.nix           # n8n implementation
│   ├── options.nix         # hwc.server.n8n.*
│   └── parts/              # Workflow helpers
│       └── workflows.nix
```

**Namespace mapping**:
- `domains/server/monitoring/prometheus/` → `hwc.server.monitoring.prometheus.*`
- `domains/server/monitoring/grafana/` → `hwc.server.monitoring.grafana.*`
- `domains/server/monitoring/alertmanager/` → `hwc.server.monitoring.alertmanager.*`
- `domains/server/n8n/` → `hwc.server.n8n.*`

## Implementation Phases

### Phase 0: Restructure Existing Modules (45 min)

**Goal**: Convert current flat structure to proper Charter modules

#### 0.1 Create Prometheus Module

**Create directory**: `domains/server/monitoring/prometheus/`

**File**: `domains/server/monitoring/prometheus/options.nix` (NEW)
```nix
{ lib, config, ... }:
let
  paths = config.hwc.paths;
in
{
  options.hwc.server.monitoring.prometheus = {
    enable = lib.mkEnableOption "Prometheus monitoring";
    port = lib.mkOption { type = lib.types.port; default = 9090; };
    dataDir = lib.mkOption { type = lib.types.path; default = "${paths.state}/prometheus"; };
    retention = lib.mkOption { type = lib.types.str; default = "30d"; };
    scrapeConfigs = lib.mkOption { type = lib.types.listOf lib.types.attrs; default = []; };
  };
}
```

**File**: `domains/server/monitoring/prometheus/index.nix` (MOVE from parts/)
- Move content from `parts/prometheus.nix`
- Update to import `./options.nix`
- Add VALIDATION section
- Update namespace to `config.hwc.server.monitoring.prometheus`

**File**: `domains/server/monitoring/prometheus/parts/alerts.nix` (NEW)
- Extract alert rules into separate part
- Pure function returning alert rule definitions

#### 0.2 Create Grafana Module

**Create directory**: `domains/server/monitoring/grafana/`

**File**: `domains/server/monitoring/grafana/options.nix` (NEW)
```nix
{ lib, config, ... }:
let
  paths = config.hwc.paths;
in
{
  options.hwc.server.monitoring.grafana = {
    enable = lib.mkEnableOption "Grafana dashboards";
    port = lib.mkOption { type = lib.types.port; default = 3000; };
    dataDir = lib.mkOption { type = lib.types.path; default = "${paths.state}/grafana"; };
    domain = lib.mkOption { type = lib.types.str; default = "grafana.local"; };
    adminPasswordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to admin password file (via agenix)";
    };
    dashboards = {
      enable = lib.mkEnableOption "Dashboard provisioning" // { default = true; };
      dashboardsPath = lib.mkOption {
        type = lib.types.path;
        default = ./dashboards;
      };
    };
  };
}
```

**File**: `domains/server/monitoring/grafana/index.nix` (MOVE from parts/)
- Move content from `parts/grafana.nix`
- Update to import `./options.nix`
- Add VALIDATION section (Prometheus dependency)
- Update namespace to `config.hwc.server.monitoring.grafana`

**Directory**: `domains/server/monitoring/grafana/dashboards/` (NEW)
- Will contain dashboard JSON files

**File**: `domains/server/monitoring/grafana/parts/dashboards.nix` (NEW)
- Dashboard provisioning helpers

#### 0.3 Update Monitoring Domain Aggregator

**File**: `domains/server/monitoring/index.nix` (UPDATE)
```nix
{ ... }:
{
  imports = [
    ./prometheus
    ./grafana
    ./alertmanager  # Will add in Phase 2
  ];
}
```

**File**: `domains/server/monitoring/options.nix` (DELETE or UPDATE)
- Options now live in each module's options.nix
- This file can be deleted OR kept as a re-export aggregator

### Phase 1: Grafana Security & Routes (30 min)

#### 1.1 Grafana Admin Password

**Create secret**:
```bash
openssl rand -base64 32 | age -r $(sudo age-keygen -y /etc/age/keys.txt) > \
  domains/secrets/parts/server/grafana-admin-password.age
```

**Add to**: `domains/secrets/declarations/server.nix`
```nix
grafana-admin-password = {
  file = ../parts/server/grafana-admin-password.age;
  mode = "0440";
  owner = "eric";
  group = "secrets";
};
```

**Use in**: `grafana/index.nix` → `settings.security.admin_password = "$__file{${cfg.adminPasswordFile}}"`

#### 1.2 Caddy Route

**File**: `domains/server/routes.nix`

Add:
```nix
{
  name = "grafana";
  mode = "port";
  port = 4443;
  upstream = "http://127.0.0.1:3000";
}
```

### Phase 2: Alertmanager Module (45 min)

**Create directory**: `domains/server/monitoring/alertmanager/`

**File**: `domains/server/monitoring/alertmanager/options.nix` (NEW)
```nix
{ lib, config, ... }:
let
  paths = config.hwc.paths;
in
{
  options.hwc.server.monitoring.alertmanager = {
    enable = lib.mkEnableOption "Prometheus Alertmanager";
    port = lib.mkOption { type = lib.types.port; default = 9093; };
    dataDir = lib.mkOption { type = lib.types.path; default = "${paths.state}/alertmanager"; };

    webhookReceivers = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption { type = lib.types.str; };
          url = lib.mkOption { type = lib.types.str; };
          sendResolved = lib.mkOption { type = lib.types.bool; default = true; };
        };
      });
      default = [];
    };

    groupWait = lib.mkOption { type = lib.types.str; default = "30s"; };
    groupInterval = lib.mkOption { type = lib.types.str; default = "5m"; };
    repeatInterval = lib.mkOption { type = lib.types.str; default = "4h"; };
  };
}
```

**File**: `domains/server/monitoring/alertmanager/index.nix` (NEW)
- Full Charter structure: OPTIONS, IMPLEMENTATION, VALIDATION
- services.prometheus.alertmanager configuration
- Webhook routing to n8n
- Run as eric user
- Assert Prometheus enabled
- Assert webhook receivers configured

**Update**: `domains/server/monitoring/index.nix` → add `./alertmanager` to imports

### Phase 3: n8n Module (60 min)

**Create directory**: `domains/server/n8n/`

**Create Slack webhook secret**:
```bash
echo "https://hooks.slack.com/services/YOUR/WEBHOOK/URL" | \
  age -r $(sudo age-keygen -y /etc/age/keys.txt) > \
  domains/secrets/parts/server/slack-webhook-url.age
```

**Add to secrets**: `domains/secrets/declarations/server.nix`

**File**: `domains/server/n8n/options.nix` (NEW)
```nix
{ lib, config, ... }:
let
  paths = config.hwc.paths;
in
{
  options.hwc.server.n8n = {
    enable = lib.mkEnableOption "n8n workflow automation";
    port = lib.mkOption { type = lib.types.port; default = 5678; };
    webhookPort = lib.mkOption { type = lib.types.port; default = 5679; };
    dataDir = lib.mkOption { type = lib.types.path; default = "${paths.state}/n8n"; };
    slackWebhookUrlFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
    };
  };
}
```

**File**: `domains/server/n8n/index.nix` (NEW)
- Full Charter structure: OPTIONS, IMPLEMENTATION, VALIDATION
- services.n8n configuration (native NixOS service)
- SQLite database at dataDir
- Environment variable for Slack webhook
- Run as eric user
- Firewall: Tailscale for UI, localhost for webhooks
- Assert slackWebhookUrlFile configured

**File**: `domains/server/n8n/parts/workflows.nix` (NEW)
- Workflow helpers (future: could provision workflows from Nix)

**Update**: `profiles/server.nix` → add import for `../domains/server/n8n`

### Phase 4: Dashboard Provisioning (60 min)

**Create directory**: `domains/server/monitoring/grafana/dashboards/`

**Dashboard provisioning** (already configured in Phase 0.2):
- Option: `hwc.server.monitoring.grafana.dashboards.dashboardsPath`
- Default: `./dashboards` (relative to grafana module)

**Create dashboard JSON files** in `grafana/dashboards/`:
- `frigate.json` - Camera status, GPU usage, detection performance, zones
- `immich.json` - Storage, job queues, API latency, thumbnails
- `system.json` - CPU, memory, disk, network (node exporter)
- `containers.json` - All Podman containers (cAdvisor or podman_exporter)
- `arr-apps.json` - Sonarr, Radarr, Lidarr, Prowlarr metrics

**Strategy**: Start with minimal valid dashboards, expand iteratively.

### Phase 5: Prometheus Alert Rules (45 min)

**File**: `domains/server/monitoring/prometheus/parts/alerts.nix` (NEW)
- Pure function returning alert rule definitions
- Organized by severity: P5 Critical, P4 Warning, P3 Info

**Example structure**:
```nix
{ pkgs, ... }:
{
  critical = [
    { alert = "DiskSpaceCritical"; expr = ''...''; labels.priority = "P5"; }
    { alert = "ServiceDown"; expr = ''up == 0''; labels.priority = "P5"; }
  ];
  warning = [
    { alert = "DiskSpaceWarning"; expr = ''...''; labels.priority = "P4"; }
    { alert = "HighMemory"; expr = ''...''; labels.priority = "P4"; }
  ];
  info = [
    { alert = "BackupCompleted"; expr = ''...''; labels.priority = "P3"; }
  ];
}
```

**Use in** `prometheus/index.nix`:
```nix
let
  alerts = import ./parts/alerts.nix { inherit pkgs; };
in
{
  services.prometheus.ruleFiles = [
    (pkgs.writeText "hwc-alerts.yml" (builtins.toJSON {
      groups = [{
        name = "hwc_alerts";
        interval = "30s";
        rules = alerts.critical ++ alerts.warning ++ alerts.info;
      }];
    }))
  ];
}
```

**Alert examples**:
- **P5 Critical**: Disk >95%, service down, GPU failure, container crash
- **P4 Warning**: Disk >90%, high CPU/memory, elevated error rates
- **P3 Info**: Backup completed, system updates available

**Alert format**: Include `[P5]`/`[P4]`/`[P3]` tags in annotations.summary for easy Slack filtering.

### Phase 6: n8n Workflow Configuration (Post-deployment)

**Access**: `http://hwc.ocelot-wahoo.ts.net:5678`

**Workflow steps**:
1. **Webhook Trigger**: Path `/alertmanager-webhook`, Method POST
2. **Function Node**: Parse Alertmanager JSON payload
3. **Extract**: severity, priority (P5/P4/P3), alert name, description, labels
4. **HTTP Request**: POST to Slack webhook
5. **Format**:
   - Title: `[P5] CRITICAL: DiskSpaceCritical` (from labels + annotations)
   - Body: Alert description, hostname, metric values
   - Color: Red (P5), Yellow (P4), Gray (P3)
6. **Handle**: Resolved alerts (green color, "RESOLVED" prefix)

**Testing**: Use Alertmanager UI to send test alerts.

### Phase 7: Machine Configuration (15 min)

**File**: `machines/server/config.nix`

Add with corrected namespaces:
```nix
# Monitoring stack - new namespaces
hwc.server.monitoring.prometheus = {
  enable = true;
  retention = "90d";
};

hwc.server.monitoring.grafana = {
  enable = true;
  domain = "hwc.ocelot-wahoo.ts.net";
  adminPasswordFile = config.age.secrets.grafana-admin-password.path;
};

hwc.server.monitoring.alertmanager = {
  enable = true;
  webhookReceivers = [{
    name = "n8n-slack";
    url = "http://localhost:5679/webhook/alertmanager-webhook";
    sendResolved = true;
  }];
};

hwc.server.n8n = {
  enable = true;
  slackWebhookUrlFile = config.age.secrets.slack-webhook-url.path;
};
```

### Phase 8: Validation & Testing (30 min)

**Build checks**:
```bash
nix flake check
./workspace/utilities/lints/charter-lint.sh domains/server/monitoring --fix
```

**Deploy**:
```bash
sudo nixos-rebuild switch --flake .#hwc-server
```

**Runtime validation**:
```bash
# Prometheus
curl http://localhost:9090/api/v1/targets
curl http://localhost:9090/api/v1/alerts

# Alertmanager
curl http://localhost:9093/api/v2/status

# n8n
curl http://localhost:5678/healthz

# Grafana (via Caddy)
curl https://hwc.ocelot-wahoo.ts.net:4443/api/health
```

**Alert flow test**:
```bash
# Trigger ServiceDown alert
sudo systemctl stop podman-frigate.service

# Wait 2 minutes for alert to fire
# Check Slack for [P5] CRITICAL message

# Resolve alert
sudo systemctl start podman-frigate.service

# Check Slack for RESOLVED message
```

**Dashboard test**:
- Open https://hwc.ocelot-wahoo.ts.net:4443
- Login with admin + generated password
- Verify Prometheus datasource connected
- Check dashboards appear in sidebar

## Critical Files to Modify

### New Modules (Full Charter Structure)
1. **Prometheus Module**: `domains/server/monitoring/prometheus/`
   - `index.nix` - Prometheus implementation with VALIDATION
   - `options.nix` - `hwc.server.monitoring.prometheus.*`
   - `parts/alerts.nix` - Alert rule definitions

2. **Grafana Module**: `domains/server/monitoring/grafana/`
   - `index.nix` - Grafana implementation with VALIDATION, provisioning
   - `options.nix` - `hwc.server.monitoring.grafana.*` (with adminPasswordFile, dashboards)
   - `dashboards/*.json` - Dashboard JSON files
   - `parts/dashboards.nix` - Dashboard helpers (optional)

3. **Alertmanager Module**: `domains/server/monitoring/alertmanager/`
   - `index.nix` - Alertmanager implementation with VALIDATION
   - `options.nix` - `hwc.server.monitoring.alertmanager.*`
   - `parts/` - Configuration helpers (optional)

4. **n8n Module**: `domains/server/n8n/`
   - `index.nix` - n8n native service with VALIDATION
   - `options.nix` - `hwc.server.n8n.*`
   - `parts/workflows.nix` - Workflow helpers (future)

### New Secret Files
1. `domains/secrets/parts/server/grafana-admin-password.age` - Encrypted Grafana password
2. `domains/secrets/parts/server/slack-webhook-url.age` - Encrypted Slack webhook

### Modified Files
1. `domains/server/monitoring/index.nix` - Update imports to new module structure
2. `domains/server/monitoring/options.nix` - DELETE (options now in each module)
3. `domains/server/monitoring/parts/*.nix` - DELETE (moved to module directories)
4. `domains/server/routes.nix` - Add Grafana route (port 4443)
5. `domains/secrets/declarations/server.nix` - Add secret declarations
6. `machines/server/config.nix` - Enable services with new namespaces
7. `profiles/server.nix` - Add import for `../domains/server/n8n`

## Charter v7.0 Compliance Checklist

- ✅ Each service is a full module with index.nix, options.nix, parts/
- ✅ All options in module's own `options.nix` (not shared/aggregated)
- ✅ VALIDATION sections in all index.nix implementations
- ✅ Namespace mapping follows directory structure:
  - `domains/server/monitoring/prometheus/` → `hwc.server.monitoring.prometheus.*`
  - `domains/server/monitoring/grafana/` → `hwc.server.monitoring.grafana.*`
  - `domains/server/monitoring/alertmanager/` → `hwc.server.monitoring.alertmanager.*`
  - `domains/server/n8n/` → `hwc.server.n8n.*`
- ✅ Parts/ structure for pure helper functions
- ✅ Secrets via agenix (no plaintext credentials)
- ✅ Services run as eric user (permission simplification)
- ✅ tmpfiles.rules for directory creation
- ✅ Firewall configuration (localhost + Tailscale)
- ✅ Dependency assertions (fail-fast)
- ✅ Clean module headers with dependencies documented

## Expected Outcomes

1. **Monitoring**: Prometheus scraping all targets (Frigate, Immich, node, containers)
2. **Visualization**: Grafana dashboards accessible at https://hwc.ocelot-wahoo.ts.net:4443
3. **Alerting**: Alerts fire based on thresholds → Alertmanager → n8n → Slack
4. **Security**: Admin password via agenix, Caddy reverse proxy with SSL
5. **Maintainability**: Charter-compliant, well-documented, easy to extend

## Post-Implementation Tasks

1. **Populate dashboards**: Expand minimal JSONs with actual panels and queries
2. **Tune alert thresholds**: Adjust based on actual system behavior
3. **Add more alert rules**: Container-specific, service-specific alerts
4. **Configure n8n workflow**: Visual editor at port 5678
5. **Test incident flow**: Simulate failures, verify Slack notifications
6. **Document runbook**: Alert response procedures
7. **Add backup**: Grafana dashboards + n8n workflows to backup rotation

## Notes

- **n8n workflow editing**: Access UI at http://hwc.ocelot-wahoo.ts.net:5678 (Tailscale only)
- **Grafana access**: https://hwc.ocelot-wahoo.ts.net:4443 (SSL via Caddy)
- **Prometheus/Alertmanager**: Localhost only, no external access needed
- **Dashboard development**: Edit JSON files, Grafana reloads every 30s
- **Alert testing**: Use Alertmanager UI to send test alerts before production use
