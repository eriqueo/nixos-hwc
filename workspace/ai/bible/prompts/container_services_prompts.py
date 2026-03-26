#!/usr/bin/env python3
"""
Container Services & Orchestration Bible - AI Prompting Templates
Specialized prompts for Podman containerized services on NixOS
"""

CONTAINER_SERVICES_SYSTEM_PROMPT = """You are a technical documentation expert specializing in containerized service orchestration using Podman and systemd on NixOS homeserver systems. You have deep expertise in:

- Podman container runtime with systemd integration
- Custom container networking and inter-service communication
- Media pipeline services (*arr applications, download clients)
- Surveillance systems (Frigate object detection, Home Assistant)
- Business intelligence services (dashboards, APIs, databases)
- Resource management and GPU sharing between containers
- VPN integration via Gluetun for security isolation

Your documentation must provide precise container configurations, valid systemd service definitions, and practical networking setups that work reliably in production."""

CONTAINER_SERVICES_REWRITE_PROMPT = """
SYSTEM CONTEXT:
- Container Runtime: Podman with systemd service integration
- Network Architecture: Custom media-network with service isolation
- Service Categories: Media (*arr apps), Surveillance (Frigate), Business (dashboards), AI (Ollama)
- VPN Integration: ProtonVPN via Gluetun container for download clients
- GPU Sharing: Multiple services access NVIDIA Quadro P1000 through device passthrough

ACCUMULATED CHANGES TO INTEGRATE:
{accumulated_changes}

CURRENT BIBLE CONTENT:
{existing_content}

INTEGRATION REQUIREMENTS:
1. PRESERVE EXACTLY:
   - Container service names and systemd unit names
   - Network configurations and port mappings
   - GPU device access patterns for GPU-enabled services
   - VPN routing configurations through Gluetun
   - Resource limits and environment variables that are working

2. UPDATE INTELLIGENTLY:
   - Add new containerized services with proper configuration
   - Update service dependencies and startup sequences
   - Integrate new networking or security configurations
   - Add new optimization settings or resource management improvements
   - Update troubleshooting based on resolved service issues

3. MAINTAIN TECHNICAL ACCURACY:
   - Container names must match actual systemd service names (podman-servicename.service)
   - Network configurations must be valid for Podman networking
   - Port mappings must avoid conflicts and match firewall rules
   - Resource limits must be appropriate for system capabilities
   - Environment variables must match actual service requirements

4. CROSS-BIBLE CONSISTENCY:
   - GPU configurations must match Hardware & GPU Bible exactly
   - Storage mount paths must match Storage & Data Bible specifications
   - Monitoring configurations must align with Monitoring Bible expectations
   - Network security must comply with System Architecture Bible requirements

CRITICAL TECHNICAL CONSTRAINTS:
- All containers use Podman (NOT Docker) - syntax and options must be Podman-compatible
- systemd integration via podman-servicename.service pattern
- Custom media-network requires proper container network attachment
- VPN routing only affects download clients (qBittorrent, SABnzbd) not media serving
- GPU access requires specific device mappings and environment variables
- Service startup order matters for dependencies (network, storage, VPN)

Generate an updated Container Services & Orchestration Bible that seamlessly integrates the accumulated changes while preserving all working service configurations and maintaining technical accuracy for Podman and systemd integration.

FORMATTING REQUIREMENTS:
- Maintain existing section structure with clear service categorization
- Preserve all systemd service definitions and Podman run commands exactly
- Use consistent service naming conventions throughout
- Include network topology diagrams where relevant
- Cross-reference other bibles without duplicating their detailed content
"""

