#!/usr/bin/env python3
"""
Monitoring & Observability Bible - AI Prompting Templates
Specialized prompts for Prometheus, Grafana, and comprehensive system monitoring
"""

MONITORING_OBSERVABILITY_SYSTEM_PROMPT = """You are a technical documentation expert specializing in comprehensive system monitoring using Prometheus, Grafana, and custom monitoring solutions for complex homeserver environments. You have deep expertise in:

- Prometheus metrics collection with custom exporters
- Grafana dashboard design and automated provisioning
- Alert management with webhook-based notification systems
- System diagnostics and performance troubleshooting
- GPU monitoring for NVIDIA hardware
- Container monitoring with cAdvisor integration
- Storage monitoring and capacity planning
- Custom monitoring solutions for specialized services

Your documentation must provide precise metric definitions, working dashboard configurations, and practical alerting that provides actionable insights without false positives."""

MONITORING_OBSERVABILITY_REWRITE_PROMPT = """
SYSTEM CONTEXT:
- Metrics Platform: Prometheus with Node Exporter, cAdvisor, GPU Exporter, custom exporters
- Visualization: Grafana with automated dashboard provisioning
- Alerting: Alert management with webhook notifications and severity-based routing
- Monitoring Scope: System resources, containers, GPU utilization, storage, application-specific metrics
- Integration: Monitoring endpoints for all containerized services and system components

ACCUMULATED CHANGES TO INTEGRATE:
{accumulated_changes}

CURRENT BIBLE CONTENT:
{existing_content}

INTEGRATION REQUIREMENTS:
1. PRESERVE EXACTLY:
   - Working Prometheus metric names and collection configurations
   - Grafana dashboard JSON structures and panel configurations
   - Alert rule definitions and notification webhook configurations
   - Diagnostic procedures and troubleshooting workflows that are effective
   - Performance baseline metrics and capacity planning calculations

2. UPDATE INTELLIGENTLY:
   - Add new metrics from newly deployed services or system components
   - Integrate new dashboard panels or visualization improvements
   - Update alert thresholds based on operational experience
   - Add new diagnostic procedures for recently encountered issues
   - Update performance targets based on system evolution

3. MAINTAIN TECHNICAL ACCURACY:
   - Metric names must match actual Prometheus exports from configured exporters
   - Grafana queries must be syntactically correct and reference existing data sources
   - Alert thresholds must be appropriate for actual system capabilities and behavior
   - Dashboard panels must reference metrics that actually exist
   - Diagnostic commands must work on the actual system configuration

4. CROSS-BIBLE CONSISTENCY:
   - GPU metrics must align with Hardware & GPU Bible hardware specifications
   - Container metrics must match Container Services Bible service definitions
   - Storage metrics must correspond to Storage & Data Bible architecture
   - System metrics must reflect System Architecture Bible configuration

CRITICAL TECHNICAL CONSTRAINTS:
- Prometheus metric names follow standard naming conventions (service_metric_unit pattern)
- Grafana dashboards use correct query syntax for Prometheus data source
- Alert rules must avoid false positives while catching actual issues
- GPU monitoring must account for Pascal architecture and 4GB VRAM limitations
- Container monitoring must work with Podman (not Docker) container runtime
- Storage monitoring must distinguish between hot SSD and cold HDD performance characteristics
- Custom exporters must be reliable and not impact system performance

Generate an updated Monitoring & Observability Bible that seamlessly integrates the accumulated changes while preserving all working monitoring configurations and maintaining technical accuracy for the monitoring stack.

FORMATTING REQUIREMENTS:
- Maintain existing section structure with clear metric category organization
- Preserve all working dashboard JSON and Prometheus configurations exactly
- Use consistent metric naming and labeling conventions throughout
- Include monitoring architecture diagrams where relevant
- Cross-reference other bibles without duplicating their monitoring-specific content
"""

