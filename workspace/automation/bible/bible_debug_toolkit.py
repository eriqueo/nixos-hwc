#\!/usr/bin/env python3
"""
AI Bible Documentation System - Debug Toolkit
Agent 7: Integration & Workflow Manager

Comprehensive debugging and troubleshooting tools for the Bible Workflow Manager.
"""

import os
import sys
import json
import yaml
import time
import logging
import argparse
import subprocess
from pathlib import Path
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional, Tuple
from dataclasses import dataclass

@dataclass
class DiagnosticResult:
    """Diagnostic test result"""
    test_name: str
    success: bool
    message: str
    details: Dict[str, Any]
    duration: float
    timestamp: datetime = datetime.now()

class BibleDebugToolkit:
    """Debugging and troubleshooting toolkit for Bible Workflow Manager"""
    
    def __init__(self, config_path: str = "/etc/nixos/config/bible_system_config.yaml"):
        """Initialize debug toolkit"""
        self.config_path = Path(config_path)
        self.config = self._load_config()
        self.base_dir = Path(self.config['paths']['base_directory'])
        self.results: List[DiagnosticResult] = []
        
        # Setup logging
        self._setup_logging()
        
    def _load_config(self) -> Dict[str, Any]:
        """Load system configuration"""
        try:
            with open(self.config_path, 'r') as f:
                return yaml.safe_load(f)
        except FileNotFoundError:
            print(f"Warning: Configuration file not found: {self.config_path}")
            return self._get_default_config()
        except yaml.YAMLError as e:
            print(f"Warning: Invalid YAML configuration: {e}")
            return self._get_default_config()
    
    def _get_default_config(self) -> Dict[str, Any]:
        """Get default configuration for debugging"""
        return {
            'paths': {
                'base_directory': '/etc/nixos',
                'docs_directory': '/etc/nixos/docs',
                'scripts_directory': '/etc/nixos/scripts',
                'logs_directory': '/etc/nixos/docs/logs',
                'config_directory': '/etc/nixos/config'
            }
        }
    
    def _setup_logging(self):
        """Setup debug logging"""
        logging.basicConfig(
            level=logging.DEBUG,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[logging.StreamHandler(sys.stdout)]
        )
        self.logger = logging.getLogger(__name__)
        self.logger.info("Bible Debug Toolkit - Agent 7")
    
    def _run_command(self, command: List[str], timeout: int = 30) -> Tuple[bool, str, str]:
        """Run command with timeout and capture output"""
        try:
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                timeout=timeout
            )
            return result.returncode == 0, result.stdout, result.stderr
        except subprocess.TimeoutExpired:
            return False, "", "Command timeout"
        except Exception as e:
            return False, "", str(e)
    
    def _add_result(self, test_name: str, success: bool, message: str, details: Dict = None, duration: float = 0.0):
        """Add diagnostic result"""
        result = DiagnosticResult(
            test_name=test_name,
            success=success,
            message=message,
            details=details or {},
            duration=duration
        )
        self.results.append(result)
        
        status = "✓" if success else "✗"
        self.logger.info(f"{status} {test_name}: {message}")
        
        return result
    
    def test_component_connectivity(self) -> bool:
        """Test connectivity to all system components"""
        self.logger.info("=== TESTING COMPONENT CONNECTIVITY ===")
        
        components = {
            'workflow_manager': '/etc/nixos/scripts/bible_workflow_manager.py',
            'validator': '/etc/nixos/scripts/bible_system_validator.py',
            'installer': '/etc/nixos/scripts/bible_system_installer.py',
            'migrator': '/etc/nixos/scripts/bible_system_migrator.py',
            'cleanup': '/etc/nixos/scripts/bible_system_cleanup.py'
        }
        
        all_connected = True
        
        for component_name, script_path in components.items():
            start_time = time.time()
            
            path = Path(script_path)
            if path.exists() and path.is_file() and os.access(path, os.X_OK):
                # Test if script can be executed
                success, stdout, stderr = self._run_command([script_path, '--help'], timeout=10)
                
                duration = time.time() - start_time
                
                if success or 'usage' in stdout.lower() or 'help' in stdout.lower():
                    self._add_result(
                        f"Component: {component_name}",
                        True,
                        "Script accessible and executable",
                        {"path": script_path, "help_output_length": len(stdout)},
                        duration
                    )
                else:
                    self._add_result(
                        f"Component: {component_name}",
                        False,
                        f"Script execution failed: {stderr[:100]}",
                        {"path": script_path, "error": stderr},
                        duration
                    )
                    all_connected = False
            else:
                self._add_result(
                    f"Component: {component_name}",
                    False,
                    "Script not found or not executable",
                    {"path": script_path, "exists": path.exists(), "executable": os.access(path, os.X_OK) if path.exists() else False}
                )
                all_connected = False
        
        return all_connected
    
    def test_workflow_execution(self, dry_run: bool = True) -> bool:
        """Test workflow execution in debug mode"""
        self.logger.info("=== TESTING WORKFLOW EXECUTION ===")
        
        workflow_script = Path('/etc/nixos/scripts/bible_workflow_manager.py')
        if not workflow_script.exists():
            self._add_result(
                "Workflow Execution",
                False,
                "Workflow manager script not found",
                {"expected_path": str(workflow_script)}
            )
            return False
        
        # Test different workflow operations
        test_operations = [
            ('health-check', ['--health-check']),
            ('post-build-dry-run', ['--post-build', '--build-success', '--dry-run'] if dry_run else ['--post-build', '--build-success'])
        ]
        
        all_tests_passed = True
        
        for test_name, args in test_operations:
            start_time = time.time()
            
            command = [str(workflow_script)] + args
            if dry_run and '--dry-run' not in args:
                command.append('--dry-run')
            
            success, stdout, stderr = self._run_command(command, timeout=60)
            duration = time.time() - start_time
            
            if success:
                self._add_result(
                    f"Workflow Test: {test_name}",
                    True,
                    f"Completed successfully ({duration:.2f}s)",
                    {
                        "command": ' '.join(command),
                        "output_lines": len(stdout.splitlines()),
                        "dry_run": dry_run
                    },
                    duration
                )
            else:
                self._add_result(
                    f"Workflow Test: {test_name}",
                    False,
                    f"Failed: {stderr[:200]}",
                    {
                        "command": ' '.join(command),
                        "stdout": stdout[:500],
                        "stderr": stderr[:500]
                    },
                    duration
                )
                all_tests_passed = False
        
        return all_tests_passed
    
    def test_system_dependencies(self) -> bool:
        """Test system dependencies and prerequisites"""
        self.logger.info("=== TESTING SYSTEM DEPENDENCIES ===")
        
        dependencies = {
            'python3': ['python3', '--version'],
            'git': ['git', '--version'],
            'systemctl': ['systemctl', '--version'],
            'nixos-rebuild': ['nixos-rebuild', '--help'],
            'ollama': ['ollama', '--version']
        }
        
        all_dependencies_met = True
        
        for dep_name, command in dependencies.items():
            start_time = time.time()
            
            success, stdout, stderr = self._run_command(command, timeout=10)
            duration = time.time() - start_time
            
            if success:
                version_info = stdout.strip().split('\n')[0] if stdout else "Available"
                self._add_result(
                    f"Dependency: {dep_name}",
                    True,
                    f"Available - {version_info}",
                    {"version_output": stdout.strip()},
                    duration
                )
            else:
                self._add_result(
                    f"Dependency: {dep_name}",
                    False,
                    f"Not available or failed: {stderr[:100]}",
                    {"error": stderr.strip()},
                    duration
                )
                all_dependencies_met = False
        
        return all_dependencies_met
    
    def test_file_system_integrity(self) -> bool:
        """Test file system paths and permissions"""
        self.logger.info("=== TESTING FILE SYSTEM INTEGRITY ===")
        
        required_paths = [
            ('/etc/nixos', 'directory', True, True),  # path, type, should_exist, should_be_writable
            ('/etc/nixos/docs', 'directory', True, True),
            ('/etc/nixos/scripts', 'directory', True, True),
            ('/etc/nixos/config', 'directory', True, True),
            (self.config_path, 'file', True, False),
            ('/etc/nixos/config/bible_categories.yaml', 'file', True, False),
            ('/etc/nixos/docs/bibles', 'directory', False, True),  # May not exist yet
            ('/etc/nixos/docs/logs', 'directory', False, True)
        ]
        
        all_paths_valid = True
        
        for path_str, path_type, should_exist, should_be_writable in required_paths:
            start_time = time.time()
            path = Path(path_str)
            
            details = {
                "path": str(path),
                "expected_type": path_type,
                "should_exist": should_exist,
                "should_be_writable": should_be_writable
            }
            
            # Check existence
            if should_exist and not path.exists():
                self._add_result(
                    f"Path: {path_str}",
                    False,
                    f"Required {path_type} does not exist",
                    details
                )
                all_paths_valid = False
                continue
            elif not should_exist and not path.exists():
                self._add_result(
                    f"Path: {path_str}",
                    True,
                    f"Optional {path_type} does not exist (OK)",
                    details
                )
                continue
            
            # Check type
            if path_type == 'directory' and not path.is_dir():
                self._add_result(
                    f"Path: {path_str}",
                    False,
                    "Expected directory but found file",
                    details
                )
                all_paths_valid = False
                continue
            elif path_type == 'file' and not path.is_file():
                self._add_result(
                    f"Path: {path_str}",
                    False,
                    "Expected file but found directory",
                    details
                )
                all_paths_valid = False
                continue
            
            # Check permissions
            readable = os.access(path, os.R_OK)
            writable = os.access(path, os.W_OK)
            
            details.update({
                "exists": True,
                "readable": readable,
                "writable": writable,
                "size_bytes": path.stat().st_size if path.is_file() else None
            })
            
            if should_be_writable and not writable:
                self._add_result(
                    f"Path: {path_str}",
                    False,
                    f"{path_type.title()} exists but is not writable",
                    details
                )
                all_paths_valid = False
            elif not readable:
                self._add_result(
                    f"Path: {path_str}",
                    False,
                    f"{path_type.title()} exists but is not readable",
                    details
                )
                all_paths_valid = False
            else:
                permission_status = "readable" + (" and writable" if writable else "")
                self._add_result(
                    f"Path: {path_str}",
                    True,
                    f"{path_type.title()} exists and is {permission_status}",
                    details
                )
        
        return all_paths_valid
    
    def test_ai_system_connectivity(self) -> bool:
        """Test AI system (Ollama) connectivity"""
        self.logger.info("=== TESTING AI SYSTEM CONNECTIVITY ===")
        
        # Test Ollama service
        start_time = time.time()
        success, stdout, stderr = self._run_command(['systemctl', 'is-active', 'ollama'], timeout=10)
        duration = time.time() - start_time
        
        if not success:
            self._add_result(
                "Ollama Service",
                False,
                f"Service not active: {stderr.strip()}",
                {"systemctl_output": stdout.strip()},
                duration
            )
            return False
        
        self._add_result(
            "Ollama Service",
            True,
            "Service is active",
            {"status": stdout.strip()},
            duration
        )
        
        # Test Ollama API connectivity
        start_time = time.time()
        try:
            import requests
            response = requests.get("http://localhost:11434/api/tags", timeout=10)
            duration = time.time() - start_time
            
            if response.status_code == 200:
                models = response.json().get('models', [])
                model_names = [model.get('name', 'unknown') for model in models]
                
                self._add_result(
                    "Ollama API",
                    True,
                    f"API responding with {len(models)} models",
                    {"models": model_names, "status_code": response.status_code},
                    duration
                )
                
                # Check for required model
                required_model = self.config.get('ai_system', {}).get('model', {}).get('name', 'llama3.2:3b')
                if any(required_model in model_name for model_name in model_names):
                    self._add_result(
                        "Required AI Model",
                        True,
                        f"Model {required_model} is available",
                        {"required_model": required_model, "available_models": model_names}
                    )
                else:
                    self._add_result(
                        "Required AI Model",
                        False,
                        f"Model {required_model} not found",
                        {"required_model": required_model, "available_models": model_names}
                    )
                    return False
                
                return True
            else:
                self._add_result(
                    "Ollama API",
                    False,
                    f"API returned status {response.status_code}",
                    {"status_code": response.status_code, "response": response.text[:200]},
                    duration
                )
                return False
                
        except ImportError:
            self._add_result(
                "Ollama API",
                False,
                "Python requests library not available",
                {"error": "ImportError: requests"}
            )
            return False
        except Exception as e:
            duration = time.time() - start_time
            self._add_result(
                "Ollama API",
                False,
                f"API connection failed: {str(e)}",
                {"error": str(e)},
                duration
            )
            return False
    
    def test_git_integration(self) -> bool:
        """Test git repository and hook integration"""
        self.logger.info("=== TESTING GIT INTEGRATION ===")
        
        git_dir = self.base_dir / ".git"
        if not git_dir.exists():
            self._add_result(
                "Git Repository",
                False,
                "Not a git repository",
                {"base_dir": str(self.base_dir), "git_dir": str(git_dir)}
            )
            return False
        
        # Test git status
        start_time = time.time()
        success, stdout, stderr = self._run_command(['git', 'status', '--porcelain'], timeout=10)
        duration = time.time() - start_time
        
        if success:
            changes = len(stdout.strip().split('\n')) if stdout.strip() else 0
            self._add_result(
                "Git Status",
                True,
                f"Repository accessible ({changes} uncommitted changes)",
                {"uncommitted_changes": changes, "status_output": stdout[:200]},
                duration
            )
        else:
            self._add_result(
                "Git Status",
                False,
                f"Git status failed: {stderr}",
                {"error": stderr},
                duration
            )
            return False
        
        # Test post-commit hook
        post_commit_hook = git_dir / "hooks" / "post-commit"
        if post_commit_hook.exists():
            hook_content = ""
            try:
                with open(post_commit_hook, 'r') as f:
                    hook_content = f.read()
            except Exception as e:
                hook_content = f"Error reading hook: {e}"
            
            has_bible_integration = "bible" in hook_content.lower()
            
            self._add_result(
                "Post-commit Hook",
                has_bible_integration,
                "Hook exists " + ("with" if has_bible_integration else "without") + " bible integration",
                {
                    "hook_path": str(post_commit_hook),
                    "hook_size": len(hook_content),
                    "has_bible_integration": has_bible_integration,
                    "executable": os.access(post_commit_hook, os.X_OK)
                }
            )
        else:
            self._add_result(
                "Post-commit Hook",
                False,
                "Post-commit hook not found",
                {"expected_path": str(post_commit_hook)}
            )
        
        return True
    
    def simulate_workflow_step_by_step(self, dry_run: bool = True) -> bool:
        """Simulate workflow execution step by step for debugging"""
        self.logger.info("=== SIMULATING WORKFLOW STEP-BY-STEP ===")
        
        workflow_steps = [
            ("System Health Check", "--health-check"),
            ("Post-build Trigger", "--post-build --build-success --dry-run" if dry_run else "--post-build --build-success"),
        ]
        
        all_steps_successful = True
        
        for step_name, args in workflow_steps:
            self.logger.info(f"Simulating: {step_name}")
            
            start_time = time.time()
            command = ['/etc/nixos/scripts/bible_workflow_manager.py'] + args.split()
            
            success, stdout, stderr = self._run_command(command, timeout=120)
            duration = time.time() - start_time
            
            if success:
                self._add_result(
                    f"Simulation: {step_name}",
                    True,
                    f"Step completed successfully ({duration:.2f}s)",
                    {
                        "command": ' '.join(command),
                        "output_preview": stdout[:300] if stdout else "",
                        "execution_time": duration
                    },
                    duration
                )
            else:
                self._add_result(
                    f"Simulation: {step_name}",
                    False,
                    f"Step failed: {stderr[:200]}",
                    {
                        "command": ' '.join(command),
                        "stdout": stdout[:500] if stdout else "",
                        "stderr": stderr[:500] if stderr else "",
                        "execution_time": duration
                    },
                    duration
                )
                all_steps_successful = False
                
                # Don't continue if a step fails
                self.logger.warning(f"Step {step_name} failed - stopping simulation")
                break
        
        return all_steps_successful
    
    def analyze_recent_logs(self, hours: int = 24) -> bool:
        """Analyze recent logs for issues"""
        self.logger.info(f"=== ANALYZING RECENT LOGS ({hours}h) ===")
        
        log_dir = Path(self.config['paths']['logs_directory'])
        if not log_dir.exists():
            self._add_result(
                "Log Analysis",
                False,
                "Log directory does not exist",
                {"log_directory": str(log_dir)}
            )
            return False
        
        # Find recent log files
        cutoff_time = datetime.now() - timedelta(hours=hours)
        recent_logs = []
        
        for log_file in log_dir.glob("*.log"):
            try:
                if datetime.fromtimestamp(log_file.stat().st_mtime) > cutoff_time:
                    recent_logs.append(log_file)
            except Exception as e:
                self.logger.warning(f"Could not check {log_file}: {e}")
        
        if not recent_logs:
            self._add_result(
                "Recent Logs",
                True,
                f"No log files found from last {hours} hours",
                {"log_directory": str(log_dir), "hours": hours}
            )
            return True
        
        # Analyze log contents
        error_count = 0
        warning_count = 0
        total_lines = 0
        
        for log_file in recent_logs:
            try:
                with open(log_file, 'r') as f:
                    for line in f:
                        total_lines += 1
                        line_lower = line.lower()
                        if 'error' in line_lower or 'failed' in line_lower or 'exception' in line_lower:
                            error_count += 1
                        elif 'warning' in line_lower or 'warn' in line_lower:
                            warning_count += 1
            except Exception as e:
                self.logger.warning(f"Could not read {log_file}: {e}")
        
        self._add_result(
            "Log Analysis",
            error_count == 0,
            f"Analyzed {len(recent_logs)} files, {total_lines} lines: {error_count} errors, {warning_count} warnings",
            {
                "log_files": [str(f) for f in recent_logs],
                "total_lines": total_lines,
                "error_count": error_count,
                "warning_count": warning_count,
                "hours_analyzed": hours
            }
        )
        
        return error_count == 0
    
    def generate_diagnostic_report(self) -> Dict[str, Any]:
        """Generate comprehensive diagnostic report"""
        total_tests = len(self.results)
        passed_tests = len([r for r in self.results if r.success])
        failed_tests = total_tests - passed_tests
        
        # Calculate average duration
        avg_duration = sum(r.duration for r in self.results) / total_tests if total_tests > 0 else 0
        
        # Group results by category
        results_by_category = {}
        for result in self.results:
            category = result.test_name.split(':')[0] if ':' in result.test_name else 'General'
            if category not in results_by_category:
                results_by_category[category] = []
            results_by_category[category].append(result)
        
        report = {
            "timestamp": datetime.now().isoformat(),
            "summary": {
                "total_tests": total_tests,
                "passed": passed_tests,
                "failed": failed_tests,
                "success_rate": (passed_tests / total_tests * 100) if total_tests > 0 else 0,
                "average_duration": avg_duration,
                "overall_status": "HEALTHY" if failed_tests == 0 else "DEGRADED" if failed_tests < 3 else "CRITICAL"
            },
            "results_by_category": {},
            "failed_tests": [],
            "recommendations": []
        }
        
        # Process results by category
        for category, results in results_by_category.items():
            category_passed = len([r for r in results if r.success])
            category_total = len(results)
            
            report["results_by_category"][category] = {
                "total": category_total,
                "passed": category_passed,
                "failed": category_total - category_passed,
                "success_rate": (category_passed / category_total * 100) if category_total > 0 else 0,
                "tests": [
                    {
                        "name": r.test_name,
                        "success": r.success,
                        "message": r.message,
                        "duration": r.duration,
                        "timestamp": r.timestamp.isoformat()
                    } for r in results
                ]
            }
        
        # Collect failed tests and recommendations
        for result in self.results:
            if not result.success:
                report["failed_tests"].append({
                    "test": result.test_name,
                    "message": result.message,
                    "details": result.details
                })
                
                # Generate recommendations based on failures
                if "Component:" in result.test_name:
                    report["recommendations"].append(f"Check component installation: {result.test_name}")
                elif "Dependency:" in result.test_name:
                    report["recommendations"].append(f"Install missing dependency: {result.test_name}")
                elif "Path:" in result.test_name:
                    report["recommendations"].append(f"Fix file system issue: {result.test_name}")
                elif "Ollama" in result.test_name:
                    report["recommendations"].append("Check Ollama service configuration and model availability")
                elif "Git" in result.test_name:
                    report["recommendations"].append("Fix git repository or hook configuration")
        
        # Add general recommendations
        if failed_tests > 0:
            report["recommendations"].extend([
                "Run 'bible_system_validator.py --health-check' for detailed system validation",
                "Check system logs for additional error details",
                "Consider running 'bible_system_installer.py' to fix configuration issues"
            ])
        
        return report
    
    def print_diagnostic_summary(self):
        """Print diagnostic summary to console"""
        if not self.results:
            print("No diagnostic tests have been run.")
            return
        
        report = self.generate_diagnostic_report()
        summary = report["summary"]
        
        print("\n" + "="*70)
        print("BIBLE SYSTEM DIAGNOSTIC SUMMARY")
        print("="*70)
        print(f"Overall Status: {summary['overall_status']}")
        print(f"Tests Run: {summary['total_tests']}")
        print(f"Passed: {summary['passed']} ({summary['success_rate']:.1f}%)")
        print(f"Failed: {summary['failed']}")
        print(f"Average Test Duration: {summary['average_duration']:.2f}s")
        
        # Show results by category
        print(f"\nResults by Category:")
        for category, data in report["results_by_category"].items():
            status = "✓" if data["failed"] == 0 else "✗"
            print(f"  {status} {category}: {data['passed']}/{data['total']} passed")
        
        # Show failed tests
        if report["failed_tests"]:
            print(f"\nFailed Tests:")
            for failure in report["failed_tests"]:
                print(f"  ✗ {failure['test']}: {failure['message']}")
        
        # Show recommendations
        if report["recommendations"]:
            print(f"\nRecommendations:")
            for i, rec in enumerate(set(report["recommendations"]), 1):
                print(f"  {i}. {rec}")
        
        print("\n" + "="*70)
    
    def run_comprehensive_diagnostics(self, dry_run: bool = True) -> bool:
        """Run all diagnostic tests"""
        self.logger.info("🔍 STARTING COMPREHENSIVE DIAGNOSTICS")
        
        diagnostic_tests = [
            ("Component Connectivity", self.test_component_connectivity),
            ("System Dependencies", self.test_system_dependencies),
            ("File System Integrity", self.test_file_system_integrity),
            ("AI System Connectivity", self.test_ai_system_connectivity),
            ("Git Integration", self.test_git_integration),
            ("Recent Log Analysis", lambda: self.analyze_recent_logs(24)),
            ("Workflow Execution", lambda: self.test_workflow_execution(dry_run)),
            ("Step-by-step Simulation", lambda: self.simulate_workflow_step_by_step(dry_run))
        ]
        
        overall_success = True
        
        for test_name, test_func in diagnostic_tests:
            self.logger.info(f"\nRunning: {test_name}")
            try:
                if not test_func():
                    overall_success = False
            except Exception as e:
                self.logger.error(f"Diagnostic test {test_name} failed with exception: {e}")
                self._add_result(
                    f"Exception: {test_name}",
                    False,
                    f"Test failed with exception: {str(e)}",
                    {"exception": str(e)}
                )
                overall_success = False
        
        return overall_success

