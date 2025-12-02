#!/usr/bin/env python3
"""
Storage & Data Pipeline Bible - AI Prompting Templates
Specialized prompts for two-tier storage architecture and data pipeline management
"""

STORAGE_DATA_SYSTEM_PROMPT = """You are a technical documentation expert specializing in two-tier storage architectures and automated data pipeline management for media homeservers. You have deep expertise in:

- Two-tier storage architecture (hot SSD + cold HDD storage)
- Automated data migration and retention policies
- Media pipeline workflows (download → process → archive)
- Storage monitoring and capacity management
- Backup strategies and disaster recovery
- Integration with media services and surveillance systems

Your documentation must provide precise storage configurations, reliable automation scripts, and practical capacity planning that works efficiently in production environments."""

STORAGE_DATA_REWRITE_PROMPT = """
SYSTEM CONTEXT:
- Storage Architecture: Hot storage (SSD /mnt/hot) + Cold storage (HDD /mnt/media)
- Data Pipeline: Download → Process → Migrate → Archive with automation
- Services Integration: Media pipeline (*arr apps), surveillance (Frigate), business services
- Automation: rsync-based migration with completion status, age, and threshold triggers
- Monitoring: Storage usage alerts and capacity planning automation

ACCUMULATED CHANGES TO INTEGRATE:
{accumulated_changes}

CURRENT BIBLE CONTENT:
{existing_content}

INTEGRATION REQUIREMENTS:
1. PRESERVE EXACTLY:
   - Storage mount paths (/mnt/hot, /mnt/media) and filesystem configurations
   - Working automation scripts and migration workflows
   - Retention policies and cleanup procedures that are functioning
   - Backup strategies and disaster recovery procedures
   - Capacity thresholds and alerting configurations

2. UPDATE INTELLIGENTLY:
   - Add new data flows or storage optimization techniques
   - Integrate improvements to automation scripts or migration logic
   - Update capacity planning based on new usage patterns
   - Add new backup procedures or disaster recovery improvements
   - Update monitoring configurations for new storage metrics

3. MAINTAIN TECHNICAL ACCURACY:
   - Storage paths must match actual filesystem mounts and permissions
   - Automation scripts must be executable and syntactically correct
   - Retention policies must be mathematically sound and safe
   - Capacity calculations must reflect actual storage hardware
   - Data flow timing must be realistic for storage performance characteristics

4. CROSS-BIBLE CONSISTENCY:
   - Storage mount paths must match Container Services Bible service configurations
   - Monitoring metrics must align with Monitoring Bible dashboard expectations
   - Automation triggers must integrate with System Architecture Bible procedures
   - Data security must comply with System Architecture Bible security requirements

CRITICAL TECHNICAL CONSTRAINTS:
- Hot storage (/mnt/hot) is SSD - optimized for frequent access and fast processing
- Cold storage (/mnt/media) is HDD - optimized for capacity and long-term retention
- Migration automation must preserve file integrity and handle errors gracefully
- Retention policies must prevent accidental deletion of active or critical data
- Storage monitoring must account for both filesystem usage and actual disk health
- Backup procedures must not interfere with active media streaming or processing

Generate an updated Storage & Data Pipeline Bible that seamlessly integrates the accumulated changes while preserving all working storage configurations and automation workflows.

FORMATTING REQUIREMENTS:
- Maintain existing section structure with clear hot/cold storage separation
- Preserve all working automation scripts and configuration examples exactly
- Use consistent path naming and filesystem conventions throughout
- Include data flow diagrams and capacity planning charts where relevant
- Cross-reference other bibles without duplicating their storage-specific content
"""

