#!/usr/bin/env python3
"""
AI Documentation & Automation Bible - AI Prompting Templates
Specialized prompts for AI documentation system using local Ollama
"""

AI_DOCUMENTATION_SYSTEM_PROMPT = """You are a technical documentation expert specializing in AI-powered documentation systems using local Ollama models for automated analysis and generation. You have deep expertise in:

- Local Ollama deployment and model management (llama3.2:3b)
- AI documentation workflows with git integration and post-build triggers
- Prompt engineering and AI model optimization for technical writing
- Automated documentation generation and change analysis
- Error handling and recovery for AI documentation systems
- Integration with NixOS rebuild workflows and systemd services

Your documentation must provide precise AI model configurations, reliable automation workflows, and practical troubleshooting that ensures consistent documentation generation without system disruption."""

AI_DOCUMENTATION_REWRITE_PROMPT = """
SYSTEM CONTEXT:
- AI Platform: Local Ollama with llama3.2:3b model (4K context window)
- Integration: Post-successful-build triggers with change accumulation and threshold detection
- Workflow: Git changes → Change analysis → Threshold detection → Bible-specific AI updates
- Error Handling: Robust error recovery, process locking, timeout protection
- Performance: Optimized for local inference with memory and processing constraints

ACCUMULATED CHANGES TO INTEGRATE:
{accumulated_changes}

CURRENT BIBLE CONTENT:
{existing_content}

INTEGRATION REQUIREMENTS:
1. PRESERVE EXACTLY:
   - Working Ollama API configurations and model endpoints
   - Functioning automation scripts and trigger mechanisms
   - Effective prompt templates and AI processing logic
   - Reliable error handling and recovery procedures
   - Process locking and timeout protection that prevents system issues

2. UPDATE INTELLIGENTLY:
   - Add improvements to AI model performance or prompt engineering
   - Integrate new automation features or workflow optimizations
   - Update error handling based on newly encountered failure modes
   - Add new documentation generation capabilities or techniques
   - Update integration points with other system components

3. MAINTAIN TECHNICAL ACCURACY:
   - Ollama API calls must match actual model capabilities and endpoints
   - Workflow scripts must be executable and compatible with the system
   - Prompt engineering must be effective for llama3.2:3b model limitations
   - Error handling must cover realistic failure scenarios
   - Integration points must match actual system architecture and timing

4. CROSS-BIBLE CONSISTENCY:
   - AI system integration must align with System Architecture Bible procedures
   - Model resource usage must respect system resource constraints
   - Documentation generation must support all bible types consistently
   - Error notification must integrate with system monitoring and alerting

CRITICAL TECHNICAL CONSTRAINTS:
- llama3.2:3b has 4K context window - prompts must be optimized for this limitation
- Local inference requires careful memory management to avoid system impact
- AI processing must not block system rebuilds or normal operations
- Error recovery must be automatic and not require manual intervention
- Process locking must prevent concurrent AI operations that could cause conflicts
- Timeout protection must prevent runaway AI processes from impacting system

Generate an updated AI Documentation & Automation Bible that seamlessly integrates the accumulated changes while preserving all working AI system configurations and automation workflows.

FORMATTING REQUIREMENTS:
- Maintain existing section structure with clear AI workflow organization
- Preserve all working automation scripts and configuration examples exactly
- Use consistent terminology for AI concepts and technical components
- Include AI architecture diagrams and workflow visualizations where relevant
- Cross-reference other bibles without duplicating their AI-specific integrations
"""

AI_DOCUMENTATION_VALIDATION_PROMPT = """
Review this updated AI Documentation & Automation Bible for technical accuracy:

{updated_content}

VALIDATION CHECKLIST:
1. Ollama Configuration:
   □ API endpoints and model specifications are correct for actual deployment
   □ Model parameters (temperature, context window) are appropriate for llama3.2:3b
   □ Memory and resource constraints are respected
   □ Model availability and health check procedures are functional

2. Automation Workflows:
   □ All automation scripts are syntactically correct and executable
   □ Git integration works with actual repository structure and permissions
   □ Trigger mechanisms properly integrate with NixOS rebuild workflow
   □ Process coordination prevents conflicts and race conditions

3. Prompt Engineering:
   □ Prompt templates are optimized for llama3.2:3b capabilities and limitations
   □ Context window usage is efficient and stays within 4K token limit
   □ Prompt engineering techniques produce consistent, high-quality outputs
   □ Bible-specific prompts are technically accurate for their domains

4. Error Handling:
   □ Error detection covers realistic AI system failure modes
   □ Recovery procedures are automatic and don't require manual intervention
   □ Timeout protection prevents runaway processes
   □ Process locking prevents concurrent operations and conflicts

5. System Integration:
   □ AI system integration doesn't disrupt normal system operations
   □ Resource usage is monitored and constrained appropriately
   □ Error notifications integrate with system monitoring
   □ Documentation output is properly validated before deployment

Return a JSON assessment:
{
  "validation_passed": boolean,
  "ollama_config_accuracy": 0-100,
  "automation_workflow_accuracy": 0-100,
  "prompt_engineering_quality": 0-100,
  "error_handling_completeness": 0-100,
  "critical_issues": ["list of any critical AI system configuration errors"],
  "performance_concerns": ["list of potential performance or resource issues"],
  "integration_accuracy": 0-100
}
"""

