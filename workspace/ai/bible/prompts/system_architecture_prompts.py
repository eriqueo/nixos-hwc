#!/usr/bin/env python3
"""
System Architecture & Operations Bible - AI Prompting Templates
Specialized prompts for NixOS configuration, security, and operational procedures
"""

SYSTEM_ARCHITECTURE_SYSTEM_PROMPT = """You are a technical documentation expert specializing in NixOS system architecture, security configuration, and operational procedures for complex homelab environments. You have deep expertise in:

- NixOS declarative configuration management with Flakes
- SOPS secrets management with age encryption
- VPN configuration (Tailscale mesh, ProtonVPN via Gluetun)
- Firewall configuration and network security
- System deployment and rollback procedures
- Operational procedures and troubleshooting workflows
- Integration of containerized services with system architecture

Your documentation must provide precise NixOS configurations, secure deployment procedures, and practical operational guidance that maintains system security and reliability."""

SYSTEM_ARCHITECTURE_REWRITE_PROMPT = """
SYSTEM CONTEXT:
- Platform: NixOS with Flakes-based declarative configuration management
- Security: SOPS age-encrypted secrets, Tailscale mesh VPN, ProtonVPN via Gluetun isolation
- Deployment: Git-based configuration with automated rebuilds and rollback capabilities
- Architecture: Multi-tier homeserver with GPU acceleration, containerization, two-tier storage
- Operations: Comprehensive monitoring, automated documentation, structured troubleshooting

ACCUMULATED CHANGES TO INTEGRATE:
{accumulated_changes}

CURRENT BIBLE CONTENT:
{existing_content}

INTEGRATION REQUIREMENTS:
1. PRESERVE EXACTLY:
   - Working NixOS configuration patterns and module structures
   - Functioning SOPS secrets management and encryption keys
   - Secure network configurations (Tailscale, firewall rules, VPN routing)
   - Reliable deployment procedures and rollback mechanisms
   - Tested operational procedures and emergency recovery workflows

2. UPDATE INTELLIGENTLY:
   - Add new NixOS configuration patterns or module improvements
   - Integrate security enhancements or policy updates
   - Update deployment procedures based on operational experience
   - Add new troubleshooting procedures for recently encountered issues
   - Update architectural documentation to reflect system evolution

3. MAINTAIN TECHNICAL ACCURACY:
   - NixOS configurations must be syntactically correct and follow best practices
   - Security configurations must comply with current security standards
   - Deployment procedures must work with the actual system setup and permissions
   - Network configurations must be compatible with existing infrastructure
   - Operational procedures must be tested and practically achievable

4. CROSS-BIBLE CONSISTENCY:
   - Hardware specifications must match Hardware & GPU Bible exactly
   - Container configurations must align with Container Services Bible
   - Storage configurations must match Storage & Data Bible specifications
   - Monitoring integration must work with Monitoring Bible configurations
   - AI system integration must support AI Documentation Bible requirements

CRITICAL TECHNICAL CONSTRAINTS:
- All NixOS configurations must be declarative and reproducible
- SOPS secrets must never be exposed in plaintext in documentation
- VPN configurations must properly isolate download traffic without affecting media serving
- Firewall rules must balance security with service accessibility
- Deployment procedures must support both testing and production changes safely
- Rollback procedures must be reliable and not require external dependencies

Generate an updated System Architecture & Operations Bible that seamlessly integrates the accumulated changes while preserving all working system configurations and maintaining security and operational reliability.

FORMATTING REQUIREMENTS:
- Maintain existing section structure with clear architectural organization
- Preserve all working NixOS configurations and deployment procedures exactly
- Use consistent terminology for system components and operational concepts
- Include system architecture diagrams and network topology where relevant
- Cross-reference other bibles without duplicating their architecture-specific content
"""

SYSTEM_ARCHITECTURE_VALIDATION_PROMPT = """
Review this updated System Architecture & Operations Bible for technical accuracy:

{updated_content}

VALIDATION CHECKLIST:
1. NixOS Configuration:
   □ All Nix expressions are syntactically correct and follow best practices
   □ Module imports and dependencies are properly structured
   □ Configuration patterns are reproducible and maintainable
   □ Flake configurations are valid and properly pinned

2. Security Configuration:
   □ SOPS secrets management follows security best practices
   □ VPN configurations properly isolate traffic as intended
   □ Firewall rules are comprehensive and follow least-privilege principles
   □ Network segmentation is properly implemented and documented

3. Deployment Procedures:
   □ Deployment steps are clearly defined and tested
   □ Rollback procedures are reliable and cover failure scenarios
   □ Testing procedures validate changes before production deployment
   □ Git workflow integrates properly with NixOS rebuild procedures

4. Operational Procedures:
   □ Troubleshooting procedures are comprehensive and actionable
   □ Emergency recovery procedures are tested and reliable
   □ Maintenance procedures don't compromise system security
   □ Documentation procedures support system evolution

5. Cross-Bible Integration:
   □ Hardware specifications match other bibles exactly
   □ Service integration points are correctly documented
   □ Security policies support all system components
   □ Operational procedures cover all system aspects comprehensively

Return a JSON assessment:
{
  "validation_passed": boolean,
  "nixos_config_accuracy": 0-100,
  "security_config_accuracy": 0-100,
  "deployment_procedure_accuracy": 0-100,
  "operational_procedure_completeness": 0-100,
  "critical_issues": ["list of any critical system configuration errors"],
  "security_concerns": ["list of potential security issues"],
  "cross_reference_accuracy": 0-100
}
"""

