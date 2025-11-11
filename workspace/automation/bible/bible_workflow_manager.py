#\!/usr/bin/env python3
"""
AI Bible Documentation System - Workflow Manager
Agent 7: Integration & Workflow Manager

Central orchestrator for the AI Bible Documentation System that coordinates
all components in a unified workflow integrated with NixOS rebuild process.
"""

import os
import sys
import json
import yaml
import time
import uuid
import logging
import argparse
import subprocess
import threading
from enum import Enum
from pathlib import Path
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional, Tuple, NamedTuple
from dataclasses import dataclass, asdict
from contextlib import contextmanager

class ErrorSeverity(Enum):
    """Error severity classification"""
    CRITICAL = "critical"    # System-breaking, immediate rollback
    WARNING = "warning"      # Degraded function, continue with caution  
    INFO = "info"           # Informational, normal operation

class WorkflowTrigger(Enum):
    """Workflow trigger types"""
    POST_BUILD_SUCCESS = "post_build_success"
    POST_BUILD_FAILURE = "post_build_failure"
    MANUAL_TRIGGER = "manual_trigger"
    SCHEDULED_MAINTENANCE = "scheduled_maintenance"
    HEALTH_CHECK = "health_check"

class ComponentStatus(Enum):
    """Component status states"""
    ONLINE = "online"
    OFFLINE = "offline"
    DEGRADED = "degraded"
    UNKNOWN = "unknown"

@dataclass
class WorkflowError(Exception):
    """Workflow error with classification"""
    component: str
    severity: ErrorSeverity
    message: str
    details: Dict = None
    timestamp: datetime = datetime.now()
    
    def __post_init__(self):
        if self.details is None:
            self.details = {}

@dataclass
class ComponentResult:
    """Result from component execution"""
    component: str
    success: bool
    duration: float
    message: str
    details: Dict = None
    error: Optional[WorkflowError] = None

@dataclass
class WorkflowContext:
    """Context information for workflow execution"""
    correlation_id: str
    trigger: WorkflowTrigger
    start_time: datetime
    trigger_details: Dict = None
    debug_mode: bool = False
    dry_run: bool = False
    
    def __post_init__(self):
        if self.trigger_details is None:
            self.trigger_details = {}

