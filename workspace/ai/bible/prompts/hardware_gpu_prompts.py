#!/usr/bin/env python3
"""
Hardware & GPU Bible - AI Prompting Templates
Specialized prompts for NVIDIA Quadro P1000 GPU acceleration documentation
"""

HARDWARE_GPU_SYSTEM_PROMPT = """You are a technical documentation expert specializing in NVIDIA GPU acceleration for containerized services on NixOS homeserver systems. You have deep expertise in:

- NVIDIA Quadro P1000 (Pascal architecture, 4GB VRAM, Compute Capability 6.1)
- Container GPU device access patterns for Podman
- Multi-service GPU sharing and resource management
- Pascal architecture limitations and optimizations
- Hardware transcoding, AI inference, and GPU compute workloads

Your documentation must be technically precise, account for hardware limitations, and provide practical configuration examples that work on the actual system."""

HARDWARE_GPU_REWRITE_PROMPT = """
SYSTEM CONTEXT:
- Hardware: NVIDIA Quadro P1000 (Pascal architecture, 4GB VRAM)
- Container Runtime: Podman with systemd integration
- GPU Services: Frigate (TensorRT), Jellyfin (NVENC/NVDEC), Immich (AI/ML), Ollama (CUDA), *arr apps (thumbnails)
- Critical Constraint: Pascal requires USE_FP16=false for TensorRT model generation

ACCUMULATED CHANGES TO INTEGRATE:
{accumulated_changes}

CURRENT BIBLE CONTENT:
{existing_content}

INTEGRATION REQUIREMENTS:
1. PRESERVE EXACTLY:
   - GPU device access patterns (/dev/nvidia*, /dev/dri, etc.)
   - Pascal architecture limitations (FP16 disabled, 4GB VRAM constraints)
   - Container GPU environment variables (NVIDIA_VISIBLE_DEVICES, etc.)
   - Service-specific GPU configurations that are currently working

2. UPDATE INTELLIGENTLY:
   - Add new GPU-accelerated services to utilization matrix
   - Integrate new performance optimizations or driver updates
   - Update troubleshooting based on new issues resolved
   - Add new GPU monitoring or diagnostic procedures

3. MAINTAIN TECHNICAL ACCURACY:
   - All GPU device paths must match actual hardware configuration
   - Container GPU options must be syntactically correct for Podman
   - Memory recommendations must respect 4GB VRAM limit
   - Performance benchmarks must be realistic for Pascal architecture

4. CROSS-BIBLE CONSISTENCY:
   - GPU configurations referenced by Container Services Bible must match exactly
   - Performance metrics must align with Monitoring Bible expectations
   - Hardware requirements must match System Architecture Bible specifications

CRITICAL TECHNICAL CONSTRAINTS:
- Pascal Compute Capability 6.1 does NOT support all modern GPU features
- TensorRT models MUST use USE_FP16=false for Pascal architecture
- 4GB VRAM requires careful memory allocation between services
- NVENC supports H.264/H.265 but limited AV1 capability
- GPU sharing requires proper device access and environment variable configuration

Generate an updated Hardware & GPU Acceleration Bible that seamlessly integrates the accumulated changes while preserving all critical technical configurations and maintaining accuracy for the NVIDIA Quadro P1000 Pascal architecture.

FORMATTING REQUIREMENTS:
- Maintain existing section structure and hierarchy
- Preserve all code blocks, configuration examples, and command syntax exactly
- Use consistent technical terminology throughout
- Include specific hardware details (Pascal, 4GB VRAM, Compute 6.1) in relevant sections
- Cross-reference other bibles appropriately without duplicating their content
"""