def main():
    """Main debug toolkit entry point"""
    parser = argparse.ArgumentParser(description="Bible Debug Toolkit - Agent 7")
    parser.add_argument(
        "--config", 
        default="/etc/nixos/config/bible_system_config.yaml",
        help="Configuration file path"
    )
    
    # Test categories
    parser.add_argument("--test-components", action="store_true", help="Test component connectivity")
    parser.add_argument("--test-dependencies", action="store_true", help="Test system dependencies")
    parser.add_argument("--test-filesystem", action="store_true", help="Test file system integrity")
    parser.add_argument("--test-ai", action="store_true", help="Test AI system connectivity")
    parser.add_argument("--test-git", action="store_true", help="Test git integration")
    parser.add_argument("--test-workflow", action="store_true", help="Test workflow execution")
    parser.add_argument("--analyze-logs", type=int, metavar="HOURS", help="Analyze logs from last N hours")
    parser.add_argument("--simulate", action="store_true", help="Simulate workflow step-by-step")
    
    # Comprehensive testing
    parser.add_argument("--comprehensive", action="store_true", help="Run all diagnostic tests")
    
    # Output options
    parser.add_argument("--report", help="Save detailed report to JSON file")
    parser.add_argument("--dry-run", action="store_true", help="Use dry-run mode for workflow tests")
    parser.add_argument("--verbose", action="store_true", help="Enable verbose output")
    
    args = parser.parse_args()
    
    # Initialize debug toolkit
    toolkit = BibleDebugToolkit(args.config)
    
    if args.verbose:
        toolkit.logger.setLevel(logging.DEBUG)
    
    # Run specific tests or comprehensive diagnostics
    success = True
    
    if args.comprehensive:
        success = toolkit.run_comprehensive_diagnostics(args.dry_run)
    else:
        # Run individual tests
        if args.test_components:
            success &= toolkit.test_component_connectivity()
        if args.test_dependencies:
            success &= toolkit.test_system_dependencies()
        if args.test_filesystem:
            success &= toolkit.test_file_system_integrity()
        if args.test_ai:
            success &= toolkit.test_ai_system_connectivity()
        if args.test_git:
            success &= toolkit.test_git_integration()
        if args.test_workflow:
            success &= toolkit.test_workflow_execution(args.dry_run)
        if args.analyze_logs:
            success &= toolkit.analyze_recent_logs(args.analyze_logs)
        if args.simulate:
            success &= toolkit.simulate_workflow_step_by_step(args.dry_run)
        
        # If no specific tests requested, show help
        if not any([args.test_components, args.test_dependencies, args.test_filesystem, 
                   args.test_ai, args.test_git, args.test_workflow, args.analyze_logs, args.simulate]):
            parser.print_help()
            return 0
    
    # Generate and save report if requested
    if args.report:
        report = toolkit.generate_diagnostic_report()
        try:
            with open(args.report, 'w') as f:
                json.dump(report, f, indent=2, default=str)
            print(f"\nDetailed report saved to: {args.report}")
        except Exception as e:
            print(f"Could not save report: {e}")
    
    # Print summary
    toolkit.print_diagnostic_summary()
    
    return 0 if success else 1

if __name__ == "__main__":
    sys.exit(main())
EOF < /dev/null