class BibleWorkflowManager:
    """Central workflow orchestrator for AI Bible Documentation System"""
    
    def __init__(self, config_path: str = "/etc/nixos/config/bible_system_config.yaml"):
        """Initialize workflow manager"""
        self.config_path = Path(config_path)
        self.config = self._load_config()
        self.base_dir = Path(self.config['paths']['base_directory'])
        
        # Workflow state
        self.current_workflow: Optional[WorkflowContext] = None
        self.workflow_lock = threading.Lock()
        self.component_status: Dict[str, ComponentStatus] = {}
        self.last_health_check: Optional[datetime] = None
        
        # Setup logging
        self._setup_logging()
        
        # Initialize components
        self._initialize_components()
        
    def _load_config(self) -> Dict[str, Any]:
        """Load system configuration"""
        try:
            with open(self.config_path, 'r') as f:
                return yaml.safe_load(f)
        except FileNotFoundError:
            print(f"FATAL: Configuration file not found: {self.config_path}")
            sys.exit(1)
        except yaml.YAMLError as e:
            print(f"FATAL: Invalid YAML configuration: {e}")
            sys.exit(1)
    
    def _setup_logging(self):
        """Setup comprehensive logging system"""
        log_dir = Path(self.config['paths']['logs_directory'])
        log_dir.mkdir(parents=True, exist_ok=True)
        
        # Main workflow log
        log_file = log_dir / f"bible_workflow_{datetime.now().strftime('%Y%m%d')}.log"
        
        # Configure logging with correlation ID support
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - [%(correlation_id)s] - %(component)s - %(message)s',
            handlers=[
                logging.FileHandler(log_file),
                logging.StreamHandler(sys.stdout)
            ]
        )
        
        # Custom logger with workflow context
        self.logger = logging.getLogger(__name__)
        
        # Add correlation ID to all log records
        class CorrelationFilter(logging.Filter):
            def filter(self, record):
                if not hasattr(record, 'correlation_id'):
                    record.correlation_id = getattr(self.current_workflow, 'correlation_id', 'no-workflow')
                if not hasattr(record, 'component'):
                    record.component = 'workflow_manager'
                return True
        
        for handler in self.logger.handlers:
            handler.addFilter(CorrelationFilter())
        
        self.logger.info("Bible Workflow Manager - Agent 7 Initialized")
    
    def _initialize_components(self):
        """Initialize and validate component availability"""
        self.logger.info("Initializing workflow components")
        
        # Component registry
        self.components = {
            'change_accumulator': self._get_component_interface('change_accumulator'),
            'threshold_manager': self._get_component_interface('threshold_manager'),
            'bible_rewriter': self._get_component_interface('bible_rewriter'),
            'consistency_manager': self._get_component_interface('consistency_manager'),
            'migrator': self._get_component_interface('migrator'),
            'validator': self._get_component_interface('validator')
        }
        
        # Initialize component status
        for component_name in self.components:
            self.component_status[component_name] = ComponentStatus.UNKNOWN
    
    def _get_component_interface(self, component_name: str):
        """Get interface for component (placeholder for actual component interfaces)"""
        # In a full implementation, this would return actual component interfaces
        # For now, return mock interfaces
        return MockComponentInterface(component_name, self.config)
    
    @contextmanager
    def workflow_context(self, trigger: WorkflowTrigger, trigger_details: Dict = None, debug_mode: bool = False, dry_run: bool = False):
        """Context manager for workflow execution"""
        correlation_id = f"workflow_{datetime.now().strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:8]}"
        
        context = WorkflowContext(
            correlation_id=correlation_id,
            trigger=trigger,
            start_time=datetime.now(),
            trigger_details=trigger_details or {},
            debug_mode=debug_mode,
            dry_run=dry_run
        )
        
        with self.workflow_lock:
            if self.current_workflow is not None:
                raise RuntimeError(f"Another workflow is already running: {self.current_workflow.correlation_id}")
            
            self.current_workflow = context
            
        try:
            self.logger.info(f"Starting workflow: {trigger.value}")
            yield context
            
        finally:
            duration = (datetime.now() - context.start_time).total_seconds()
            self.logger.info(f"Workflow completed in {duration:.2f} seconds")
            
            with self.workflow_lock:
                self.current_workflow = None
    
    def execute_post_build_workflow(self, build_success: bool, build_details: Dict = None) -> bool:
        """Execute post-build workflow"""
        trigger = WorkflowTrigger.POST_BUILD_SUCCESS if build_success else WorkflowTrigger.POST_BUILD_FAILURE
        
        with self.workflow_context(trigger, build_details or {}) as context:
            if not build_success:
                self.logger.warning("Build failed - executing failure workflow")
                return self._execute_failure_workflow(context)
            
            return self._execute_success_workflow(context)
    
    def _execute_success_workflow(self, context: WorkflowContext) -> bool:
        """Execute post-successful-build workflow"""
        workflow_steps = [
            ("System Health Check", self._step_health_check),
            ("Change Accumulation", self._step_change_accumulation),
            ("Threshold Detection", self._step_threshold_detection),
            ("Bible Rewriting", self._step_bible_rewriting),
            ("Consistency Validation", self._step_consistency_validation),
            ("Cleanup & Finalization", self._step_cleanup_finalization)
        ]
        
        results = []
        
        try:
            for step_name, step_func in workflow_steps:
                self.logger.info(f"Executing step: {step_name}")
                
                step_start = time.time()
                try:
                    result = step_func(context)
                    step_duration = time.time() - step_start
                    
                    if result.success:
                        self.logger.info(f"Step completed: {step_name} ({step_duration:.2f}s)")
                        results.append(result)
                    else:
                        self.logger.error(f"Step failed: {step_name} - {result.message}")
                        results.append(result)
                        
                        # Handle step failure based on severity
                        if result.error and result.error.severity == ErrorSeverity.CRITICAL:
                            self.logger.error("Critical error - aborting workflow")
                            self._handle_critical_failure(context, results)
                            return False
                        elif result.error and result.error.severity == ErrorSeverity.WARNING:
                            self.logger.warning(f"Warning in {step_name} - continuing with caution")
                        
                except Exception as e:
                    step_duration = time.time() - step_start
                    error = WorkflowError("workflow_manager", ErrorSeverity.CRITICAL, f"Step {step_name} exception: {str(e)}")
                    result = ComponentResult(step_name, False, step_duration, str(e), error=error)
                    results.append(result)
                    
                    self.logger.error(f"Step exception: {step_name} - {str(e)}")
                    self._handle_critical_failure(context, results)
                    return False
            
            # All steps completed
            self._log_workflow_success(context, results)
            return True
            
        except Exception as e:
            self.logger.error(f"Workflow exception: {str(e)}")
            self._handle_critical_failure(context, results)
            return False
    
    def _execute_failure_workflow(self, context: WorkflowContext) -> bool:
        """Execute post-build-failure workflow (minimal operations)"""
        self.logger.info("Executing failure workflow - logging build failure")
        
        # Only perform minimal operations after build failure
        failure_steps = [
            ("Log Build Failure", self._step_log_build_failure),
            ("System Health Check", self._step_health_check),
            ("Update Status", self._step_update_failure_status)
        ]
        
        results = []
        for step_name, step_func in failure_steps:
            try:
                result = step_func(context)
                results.append(result)
                if result.success:
                    self.logger.info(f"Failure step completed: {step_name}")
                else:
                    self.logger.warning(f"Failure step warning: {step_name} - {result.message}")
            except Exception as e:
                self.logger.error(f"Failure step exception: {step_name} - {str(e)}")
        
        return True  # Failure workflow should always "succeed"
    
    def _step_health_check(self, context: WorkflowContext) -> ComponentResult:
        """Execute system health check step"""
        start_time = time.time()
        
        try:
            # Check all components
            health_results = {}
            overall_healthy = True
            
            for component_name, component in self.components.items():
                try:
                    component_healthy = component.health_check()
                    health_results[component_name] = component_healthy
                    if component_healthy:
                        self.component_status[component_name] = ComponentStatus.ONLINE
                    else:
                        self.component_status[component_name] = ComponentStatus.DEGRADED
                        overall_healthy = False
                        
                except Exception as e:
                    self.logger.warning(f"Health check failed for {component_name}: {str(e)}")
                    self.component_status[component_name] = ComponentStatus.OFFLINE
                    health_results[component_name] = False
                    overall_healthy = False
            
            self.last_health_check = datetime.now()
            
            duration = time.time() - start_time
            
            if overall_healthy:
                return ComponentResult(
                    "health_check", True, duration, 
                    "All components healthy",
                    {"health_results": health_results}
                )
            else:
                # Degraded but not critical
                error = WorkflowError("health_check", ErrorSeverity.WARNING, "Some components unhealthy", health_results)
                return ComponentResult(
                    "health_check", False, duration,
                    "System degraded but operational",
                    {"health_results": health_results},
                    error
                )
                
        except Exception as e:
            duration = time.time() - start_time
            error = WorkflowError("health_check", ErrorSeverity.CRITICAL, f"Health check failed: {str(e)}")
            return ComponentResult("health_check", False, duration, str(e), error=error)
    
    def _step_change_accumulation(self, context: WorkflowContext) -> ComponentResult:
        """Execute change accumulation step"""
        start_time = time.time()
        
        try:
            component = self.components['change_accumulator']
            
            # Get accumulated changes since last update
            changes = component.get_accumulated_changes()
            change_count = sum(len(change_list) for change_list in changes.values())
            
            duration = time.time() - start_time
            
            if change_count > 0:
                self.logger.info(f"Accumulated {change_count} changes across {len(changes)} categories")
                return ComponentResult(
                    "change_accumulation", True, duration,
                    f"Found {change_count} changes",
                    {"changes": changes, "change_count": change_count}
                )
            else:
                self.logger.info("No changes accumulated since last update")
                return ComponentResult(
                    "change_accumulation", True, duration,
                    "No changes to process",
                    {"changes": {}, "change_count": 0}
                )
                
        except Exception as e:
            duration = time.time() - start_time
            error = WorkflowError("change_accumulator", ErrorSeverity.WARNING, f"Change accumulation failed: {str(e)}")
            return ComponentResult("change_accumulation", False, duration, str(e), error=error)
    
    def _step_threshold_detection(self, context: WorkflowContext) -> ComponentResult:
        """Execute threshold detection step"""
        start_time = time.time()
        
        try:
            component = self.components['threshold_manager']
            
            # Get changes from previous step
            prev_results = getattr(context, 'step_results', {})
            changes = prev_results.get('change_accumulation', {}).get('details', {}).get('changes', {})
            
            if not changes:
                duration = time.time() - start_time
                return ComponentResult(
                    "threshold_detection", True, duration,
                    "No changes to evaluate",
                    {"updates_needed": {}}
                )
            
            # Check thresholds for each bible category
            updates_needed = component.check_thresholds(changes)
            update_count = sum(1 for needed in updates_needed.values() if needed)
            
            duration = time.time() - start_time
            
            if update_count > 0:
                self.logger.info(f"Threshold detection: {update_count} bibles need updates")
                return ComponentResult(
                    "threshold_detection", True, duration,
                    f"{update_count} bibles exceed thresholds",
                    {"updates_needed": updates_needed, "update_count": update_count}
                )
            else:
                self.logger.info("No bibles exceed update thresholds")
                return ComponentResult(
                    "threshold_detection", True, duration,
                    "No updates needed",
                    {"updates_needed": {}, "update_count": 0}
                )
                
        except Exception as e:
            duration = time.time() - start_time
            error = WorkflowError("threshold_manager", ErrorSeverity.WARNING, f"Threshold detection failed: {str(e)}")
            return ComponentResult("threshold_detection", False, duration, str(e), error=error)
    
    def _step_bible_rewriting(self, context: WorkflowContext) -> ComponentResult:
        """Execute bible rewriting step"""
        start_time = time.time()
        
        try:
            component = self.components['bible_rewriter']
            
            # Get updates needed from previous step
            prev_results = getattr(context, 'step_results', {})
            updates_needed = prev_results.get('threshold_detection', {}).get('details', {}).get('updates_needed', {})
            changes = prev_results.get('change_accumulation', {}).get('details', {}).get('changes', {})
            
            if not any(updates_needed.values()):
                duration = time.time() - start_time
                return ComponentResult(
                    "bible_rewriting", True, duration,
                    "No bible updates needed",
                    {"updated_bibles": []}
                )
            
            # Perform bible updates
            updated_bibles = []
            update_results = {}
            
            for bible_name, needs_update in updates_needed.items():
                if needs_update:
                    bible_changes = changes.get(bible_name, [])
                    
                    if context.dry_run:
                        self.logger.info(f"DRY RUN: Would update bible {bible_name} with {len(bible_changes)} changes")
                        update_results[bible_name] = {"success": True, "dry_run": True}
                        updated_bibles.append(bible_name)
                    else:
                        self.logger.info(f"Updating bible: {bible_name}")
                        result = component.update_bible(bible_name, bible_changes)
                        update_results[bible_name] = result
                        
                        if result.get("success", False):
                            updated_bibles.append(bible_name)
                        else:
                            self.logger.error(f"Failed to update bible {bible_name}: {result.get('error', 'Unknown error')}")
            
            duration = time.time() - start_time
            
            if len(updated_bibles) == len([b for b, needed in updates_needed.items() if needed]):
                return ComponentResult(
                    "bible_rewriting", True, duration,
                    f"Successfully updated {len(updated_bibles)} bibles",
                    {"updated_bibles": updated_bibles, "update_results": update_results}
                )
            else:
                failed_count = len([b for b, needed in updates_needed.items() if needed]) - len(updated_bibles)
                error = WorkflowError("bible_rewriter", ErrorSeverity.WARNING, f"{failed_count} bible updates failed")
                return ComponentResult(
                    "bible_rewriting", False, duration,
                    f"Partial success: {len(updated_bibles)} updated, {failed_count} failed",
                    {"updated_bibles": updated_bibles, "update_results": update_results},
                    error
                )
                
        except Exception as e:
            duration = time.time() - start_time
            error = WorkflowError("bible_rewriter", ErrorSeverity.CRITICAL, f"Bible rewriting failed: {str(e)}")
            return ComponentResult("bible_rewriting", False, duration, str(e), error=error)
    
    def _step_consistency_validation(self, context: WorkflowContext) -> ComponentResult:
        """Execute consistency validation step"""
        start_time = time.time()
        
        try:
            component = self.components['consistency_manager']
            
            # Get updated bibles from previous step
            prev_results = getattr(context, 'step_results', {})
            updated_bibles = prev_results.get('bible_rewriting', {}).get('details', {}).get('updated_bibles', [])
            
            if not updated_bibles:
                duration = time.time() - start_time
                return ComponentResult(
                    "consistency_validation", True, duration,
                    "No bibles to validate",
                    {"validation_results": {}}
                )
            
            # Validate consistency
            if context.dry_run:
                self.logger.info(f"DRY RUN: Would validate consistency for {len(updated_bibles)} bibles")
                validation_results = {bible: {"consistent": True, "dry_run": True} for bible in updated_bibles}
            else:
                self.logger.info(f"Validating consistency for {len(updated_bibles)} updated bibles")
                validation_results = component.validate_consistency(updated_bibles)
            
            duration = time.time() - start_time
            
            # Check validation results
            inconsistent_bibles = [bible for bible, result in validation_results.items() 
                                 if not result.get("consistent", False)]
            
            if not inconsistent_bibles:
                return ComponentResult(
                    "consistency_validation", True, duration,
                    "All bibles consistent",
                    {"validation_results": validation_results}
                )
            else:
                error = WorkflowError("consistency_manager", ErrorSeverity.WARNING, 
                                    f"{len(inconsistent_bibles)} bibles have consistency issues")
                return ComponentResult(
                    "consistency_validation", False, duration,
                    f"Consistency issues in {len(inconsistent_bibles)} bibles",
                    {"validation_results": validation_results, "inconsistent_bibles": inconsistent_bibles},
                    error
                )
                
        except Exception as e:
            duration = time.time() - start_time
            error = WorkflowError("consistency_manager", ErrorSeverity.WARNING, f"Consistency validation failed: {str(e)}")
            return ComponentResult("consistency_validation", False, duration, str(e), error=error)
    
    def _step_cleanup_finalization(self, context: WorkflowContext) -> ComponentResult:
        """Execute cleanup and finalization step"""
        start_time = time.time()
        
        try:
            cleanup_tasks = []
            
            # Reset change accumulation for successfully updated bibles
            prev_results = getattr(context, 'step_results', {})
            updated_bibles = prev_results.get('bible_rewriting', {}).get('details', {}).get('updated_bibles', [])
            
            if updated_bibles and not context.dry_run:
                component = self.components['change_accumulator']
                component.reset_accumulation(updated_bibles)
                cleanup_tasks.append(f"Reset accumulation for {len(updated_bibles)} bibles")
            
            # Perform log rotation if needed
            if self._should_rotate_logs():
                self._rotate_logs()
                cleanup_tasks.append("Rotated logs")
            
            # Clean up old backups
            self._cleanup_old_backups()
            cleanup_tasks.append("Cleaned old backups")
            
            duration = time.time() - start_time
            
            return ComponentResult(
                "cleanup_finalization", True, duration,
                f"Completed {len(cleanup_tasks)} cleanup tasks",
                {"cleanup_tasks": cleanup_tasks}
            )
            
        except Exception as e:
            duration = time.time() - start_time
            error = WorkflowError("workflow_manager", ErrorSeverity.WARNING, f"Cleanup failed: {str(e)}")
            return ComponentResult("cleanup_finalization", False, duration, str(e), error=error)
    
    def _step_log_build_failure(self, context: WorkflowContext) -> ComponentResult:
        """Log build failure information"""
        start_time = time.time()
        
        build_details = context.trigger_details
        self.logger.error(f"NixOS build failed: {build_details}")
        
        duration = time.time() - start_time
        return ComponentResult(
            "log_build_failure", True, duration,
            "Build failure logged",
            {"build_details": build_details}
        )
    
    def _step_update_failure_status(self, context: WorkflowContext) -> ComponentResult:
        """Update system status after build failure"""
        start_time = time.time()
        
        # Update system status to indicate build failure
        status_file = Path(self.config['paths']['logs_directory']) / "last_build_status.json"
        status = {
            "timestamp": datetime.now().isoformat(),
            "build_success": False,
            "details": context.trigger_details,
            "correlation_id": context.correlation_id
        }
        
        try:
            with open(status_file, 'w') as f:
                json.dump(status, f, indent=2)
        except Exception as e:
            self.logger.warning(f"Could not update status file: {str(e)}")
        
        duration = time.time() - start_time
        return ComponentResult(
            "update_failure_status", True, duration,
            "Status updated",
            {"status_file": str(status_file)}
        )
    
    def _handle_critical_failure(self, context: WorkflowContext, results: List[ComponentResult]):
        """Handle critical workflow failure"""
        self.logger.error("Critical failure detected - initiating recovery procedures")
        
        # Log failure details
        failure_log = {
            "correlation_id": context.correlation_id,
            "trigger": context.trigger.value,
            "failure_time": datetime.now().isoformat(),
            "results": [asdict(result) for result in results],
            "component_status": {name: status.value for name, status in self.component_status.items()}
        }
        
        failure_file = Path(self.config['paths']['logs_directory']) / f"critical_failure_{context.correlation_id}.json"
        try:
            with open(failure_file, 'w') as f:
                json.dump(failure_log, f, indent=2, default=str)
            self.logger.info(f"Critical failure details saved to: {failure_file}")
        except Exception as e:
            self.logger.error(f"Could not save failure details: {str(e)}")
        
        # Attempt recovery operations
        try:
            self._attempt_system_recovery(context)
        except Exception as e:
            self.logger.error(f"Recovery attempt failed: {str(e)}")
    
    def _attempt_system_recovery(self, context: WorkflowContext):
        """Attempt system recovery after critical failure"""
        self.logger.info("Attempting system recovery")
        
        # Basic recovery operations
        recovery_steps = [
            ("Validate system integrity", self._validate_system_integrity),
            ("Restore from backup if needed", self._restore_from_backup_if_needed),
            ("Reset component states", self._reset_component_states),
            ("Perform health check", self._perform_recovery_health_check)
        ]
        
        for step_name, step_func in recovery_steps:
            try:
                self.logger.info(f"Recovery step: {step_name}")
                step_func()
            except Exception as e:
                self.logger.error(f"Recovery step failed: {step_name} - {str(e)}")
    
    def _validate_system_integrity(self):
        """Validate system integrity during recovery"""
        validator = self.components['validator']
        result = validator.validate_system_integrity()
        if not result.get("success", False):
            self.logger.warning("System integrity issues detected during recovery")
    
    def _restore_from_backup_if_needed(self):
        """Restore from backup if system is corrupted"""
        # This would implement backup restoration logic
        self.logger.info("Checking if backup restoration is needed")
        # Placeholder for actual backup restoration logic
    
    def _reset_component_states(self):
        """Reset component states to known good state"""
        for component_name in self.components:
            self.component_status[component_name] = ComponentStatus.UNKNOWN
        self.logger.info("Component states reset")
    
    def _perform_recovery_health_check(self):
        """Perform health check as part of recovery"""
        try:
            context = WorkflowContext(
                correlation_id=f"recovery_{datetime.now().strftime('%Y%m%d_%H%M%S')}",
                trigger=WorkflowTrigger.HEALTH_CHECK,
                start_time=datetime.now()
            )
            result = self._step_health_check(context)
            if result.success:
                self.logger.info("Recovery health check passed")
            else:
                self.logger.warning("Recovery health check shows issues")
        except Exception as e:
            self.logger.error(f"Recovery health check failed: {str(e)}")
    
    def _log_workflow_success(self, context: WorkflowContext, results: List[ComponentResult]):
        """Log successful workflow completion"""
        duration = (datetime.now() - context.start_time).total_seconds()
        
        success_summary = {
            "correlation_id": context.correlation_id,
            "trigger": context.trigger.value,
            "completion_time": datetime.now().isoformat(),
            "duration_seconds": duration,
            "results_summary": {
                "total_steps": len(results),
                "successful_steps": len([r for r in results if r.success]),
                "warnings": len([r for r in results if not r.success and r.error and r.error.severity == ErrorSeverity.WARNING])
            },
            "component_timings": {result.component: result.duration for result in results}
        }
        
        self.logger.info(f"Workflow completed successfully: {json.dumps(success_summary, indent=2)}")
        
        # Save success details
        success_file = Path(self.config['paths']['logs_directory']) / f"workflow_success_{context.correlation_id}.json"
        try:
            with open(success_file, 'w') as f:
                json.dump(success_summary, f, indent=2)
        except Exception as e:
            self.logger.warning(f"Could not save success details: {str(e)}")
    
    def _should_rotate_logs(self) -> bool:
        """Check if log rotation is needed"""
        log_dir = Path(self.config['paths']['logs_directory'])
        if not log_dir.exists():
            return False
        
        # Check if any log file exceeds size limit
        max_size = self.config.get('monitoring', {}).get('logging', {}).get('max_size_mb', 50) * 1024 * 1024
        
        for log_file in log_dir.glob("*.log"):
            if log_file.stat().st_size > max_size:
                return True
        
        return False
    
    def _rotate_logs(self):
        """Rotate log files"""
        self.logger.info("Rotating log files")
        # Placeholder for log rotation logic
    
    def _cleanup_old_backups(self):
        """Clean up old backup files"""
        backup_dir = Path(self.config['paths']['backups_directory'])
        if not backup_dir.exists():
            return
        
        # Keep only recent backups
        retention_count = self.config.get('bible_system', {}).get('performance', {}).get('backup_retention_count', 10)
        
        # This would implement actual backup cleanup
        self.logger.debug(f"Cleaning old backups (keeping {retention_count})")
    
    def execute_manual_workflow(self, operation: str, **kwargs) -> bool:
        """Execute manual workflow operations"""
        operation_map = {
            'health-check': self._manual_health_check,
            'force-update': self._manual_force_update, 
            'validate': self._manual_validate,
            'migrate': self._manual_migrate,
            'cleanup': self._manual_cleanup
        }
        
        if operation not in operation_map:
            self.logger.error(f"Unknown manual operation: {operation}")
            return False
        
        trigger_details = {"operation": operation, "kwargs": kwargs}
        
        with self.workflow_context(WorkflowTrigger.MANUAL_TRIGGER, trigger_details, **kwargs) as context:
            return operation_map[operation](context, **kwargs)
    
    def _manual_health_check(self, context: WorkflowContext, **kwargs) -> bool:
        """Execute manual health check"""
        result = self._step_health_check(context)
        
        # Print health check results
        print(f"\nHealth Check Results:")
        print(f"Overall Status: {'HEALTHY' if result.success else 'DEGRADED'}")
        print(f"Duration: {result.duration:.2f} seconds")
        
        if result.details and 'health_results' in result.details:
            print(f"\nComponent Status:")
            for component, healthy in result.details['health_results'].items():
                status = "✓" if healthy else "✗"
                print(f"  {status} {component}")
        
        return result.success
    
    def _manual_force_update(self, context: WorkflowContext, **kwargs) -> bool:
        """Execute manual force update"""
        self.logger.info("Executing forced bible updates")
        
        # Skip threshold detection for force update
        workflow_steps = [
            ("System Health Check", self._step_health_check),
            ("Change Accumulation", self._step_change_accumulation),
            ("Bible Rewriting (Forced)", lambda ctx: self._force_bible_updates(ctx, kwargs.get('bibles', []))),
            ("Consistency Validation", self._step_consistency_validation),
            ("Cleanup & Finalization", self._step_cleanup_finalization)
        ]
        
        results = []
        for step_name, step_func in workflow_steps:
            try:
                result = step_func(context)
                results.append(result)
                if not result.success and result.error and result.error.severity == ErrorSeverity.CRITICAL:
                    self.logger.error(f"Critical error in {step_name} - aborting")
                    return False
            except Exception as e:
                self.logger.error(f"Exception in {step_name}: {str(e)}")
                return False
        
        return True
    
    def _force_bible_updates(self, context: WorkflowContext, bible_list: List[str]) -> ComponentResult:
        """Force bible updates without threshold checking"""
        start_time = time.time()
        
        try:
            component = self.components['bible_rewriter']
            
            # If no specific bibles specified, update all
            if not bible_list:
                # Load bible categories
                categories_path = Path(self.config['paths']['bible_categories'])
                with open(categories_path, 'r') as f:
                    categories = yaml.safe_load(f)
                bible_list = list(categories['bible_categories'].keys())
            
            updated_bibles = []
            update_results = {}
            
            for bible_name in bible_list:
                self.logger.info(f"Force updating bible: {bible_name}")
                
                if context.dry_run:
                    update_results[bible_name] = {"success": True, "dry_run": True}
                    updated_bibles.append(bible_name)
                else:
                    result = component.update_bible(bible_name, [])  # Empty changes for force update
                    update_results[bible_name] = result
                    
                    if result.get("success", False):
                        updated_bibles.append(bible_name)
            
            duration = time.time() - start_time
            
            return ComponentResult(
                "force_bible_updates", True, duration,
                f"Force updated {len(updated_bibles)} bibles",
                {"updated_bibles": updated_bibles, "update_results": update_results}
            )
            
        except Exception as e:
            duration = time.time() - start_time
            error = WorkflowError("bible_rewriter", ErrorSeverity.CRITICAL, f"Force update failed: {str(e)}")
            return ComponentResult("force_bible_updates", False, duration, str(e), error=error)
    
    def _manual_validate(self, context: WorkflowContext, **kwargs) -> bool:
        """Execute manual validation"""
        validator = self.components['validator']
        
        if kwargs.get('full', False):
            result = validator.run_full_validation()
        else:
            result = validator.run_health_check()
        
        print(f"\nValidation Results: {'PASSED' if result else 'FAILED'}")
        return result
    
    def _manual_migrate(self, context: WorkflowContext, **kwargs) -> bool:
        """Execute manual migration"""
        migrator = self.components['migrator']
        
        if kwargs.get('detect_only', False):
            result = migrator.detect_legacy_configuration()
            print(f"\nLegacy Detection Results:")
            print(json.dumps(result, indent=2))
            return True
        else:
            result = migrator.migrate_legacy_documentation()
            print(f"\nMigration Result: {'SUCCESS' if result else 'FAILED'}")
            return result
    
    def _manual_cleanup(self, context: WorkflowContext, **kwargs) -> bool:
        """Execute manual cleanup"""
        result = self._step_cleanup_finalization(context)
        print(f"\nCleanup Result: {'SUCCESS' if result.success else 'FAILED'}")
        if result.details and 'cleanup_tasks' in result.details:
            print(f"Tasks completed:")
            for task in result.details['cleanup_tasks']:
                print(f"  - {task}")
        return result.success