HARDWARE_GPU_VALIDATION_PROMPT = """
Review this updated Hardware & GPU Bible for technical accuracy and completeness:

{updated_content}

VALIDATION CHECKLIST:
1. GPU Device Access:
   □ All /dev/nvidia* device paths are correct for actual hardware
   □ Container GPU options use valid Podman syntax
   □ Environment variables match NVIDIA container runtime requirements

2. Pascal Architecture Compliance:
   □ TensorRT configurations specify USE_FP16=false
   □ Memory recommendations respect 4GB VRAM limit
   □ Compute Capability 6.1 limitations are documented
   □ Codec support accurately reflects Pascal capabilities

3. Service Integration:
   □ All GPU-accelerated services are documented in utilization matrix
   □ Configuration examples work with actual service implementations
   □ Performance expectations are realistic for Pascal hardware

4. Cross-Bible References:
   □ Container service GPU configurations match Container Services Bible
   □ Monitoring metrics align with Monitoring Bible expectations
   □ System requirements match Architecture Bible specifications

5. Technical Accuracy:
   □ All commands and configurations are syntactically correct
   □ File paths and service names match actual system implementation
   □ Performance benchmarks are achievable on Pascal hardware

Return a JSON assessment:
{
  "validation_passed": boolean,
  "technical_accuracy_score": 0-100,
  "critical_issues": ["list of any critical technical errors"],
  "recommendations": ["list of improvement suggestions"],
  "cross_reference_accuracy": 0-100
}
"""

HARDWARE_GPU_CONFLICT_RESOLUTION_PROMPT = """
Resolve conflicts between existing content and new changes for Hardware & GPU Bible:

EXISTING CONTENT SECTION:
{existing_section}

CONFLICTING NEW INFORMATION:
{conflicting_changes}

RESOLUTION STRATEGY:
1. Preserve any working configurations that are currently functional
2. Update outdated information with verified new data
3. Maintain Pascal architecture constraints and limitations
4. Ensure all technical specifications remain accurate

For each conflict, determine:
- Which information is more accurate/current
- Whether both pieces of information can coexist
- How to integrate new information without breaking existing functionality
- What cross-bible references need updating

Return the resolved content section with clear indication of what was changed and why.
"""

# Additional specialized prompts for specific scenarios

HARDWARE_GPU_NEW_SERVICE_PROMPT = """
A new GPU-accelerated service has been added to the system. Update the Hardware & GPU Bible to include:

NEW SERVICE DETAILS:
{new_service_info}

UPDATE REQUIREMENTS:
1. Add service to GPU Utilization Matrix with appropriate details
2. Document any specific GPU configuration requirements
3. Update resource allocation recommendations considering 4GB VRAM limit
4. Add troubleshooting section if service has Pascal-specific issues
5. Update performance monitoring recommendations

Ensure the new service integration doesn't conflict with existing GPU-accelerated services and maintains technical accuracy for Pascal architecture.
"""

HARDWARE_GPU_PERFORMANCE_UPDATE_PROMPT = """
New performance data or optimization techniques have been discovered. Update the Hardware & GPU Bible:

PERFORMANCE DATA:
{performance_updates}

INTEGRATION REQUIREMENTS:
1. Update performance benchmarks with verified data
2. Add new optimization techniques that work on Pascal architecture
3. Update resource allocation recommendations based on new performance data
4. Revise troubleshooting sections with new diagnostic techniques
5. Update monitoring recommendations to track new performance metrics

Ensure all performance recommendations are achievable on NVIDIA Quadro P1000 hardware and don't exceed 4GB VRAM limitations.
"""

# Export prompt templates for use by the rewriter engine
PROMPT_TEMPLATES = {
    "system_prompt": HARDWARE_GPU_SYSTEM_PROMPT,
    "rewrite_prompt": HARDWARE_GPU_REWRITE_PROMPT,
    "validation_prompt": HARDWARE_GPU_VALIDATION_PROMPT,
    "conflict_resolution": HARDWARE_GPU_CONFLICT_RESOLUTION_PROMPT,
    "new_service": HARDWARE_GPU_NEW_SERVICE_PROMPT,
    "performance_update": HARDWARE_GPU_PERFORMANCE_UPDATE_PROMPT
}