# domains/business/index.nix
#
# Business domain — Heartwood Craft remodeling business infrastructure
# NAMESPACE: hwc.business.*
#
# Modules:
#   - databases      — hwc PostgreSQL business database layer
#   - estimator      — Estimate Assembler PWA (Vite/React)
#   - firefly        — Firefly III + Pico (personal finance, containerized)
#   - paperless      — Paperless-ngx (document management, containerized)
#   - website         — iheartwoodcraft.com (CMS + 11ty site content)
#
# NOTE: Heartwood MCP (JT tools) moved to domains/system/mcp/parts/jt.nix (hwc.system.mcp.jt.*)

{ config, lib, ... }:
{
  imports = [
    ./databases/index.nix
    ./datax/index.nix
    ./datax-monitor/index.nix  # DX1 agent-execution diagnostic dashboard
    ./estimator/index.nix
    ./firefly/index.nix
    ./paperless/index.nix
    ./website/index.nix
    ./morning-briefing/index.nix
    ./leads/index.nix          # hwc-leads (Phase 0 scaffold, Phase 2 impl)
    ./umami/index.nix          # Umami web analytics (stats.iheartwoodcraft.com)
  ];
}