class MockComponentInterface:
    """Mock component interface for testing"""
    
    def __init__(self, component_name: str, config: Dict):
        self.component_name = component_name
        self.config = config
    
    def health_check(self) -> bool:
        """Mock health check"""
        return True
    
    def get_accumulated_changes(self) -> Dict[str, List]:
        """Mock change accumulation"""
        return {"hardware_gpu": [], "container_services": []}
    
    def reset_accumulation(self, bible_categories: List[str]) -> bool:
        """Mock accumulation reset"""
        return True
    
    def check_thresholds(self, changes: Dict) -> Dict[str, bool]:
        """Mock threshold checking"""
        return {category: False for category in changes.keys()}
    
    def update_bible(self, bible_name: str, changes: List) -> Dict:
        """Mock bible update"""
        return {"success": True, "bible": bible_name, "changes_applied": len(changes)}
    
    def validate_consistency(self, updated_bibles: List[str]) -> Dict:
        """Mock consistency validation"""
        return {bible: {"consistent": True} for bible in updated_bibles}
    
    def validate_system_integrity(self) -> Dict:
        """Mock system integrity validation"""
        return {"success": True, "issues": []}
    
    def run_health_check(self) -> bool:
        """Mock health check"""
        return True
    
    def run_full_validation(self) -> bool:
        """Mock full validation"""
        return True
    
    def detect_legacy_configuration(self) -> Dict:
        """Mock legacy detection"""
        return {"has_legacy": False, "legacy_files": []}
    
    def migrate_legacy_documentation(self) -> bool:
        """Mock migration"""
        return True