AI_DOCUMENTATION_PROMPT_OPTIMIZATION_PROMPT = """
AI prompt engineering or model optimization techniques have been improved:

OPTIMIZATION DETAILS:
{optimization_info}

UPDATE REQUIREMENTS:
1. Update prompt templates with improved engineering techniques
2. Optimize context window usage for better information density
3. Add new prompt validation and testing procedures
4. Update model parameter tuning for better consistency
5. Add new prompt debugging and troubleshooting techniques
6. Update documentation of prompt engineering best practices

Ensure all prompt optimizations improve output quality without exceeding model limitations.
"""

AI_DOCUMENTATION_WORKFLOW_IMPROVEMENT_PROMPT = """
AI documentation workflow automation has been improved or extended:

WORKFLOW IMPROVEMENTS:
{workflow_info}

UPDATE REQUIREMENTS:
1. Update automation scripts with new workflow capabilities
2. Add new integration points with system components
3. Update error handling for new workflow steps
4. Add new monitoring and logging for workflow stages
5. Update testing and validation procedures for new workflows
6. Revise troubleshooting procedures for new automation features

Ensure workflow improvements enhance reliability without introducing new failure modes.
"""

AI_DOCUMENTATION_MODEL_UPDATE_PROMPT = """
The AI model or Ollama configuration has been updated:

MODEL UPDATES:
{model_info}

UPDATE REQUIREMENTS:
1. Update model specifications and capability descriptions
2. Revise prompt templates for new model capabilities or limitations
3. Update performance characteristics and resource usage documentation
4. Add new model-specific troubleshooting procedures
5. Update integration testing procedures for new model behavior
6. Revise optimization recommendations for new model characteristics

Ensure all model updates maintain compatibility with existing workflows while leveraging new capabilities.
"""

AI_DOCUMENTATION_ERROR_HANDLING_PROMPT = """
Error handling and recovery procedures have been enhanced:

ERROR HANDLING UPDATES:
{error_info}

UPDATE REQUIREMENTS:
1. Update error detection and classification procedures
2. Add new automatic recovery mechanisms
3. Update logging and diagnostic procedures for new error types
4. Add new monitoring for error rates and recovery success
5. Update troubleshooting procedures for new error scenarios
6. Revise notification and alerting for AI system issues

Ensure enhanced error handling improves system reliability without adding unnecessary complexity.
"""

AI_DOCUMENTATION_INTEGRATION_UPDATE_PROMPT = """
Integration with other system components has been updated or expanded:

INTEGRATION UPDATES:
{integration_info}

UPDATE REQUIREMENTS:
1. Update integration procedures with other system components
2. Add new dependency management for AI system operations
3. Update resource coordination with other system services
4. Add new monitoring of integration points and data flows
5. Update testing procedures for cross-component integration
6. Revise troubleshooting for integration-related issues

Ensure integration updates improve system cohesion without creating new dependencies or failure points.
"""

# Export prompt templates
PROMPT_TEMPLATES = {
    "system_prompt": AI_DOCUMENTATION_SYSTEM_PROMPT,
    "rewrite_prompt": AI_DOCUMENTATION_REWRITE_PROMPT,
    "validation_prompt": AI_DOCUMENTATION_VALIDATION_PROMPT,
    "prompt_optimization": AI_DOCUMENTATION_PROMPT_OPTIMIZATION_PROMPT,
    "workflow_improvement": AI_DOCUMENTATION_WORKFLOW_IMPROVEMENT_PROMPT,
    "model_update": AI_DOCUMENTATION_MODEL_UPDATE_PROMPT,
    "error_handling": AI_DOCUMENTATION_ERROR_HANDLING_PROMPT,
    "integration_update": AI_DOCUMENTATION_INTEGRATION_UPDATE_PROMPT
}