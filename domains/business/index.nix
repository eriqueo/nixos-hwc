# domains/business/index.nix
#
# Business domain — Heartwood Craft remodeling business infrastructure
# NAMESPACE: hwc.business.*
#
# Modules:
#   - estimator      — Estimate Assembler PWA (Vite/React)
#   - firefly        — Firefly III + Pico (personal finance, containerized)
#   - paperless      — Paperless-ngx (document management, containerized)
#   - website         — heartwoodcraft.me (CMS + 11ty site content)
#
# NOTE: Heartwood MCP (JT tools) moved to domains/system/mcp/parts/jt.nix (hwc.system.mcp.jt.*)

{ config, lib, ... }:
{
  imports = [
    ./estimator/index.nix
    ./firefly/index.nix
    ./paperless/index.nix
    ./website/index.nix
    ./morning-briefing/index.nix
  ];
}