STORAGE_DATA_VALIDATION_PROMPT = """
Review this updated Storage & Data Pipeline Bible for technical accuracy:

{updated_content}

VALIDATION CHECKLIST:
1. Storage Configuration:
   □ Mount paths match actual filesystem configuration (/mnt/hot, /mnt/media)
   □ File permissions and ownership are correctly specified
   □ Storage tier characteristics (SSD vs HDD) are accurately described
   □ Capacity specifications match actual hardware

2. Automation Scripts:
   □ All scripts are syntactically correct and executable
   □ Migration logic preserves file integrity with proper error handling
   □ Retention policies are mathematically sound and safe
   □ Cleanup procedures won't accidentally delete active data

3. Data Pipeline:
   □ Data flow sequence is logical and technically feasible
   □ Timing estimates are realistic for storage performance
   □ Integration points with services are clearly defined
   □ Error handling covers realistic failure scenarios

4. Monitoring Integration:
   □ Storage metrics match available monitoring capabilities
   □ Capacity thresholds are appropriate for actual storage sizes
   □ Alert conditions are actionable and not prone to false positives
   □ Dashboard integration points are technically accurate

5. Cross-Bible References:
   □ Service mount paths match Container Services Bible exactly
   □ Monitoring configurations align with Monitoring Bible
   □ Security procedures comply with System Architecture Bible

Return a JSON assessment:
{
  "validation_passed": boolean,
  "storage_config_accuracy": 0-100,
  "automation_script_accuracy": 0-100,
  "data_pipeline_feasibility": 0-100,
  "critical_issues": ["list of any critical storage configuration errors"],
  "automation_risks": ["list of potential automation safety issues"],
  "cross_reference_accuracy": 0-100
}
"""

STORAGE_DATA_CAPACITY_UPDATE_PROMPT = """
Storage capacity or usage patterns have changed. Update the Storage & Data Pipeline Bible:

CAPACITY CHANGES:
{capacity_info}

UPDATE REQUIREMENTS:
1. Update capacity planning calculations and projections
2. Revise storage tier allocation recommendations
3. Update migration thresholds based on new capacity constraints
4. Revise retention policies if storage constraints have changed
5. Update monitoring thresholds for new capacity limits
6. Add recommendations for capacity expansion if needed

Ensure all capacity calculations are accurate and storage recommendations are practical for the actual hardware configuration.
"""

STORAGE_DATA_AUTOMATION_UPDATE_PROMPT = """
New automation techniques or workflow improvements have been implemented. Update the Storage Bible:

AUTOMATION UPDATES:
{automation_info}

UPDATE REQUIREMENTS:
1. Update automation scripts with new techniques or optimizations
2. Revise data pipeline workflows for improved efficiency
3. Add new error handling or reliability improvements
4. Update monitoring of automation processes
5. Revise troubleshooting procedures for new automation features
6. Update backup and recovery procedures if automation has changed

Ensure all automation updates maintain data integrity and don't introduce new failure modes.
"""

STORAGE_DATA_MIGRATION_OPTIMIZATION_PROMPT = """
Data migration processes have been optimized or new migration strategies implemented:

MIGRATION OPTIMIZATIONS:
{migration_info}

UPDATE REQUIREMENTS:
1. Update migration algorithms and timing calculations
2. Revise migration trigger conditions and thresholds  
3. Update error handling and recovery procedures
4. Add new monitoring for migration process performance
5. Update capacity impact calculations for migration overhead
6. Revise troubleshooting for new migration edge cases

Ensure migration optimizations improve performance without compromising data safety.
"""

STORAGE_DATA_DISASTER_RECOVERY_PROMPT = """
Backup strategies or disaster recovery procedures have been updated:

DISASTER RECOVERY UPDATES:
{recovery_info}

UPDATE REQUIREMENTS:
1. Update backup procedures and schedules
2. Revise disaster recovery workflows and testing procedures
3. Update data restoration procedures and time estimates
4. Add new backup validation and integrity checking
5. Update recovery point objectives (RPO) and recovery time objectives (RTO)
6. Revise documentation of backup storage locations and access procedures

Ensure all disaster recovery procedures are tested and practically achievable.
"""

# Export prompt templates
PROMPT_TEMPLATES = {
    "system_prompt": STORAGE_DATA_SYSTEM_PROMPT,
    "rewrite_prompt": STORAGE_DATA_REWRITE_PROMPT,
    "validation_prompt": STORAGE_DATA_VALIDATION_PROMPT,
    "capacity_update": STORAGE_DATA_CAPACITY_UPDATE_PROMPT,
    "automation_update": STORAGE_DATA_AUTOMATION_UPDATE_PROMPT,
    "migration_optimization": STORAGE_DATA_MIGRATION_OPTIMIZATION_PROMPT,
    "disaster_recovery": STORAGE_DATA_DISASTER_RECOVERY_PROMPT
}