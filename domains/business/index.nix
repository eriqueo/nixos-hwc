# domains/business/index.nix
#
# Business domain — Heartwood Craft remodeling business infrastructure
# NAMESPACE: hwc.business.*
#
# Modules:
#   - mcp            — Heartwood MCP Server (JobTread PAVE interface)
#   - estimator      — Estimate Assembler PWA (Vite/React)
#   - firefly        — Firefly III + Pico (personal finance, containerized)
#   - paperless      — Paperless-ngx (document management, containerized)
#   - heartwood-cms  — CMS Dashboard for heartwoodcraft.me (Node.js)

{ config, lib, ... }:
{
  imports = [
    ./mcp/index.nix
    ./estimator/index.nix
    ./firefly/index.nix
    ./paperless/index.nix
    ./heartwood-cms/index.nix
  ];
}