def main():
    """Main workflow manager entry point"""
    parser = argparse.ArgumentParser(description="Bible Workflow Manager - Agent 7")
    parser.add_argument(
        "--config", 
        default="/etc/nixos/config/bible_system_config.yaml",
        help="Configuration file path"
    )
    
    # Workflow triggers
    parser.add_argument("--post-build", action="store_true", help="Execute post-build workflow")
    parser.add_argument("--build-success", action="store_true", help="Build was successful")
    parser.add_argument("--build-failed", action="store_true", help="Build failed")
    
    # Manual operations
    parser.add_argument("--health-check", action="store_true", help="Run health check")
    parser.add_argument("--force-update", action="store_true", help="Force bible updates")
    parser.add_argument("--validate", action="store_true", help="Run system validation")
    parser.add_argument("--migrate", action="store_true", help="Run migration")
    parser.add_argument("--cleanup", action="store_true", help="Run cleanup")
    
    # Options
    parser.add_argument("--bibles", nargs="*", help="Specific bibles to operate on")
    parser.add_argument("--debug", action="store_true", help="Enable debug mode")
    parser.add_argument("--dry-run", action="store_true", help="Dry run mode")
    parser.add_argument("--full", action="store_true", help="Full validation")
    parser.add_argument("--detect-only", action="store_true", help="Migration detection only")
    
    args = parser.parse_args()
    
    # Initialize workflow manager
    try:
        manager = BibleWorkflowManager(args.config)
    except SystemExit:
        return 1
    except Exception as e:
        print(f"Failed to initialize workflow manager: {str(e)}")
        return 1
    
    success = True
    
    try:
        if args.post_build:
            build_success = args.build_success or not args.build_failed
            success = manager.execute_post_build_workflow(build_success)
            
        elif args.health_check:
            success = manager.execute_manual_workflow('health-check', debug=args.debug)
            
        elif args.force_update:
            success = manager.execute_manual_workflow('force-update', 
                                                    bibles=args.bibles or [], 
                                                    debug=args.debug, 
                                                    dry_run=args.dry_run)
            
        elif args.validate:
            success = manager.execute_manual_workflow('validate', 
                                                    full=args.full, 
                                                    debug=args.debug)
            
        elif args.migrate:
            success = manager.execute_manual_workflow('migrate', 
                                                    detect_only=args.detect_only, 
                                                    debug=args.debug, 
                                                    dry_run=args.dry_run)
            
        elif args.cleanup:
            success = manager.execute_manual_workflow('cleanup', debug=args.debug)
            
        else:
            parser.print_help()
            return 0
    
    except KeyboardInterrupt:
        print("\nWorkflow interrupted by user")
        return 1
    except Exception as e:
        print(f"Workflow failed with exception: {str(e)}")
        return 1
    
    return 0 if success else 1

if __name__ == "__main__":
    sys.exit(main())
EOF < /dev/null