CONTAINER_SERVICES_VALIDATION_PROMPT = """
Review this updated Container Services & Orchestration Bible for technical accuracy:

{updated_content}

VALIDATION CHECKLIST:
1. Service Configuration:
   □ All container names match systemd service patterns (podman-*.service)
   □ Podman commands use correct syntax (not Docker syntax)
   □ Resource limits are appropriate for system capabilities
   □ Environment variables match actual service requirements

2. Network Configuration:
   □ Network names and configurations are valid for Podman
   □ Port mappings avoid conflicts and match firewall rules
   □ VPN routing correctly isolates download clients only
   □ Inter-service communication works within media-network

3. GPU Integration:
   □ GPU device access patterns match Hardware & GPU Bible
   □ Only appropriate services have GPU access configured
   □ GPU environment variables are correct for Pascal architecture
   □ Resource sharing doesn't exceed GPU memory limits

4. Storage Integration:
   □ Mount paths match Storage & Data Bible specifications
   □ Hot and cold storage tiers are properly configured
   □ Data flow between services follows documented pipeline

5. Service Dependencies:
   □ Startup order respects service dependencies
   □ VPN services start before download clients
   □ Network creation precedes service container startup
   □ Storage mounts are available before dependent services

Return a JSON assessment:
{
  "validation_passed": boolean,
  "service_config_accuracy": 0-100,
  "network_config_accuracy": 0-100,
  "critical_issues": ["list of any critical configuration errors"],
  "dependency_issues": ["list of service dependency problems"],
  "cross_reference_accuracy": 0-100
}
"""

CONTAINER_SERVICES_NEW_SERVICE_PROMPT = """
A new containerized service is being added to the system. Update the Container Services Bible:

NEW SERVICE DETAILS:
{new_service_info}

INTEGRATION REQUIREMENTS:
1. Create proper systemd service definition following naming conventions
2. Configure container networking (media-network attachment, port mappings)
3. Set up appropriate resource limits and environment variables
4. Configure storage mounts if the service needs data persistence
5. Add GPU access if the service requires hardware acceleration
6. Document service dependencies and startup order
7. Add monitoring endpoints if the service exposes metrics
8. Create troubleshooting section for common service issues

TECHNICAL CONSTRAINTS:
- Use Podman syntax (not Docker)
- Follow systemd service naming: podman-servicename.service
- Ensure network configuration doesn't conflict with existing services
- GPU access only if genuinely needed and configured properly
- VPN routing only for download-related services

Generate the new service configuration and integrate it properly into the existing bible structure.
"""

CONTAINER_SERVICES_OPTIMIZATION_PROMPT = """
New optimization techniques or performance improvements have been implemented. Update the Container Services Bible:

OPTIMIZATION DETAILS:
{optimization_info}

UPDATE REQUIREMENTS:
1. Update resource limits based on new performance data
2. Add new configuration parameters that improve performance
3. Update network optimizations or security improvements
4. Revise service startup procedures for better reliability
5. Add new monitoring or health check configurations
6. Update troubleshooting with new diagnostic techniques

Ensure all optimizations are compatible with existing service configurations and don't introduce stability issues.
"""

CONTAINER_SERVICES_CONFLICT_RESOLUTION_PROMPT = """
Resolve configuration conflicts between existing and new container service information:

EXISTING SERVICE CONFIG:
{existing_config}

CONFLICTING NEW CONFIG:
{conflicting_config}

RESOLUTION STRATEGY:
1. Preserve working configurations that are currently stable
2. Update outdated configurations with verified improvements
3. Ensure new configurations don't break service dependencies
4. Maintain compatibility with existing network and storage configurations

Determine the best configuration that integrates both old and new information while maintaining service reliability.
"""

# Export prompt templates
PROMPT_TEMPLATES = {
    "system_prompt": CONTAINER_SERVICES_SYSTEM_PROMPT,
    "rewrite_prompt": CONTAINER_SERVICES_REWRITE_PROMPT,
    "validation_prompt": CONTAINER_SERVICES_VALIDATION_PROMPT,
    "new_service": CONTAINER_SERVICES_NEW_SERVICE_PROMPT,
    "optimization": CONTAINER_SERVICES_OPTIMIZATION_PROMPT,
    "conflict_resolution": CONTAINER_SERVICES_CONFLICT_RESOLUTION_PROMPT
}