SYSTEM_ARCHITECTURE_SECURITY_UPDATE_PROMPT = """
Security configurations or policies have been updated:

SECURITY UPDATES:
{security_info}

UPDATE REQUIREMENTS:
1. Update security configurations with new policies or requirements
2. Revise SOPS secrets management procedures if encryption has changed
3. Update VPN configurations or access control policies
4. Add new firewall rules or network security measures
5. Update security monitoring and auditing procedures
6. Revise security incident response procedures

Ensure all security updates maintain or improve system security posture without disrupting operations.
"""

SYSTEM_ARCHITECTURE_DEPLOYMENT_UPDATE_PROMPT = """
Deployment procedures or automation have been improved:

DEPLOYMENT UPDATES:
{deployment_info}

UPDATE REQUIREMENTS:
1. Update NixOS deployment procedures with new automation or techniques
2. Revise testing procedures for configuration changes
3. Update rollback procedures for new deployment mechanisms
4. Add new validation steps for deployment safety
5. Update deployment monitoring and success verification
6. Revise troubleshooting for new deployment failure modes

Ensure deployment updates improve reliability and safety without adding unnecessary complexity.
"""

SYSTEM_ARCHITECTURE_OPERATIONAL_UPDATE_PROMPT = """
Operational procedures or troubleshooting techniques have been enhanced:

OPERATIONAL UPDATES:
{operational_info}

UPDATE REQUIREMENTS:
1. Update operational procedures with new techniques or tools
2. Add new troubleshooting procedures for recently encountered issues
3. Update maintenance schedules or procedures based on operational experience
4. Add new monitoring or diagnostic capabilities
5. Update emergency response procedures for new scenarios
6. Revise documentation maintenance procedures

Ensure operational updates improve system reliability and maintainability.
"""

SYSTEM_ARCHITECTURE_INTEGRATION_UPDATE_PROMPT = """
System architecture or component integration has evolved:

ARCHITECTURE UPDATES:
{architecture_info}

UPDATE REQUIREMENTS:
1. Update architectural diagrams and system relationship documentation
2. Revise component integration procedures and dependencies
3. Update system capacity planning and scaling considerations
4. Add new architectural decision documentation and rationale
5. Update system evolution planning and roadmap
6. Revise architectural troubleshooting and validation procedures

Ensure architectural updates accurately reflect system evolution while maintaining consistency.
"""

SYSTEM_ARCHITECTURE_NIXOS_UPDATE_PROMPT = """
NixOS configuration patterns or system management techniques have been updated:

NIXOS UPDATES:
{nixos_info}

UPDATE REQUIREMENTS:
1. Update NixOS configuration examples and patterns
2. Add new module configurations or system management techniques
3. Update Flake management and dependency handling procedures
4. Add new NixOS-specific troubleshooting and diagnostic techniques
5. Update system upgrade and maintenance procedures
6. Revise NixOS best practices and optimization recommendations

Ensure all NixOS updates follow declarative principles and improve system maintainability.
"""

# Export prompt templates
PROMPT_TEMPLATES = {
    "system_prompt": SYSTEM_ARCHITECTURE_SYSTEM_PROMPT,
    "rewrite_prompt": SYSTEM_ARCHITECTURE_REWRITE_PROMPT,
    "validation_prompt": SYSTEM_ARCHITECTURE_VALIDATION_PROMPT,
    "security_update": SYSTEM_ARCHITECTURE_SECURITY_UPDATE_PROMPT,
    "deployment_update": SYSTEM_ARCHITECTURE_DEPLOYMENT_UPDATE_PROMPT,
    "operational_update": SYSTEM_ARCHITECTURE_OPERATIONAL_UPDATE_PROMPT,
    "integration_update": SYSTEM_ARCHITECTURE_INTEGRATION_UPDATE_PROMPT,
    "nixos_update": SYSTEM_ARCHITECTURE_NIXOS_UPDATE_PROMPT
}