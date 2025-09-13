# Infrastructure Mesh Bucket

## Purpose

The **Mesh Bucket** provides **service ↔ service and service ↔ network integration glue**. These modules handle the networking layer that connects services to each other and to external networks without implementing the services themselves.

**Key Principle**: Mesh bucket provides the "network plumbing" between services - container networks, service discovery, load balancing, and inter-service communication.

## Current Modules

### 🐳 Container Networking (`container-networking.nix`)
**Inter-container communication and network integration**

**Status**: Currently a placeholder module designed for future container networking needs.

**Intended Provides:**
- Container-to-container networking setup
- Service mesh integration for containerized services  
- Network overlay configuration
- Inter-service communication routing

**Future Option Pattern:**
```nix
hwc.infrastructure.mesh.containerNetworking = {
  enable = true;
  networks = {
    services = {
      subnet = "10.200.0.0/24";
      services = [ "ollama" "jellyfin" "radarr" "sonarr" ];
    };
    monitoring = {
      subnet = "10.201.0.0/24"; 
      services = [ "prometheus" "grafana" ];
    };
  };
  serviceMesh = {
    enable = true;
    provider = "consul" | "istio" | "linkerd";
  };
};
```

## Future Mesh Capabilities

### Service Discovery Integration
```nix
hwc.infrastructure.mesh.serviceDiscovery = {
  enable = true;
  provider = "consul";
  services = {
    ollama = { port = 11434; health = "/health"; };
    jellyfin = { port = 8096; health = "/System/Ping"; };
  };
};
```

### Load Balancing Glue
```nix  
hwc.infrastructure.mesh.loadBalancing = {
  enable = true;
  frontends = {
    web = {
      domain = "*.local";
      backends = [ "jellyfin" "radarr" "sonarr" ];
      ssl = true;
    };
  };
};
```

### Network Policy Integration
```nix
hwc.infrastructure.mesh.networkPolicies = {
  enable = true;
  policies = {
    media-services = {
      allow = [ "jellyfin" "radarr" "sonarr" ];
      deny = [ "ollama" ];  # AI services isolated from media
    };
  };
};
```

## Mesh Integration Patterns

### Service-to-Service Communication
```nix
# Services domain declares what it needs
hwc.services.radarr = {
  enable = true;
  # Service declares its communication needs
  requires = [ "qbittorrent" "prowlarr" ];
};

# Mesh domain wires them together  
hwc.infrastructure.mesh.containerNetworking = {
  enable = true;
  # Mesh handles the network plumbing
  networks.media-stack = [ "radarr" "qbittorrent" "prowlarr" ];
};
```

### External Network Integration
```nix
# System domain provides network interfaces
networking.interfaces.eth0.ipv4.addresses = [{ address = "192.168.1.100"; prefixLength = 24; }];

# Mesh domain provides service exposure
hwc.infrastructure.mesh.externalAccess = {
  services = {
    jellyfin = { port = 8096; interface = "eth0"; };
    radarr = { port = 7878; interface = "tailscale0"; };  # VPN only
  };
};
```

### Cross-Domain Network Flow
```
Services Domain → declares service communication needs
       ↓
Mesh Domain → provides network integration between services  
       ↓
System Domain → provides underlying network interfaces
       ↓
Security Domain → provides firewall rules and access control
```

## Implementation Strategy

The mesh bucket follows a **gradual implementation approach**:

### Phase 1: Container Networking (Current)
- Placeholder module for future container networking
- Basic network isolation between service groups
- Integration with existing Podman/Docker setup

### Phase 2: Service Discovery  
- Automatic service registration and discovery
- Health checking integration
- DNS-based service resolution

### Phase 3: Load Balancing & Routing
- Reverse proxy integration (Caddy/Traefik)
- SSL termination and certificate management
- Request routing based on service topology

### Phase 4: Service Mesh
- Full service mesh integration (Consul Connect, Istio)  
- mTLS between services
- Advanced traffic management and observability

## Data Flow Examples

### Container Service Communication
```
Service A → requests connection to Service B
       ↓
Mesh networking → routes via container network bridge
       ↓  
Network policy → validates connection is allowed
       ↓
Service B → receives connection on internal network
```

### External Service Access
```
External Client → connects to public IP:port
       ↓
System firewall → allows connection (security domain)
       ↓
Mesh load balancer → routes to healthy service instance
       ↓
Container network → delivers to service container
       ↓
Service → processes request and responds
```

## Validation & Troubleshooting

### Container Network Connectivity
```bash
# Check container networks
podman network ls

# Test inter-container connectivity  
podman exec service-a ping service-b

# Check network policies
iptables -L | grep -i docker
```

### Service Discovery
```bash
# Check service registration
consul members

# Test service resolution
dig @127.0.0.1 -p 8600 jellyfin.service.consul
```

### Load Balancer Status  
```bash
# Check reverse proxy status
systemctl status caddy

# Verify backend health
curl -I http://localhost:8096/health
```

## Anti-Patterns

**❌ Don't implement services in mesh bucket**:
```nix
# Wrong - service implementation belongs in services domain
systemd.services.jellyfin = { ... };
```

**❌ Don't handle authentication/authorization**:
```nix
# Wrong - security policies belong in security domain  
services.oauth2-proxy = { ... };
```

**❌ Don't configure system networking directly**:
```nix
# Wrong - basic networking belongs in system domain
networking.interfaces.eth0 = { ... };
```

**✅ Do provide service interconnection**:
```nix
# Correct - wiring services together
virtualisation.oci-containers.networks = {
  media-stack = { driver = "bridge"; };
};
```

**✅ Do integrate with other domains**:
```nix
# Correct - consuming from hardware for network interfaces
config = lib.mkIf (config.hwc.infrastructure.hardware.networking.interfaces != {}) {
  # Use detected interfaces for service exposure
};
```

**✅ Do provide stable interfaces for services**:
```nix
# Correct - services can declare networking needs
options.hwc.infrastructure.mesh.expose = lib.mkOption {
  type = lib.types.attrsOf serviceExposureType;
  description = "Services to expose on the network";
};
```

## Relationship to Other Domains

### With Services Domain
- **Services declare**: What they need to communicate with
- **Mesh provides**: The network plumbing to make it work

### With Security Domain  
- **Security declares**: Access policies and firewall rules
- **Mesh implements**: Network segmentation to enforce policies

### With System Domain
- **System provides**: Basic networking interfaces and capabilities  
- **Mesh builds**: Service networking on top of system networking

### With Hardware Domain
- **Hardware detects**: Available network interfaces and capabilities
- **Mesh consumes**: Network hardware for service connectivity

---

The mesh bucket is currently in **early development** but designed to provide comprehensive **service networking integration** as the system grows more complex. It maintains clean separation from service implementation while providing the essential network glue services need to communicate effectively.