# Security Configuration Guide

## Firewall Rules
- Strict mode: Default deny all
- Service-based allowlisting
- Rate limiting on SSH

## Secret Management
```nix
hwc.secrets = {
  enable = true;
  provider = "sops";
  sops.secrets = {
    "api_key" = {
      owner = "myservice";
      group = "myservice";
    };
  };
};
VPN Configuration

Tailscale for zero-trust networking
WireGuard for site-to-site
Split tunneling support

Container Security

Isolated networks per service group
No privileged containers by default
Resource limits enforced

Audit Trail

All commands logged
File access monitoring
Network connection tracking