MONITORING_OBSERVABILITY_VALIDATION_PROMPT = """
Review this updated Monitoring & Observability Bible for technical accuracy:

{updated_content}

VALIDATION CHECKLIST:
1. Prometheus Configuration:
   □ All metric names follow standard Prometheus naming conventions
   □ Scrape configurations reference actual service endpoints
   □ Recording rules are syntactically correct and mathematically sound
   □ Retention policies are appropriate for storage capacity

2. Grafana Dashboards:
   □ All dashboard JSON is syntactically valid
   □ Panel queries reference metrics that actually exist
   □ Visualization types are appropriate for the data being displayed
   □ Dashboard variables and templating work correctly

3. Alert Rules:
   □ Alert expressions are syntactically correct for Prometheus
   □ Alert thresholds are reasonable for actual system behavior
   □ Alert labels and annotations provide actionable information
   □ Notification routing is properly configured

4. Monitoring Coverage:
   □ All major system components have appropriate monitoring
   □ Critical services have health checks and performance metrics
   □ Resource utilization monitoring covers CPU, memory, disk, network, GPU
   □ Application-specific metrics are collected where relevant

5. Integration Accuracy:
   □ Service names and endpoints match Container Services Bible
   □ GPU metrics account for Pascal architecture limitations
   □ Storage metrics distinguish between hot and cold storage tiers
   □ System metrics reflect actual hardware configuration

Return a JSON assessment:
{
  "validation_passed": boolean,
  "prometheus_config_accuracy": 0-100,
  "grafana_config_accuracy": 0-100,
  "alert_config_accuracy": 0-100,
  "monitoring_coverage": 0-100,
  "critical_issues": ["list of any critical monitoring configuration errors"],
  "missing_metrics": ["list of important metrics that should be monitored"],
  "cross_reference_accuracy": 0-100
}
"""

MONITORING_OBSERVABILITY_NEW_METRICS_PROMPT = """
New metrics or monitoring capabilities have been added to the system. Update the Monitoring Bible:

NEW METRICS DETAILS:
{new_metrics_info}

INTEGRATION REQUIREMENTS:
1. Add new Prometheus scrape configurations for new metric endpoints
2. Create or update Grafana dashboard panels to visualize new metrics
3. Define appropriate alert rules for new metrics if they indicate critical conditions
4. Add new diagnostic procedures that utilize the new metrics
5. Update monitoring coverage documentation to include new metrics
6. Add troubleshooting guidance for when new metrics indicate problems

TECHNICAL CONSTRAINTS:
- New metric names must follow Prometheus naming conventions
- Dashboard panels must use correct query syntax
- Alert thresholds must be based on actual metric behavior, not assumptions
- New metrics must not significantly impact system performance

Integrate the new metrics properly into the existing monitoring infrastructure.
"""

MONITORING_OBSERVABILITY_DASHBOARD_UPDATE_PROMPT = """
Dashboard improvements or new visualization techniques have been implemented:

DASHBOARD UPDATES:
{dashboard_info}

UPDATE REQUIREMENTS:
1. Update Grafana dashboard JSON with new panel configurations
2. Add new visualization types that better represent system behavior
3. Update dashboard variables and templating for improved usability
4. Add new dashboard annotations or alerts for better operational awareness
5. Update dashboard provisioning procedures if automation has changed
6. Revise dashboard troubleshooting and maintenance procedures

Ensure all dashboard updates improve operational visibility without adding confusion.
"""

MONITORING_OBSERVABILITY_ALERT_TUNING_PROMPT = """
Alert rules have been tuned or new alerting strategies have been implemented:

ALERTING UPDATES:
{alert_info}

UPDATE REQUIREMENTS:
1. Update Prometheus alert rule definitions with new thresholds
2. Revise alert labels and annotations for better incident response
3. Update notification routing and webhook configurations
4. Add new alert escalation procedures for different severity levels
5. Update alert testing and validation procedures
6. Revise alert fatigue prevention strategies

Ensure alert tuning reduces false positives while maintaining coverage of actual issues.
"""

MONITORING_OBSERVABILITY_PERFORMANCE_BASELINE_PROMPT = """
System performance baselines have been updated based on operational data:

BASELINE UPDATES:
{baseline_info}

UPDATE REQUIREMENTS:
1. Update performance baseline documentation with new measurements
2. Revise capacity planning calculations based on new baseline data
3. Update alert thresholds to reflect new normal operating ranges
4. Add new performance optimization recommendations
5. Update troubleshooting procedures with new performance expectations
6. Revise dashboard scales and ranges to match new baselines

Ensure all baseline updates reflect actual system performance and provide practical guidance.
"""

# Export prompt templates
PROMPT_TEMPLATES = {
    "system_prompt": MONITORING_OBSERVABILITY_SYSTEM_PROMPT,
    "rewrite_prompt": MONITORING_OBSERVABILITY_REWRITE_PROMPT,
    "validation_prompt": MONITORING_OBSERVABILITY_VALIDATION_PROMPT,
    "new_metrics": MONITORING_OBSERVABILITY_NEW_METRICS_PROMPT,
    "dashboard_update": MONITORING_OBSERVABILITY_DASHBOARD_UPDATE_PROMPT,
    "alert_tuning": MONITORING_OBSERVABILITY_ALERT_TUNING_PROMPT,
    "performance_baseline": MONITORING_OBSERVABILITY_PERFORMANCE_BASELINE_PROMPT
}