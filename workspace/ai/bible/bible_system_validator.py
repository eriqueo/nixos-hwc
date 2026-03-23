#\!/usr/bin/env python3
"""
AI Bible Documentation System - Validation & Health Check Tool
Agent 8: Configuration & Deployment System

This script validates the bible system configuration, health, and integrity.
"""

import os
import sys
import yaml
import json
import requests
import subprocess
import argparse
import logging
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional, NamedTuple
from datetime import datetime, timedelta
from dataclasses import dataclass

@dataclass
class ValidationResult:
    """Validation result data structure"""
    component: str
    status: str  # "pass", "fail", "warning"
    message: str
    details: Optional[Dict[str, Any]] = None
    timestamp: datetime = datetime.now()

class BibleSystemValidator:
    """Comprehensive validator for AI Bible Documentation System"""
    
    def __init__(self, config_path: str = "/etc/nixos/config/bible_system_config.yaml"):
        """Initialize validator with configuration"""
        self.config_path = Path(config_path)
        self.config = self._load_config()
        self.base_dir = Path(self.config['paths']['base_directory'])
        self.results: List[ValidationResult] = []
        
        # Setup logging
        self._setup_logging()
        
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
        """Setup logging configuration"""
        log_dir = Path(self.config['paths']['logs_directory'])
        log_dir.mkdir(parents=True, exist_ok=True)
        
        log_file = log_dir / f"bible_validator_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
        
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(log_file),
                logging.StreamHandler(sys.stdout)
            ]
        )
        self.logger = logging.getLogger(__name__)
        self.logger.info("Bible System Validator - Agent 8")
        self.logger.info(f"Configuration: {self.config_path}")
        
    def _run_command(self, command: List[str], timeout: int = 30) -> Tuple[bool, str, str]:
        """Run system command with timeout"""
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
    
    def _add_result(self, component: str, status: str, message: str, details: Optional[Dict] = None):
        """Add validation result"""
        result = ValidationResult(component, status, message, details)
        self.results.append(result)
        
        # Log result
        log_level = {
            "pass": self.logger.info,
            "warning": self.logger.warning,
            "fail": self.logger.error
        }.get(status, self.logger.info)
        
        log_level(f"{component}: {message}")
    
    def validate_configuration_files(self) -> bool:
        """Validate all configuration files"""
        self.logger.info("=== VALIDATING CONFIGURATION FILES ===")
        
        config_files = [
            (self.config['paths']['bible_categories'], "Bible Categories Config"),
            (self.config_path, "Main System Config")
        ]
        
        all_valid = True
        
        for file_path, description in config_files:
            path = Path(file_path)
            
            if not path.exists():
                self._add_result(description, "fail", f"File not found: {file_path}")
                all_valid = False
                continue
            
            try:
                with open(path, 'r') as f:
                    if path.suffix in ['.yaml', '.yml']:
                        yaml.safe_load(f)
                    elif path.suffix == '.json':
                        json.load(f)
                
                # Check file permissions
                actual_perms = oct(path.stat().st_mode)[-3:]
                expected_perms = self.config['security']['access_control']['config_permissions']
                
                if actual_perms == expected_perms:
                    self._add_result(description, "pass", f"Valid configuration with correct permissions")
                else:
                    self._add_result(description, "warning", 
                                   f"Valid config but permissions {actual_perms} \!= {expected_perms}")
                
            except Exception as e:
                self._add_result(description, "fail", f"Invalid configuration: {e}")
                all_valid = False
        
        return all_valid
    
    def validate_directory_structure(self) -> bool:
        """Validate required directory structure"""
        self.logger.info("=== VALIDATING DIRECTORY STRUCTURE ===")
        
        required_dirs = [
            (self.config['paths']['docs_directory'], "Documentation Directory"),
            (self.config['paths']['bibles_directory'], "Bibles Directory"),
            (self.config['paths']['scripts_directory'], "Scripts Directory"),
            (self.config['paths']['config_directory'], "Config Directory"),
            (self.config['paths']['backups_directory'], "Backups Directory"),
            (self.config['paths']['logs_directory'], "Logs Directory")
        ]
        
        all_valid = True
        
        for dir_path, description in required_dirs:
            path = Path(dir_path)
            
            if not path.exists():
                self._add_result(description, "fail", f"Directory not found: {dir_path}")
                all_valid = False
                continue
            
            if not path.is_dir():
                self._add_result(description, "fail", f"Path exists but is not a directory: {dir_path}")
                all_valid = False
                continue
            
            # Check permissions
            if not os.access(path, os.R_OK | os.W_OK):
                self._add_result(description, "fail", f"Insufficient permissions: {dir_path}")
                all_valid = False
                continue
            
            self._add_result(description, "pass", f"Directory exists with proper access")
        
        return all_valid
    
    def validate_bible_files(self) -> bool:
        """Validate bible files structure and content"""
        self.logger.info("=== VALIDATING BIBLE FILES ===")
        
        try:
            # Load bible categories
            categories_path = Path(self.config['paths']['bible_categories'])
            with open(categories_path, 'r') as f:
                categories = yaml.safe_load(f)
            
            bibles_dir = Path(self.config['paths']['bibles_directory'])
            all_valid = True
            
            for category_key, category_data in categories['bible_categories'].items():
                bible_filename = category_data['filename']
                bible_path = bibles_dir / bible_filename
                
                if not bible_path.exists():
                    self._add_result(f"Bible: {bible_filename}", "warning", 
                                   f"Bible file not found (may need migration): {bible_path}")
                    continue
                
                # Validate bible content structure
                try:
                    with open(bible_path, 'r') as f:
                        content = f.read()
                    
                    # Check for required sections
                    required_sections = [
                        "## 🎯 Bible Scope",
                        "## 🏗️ Architecture Overview", 
                        "## 📋 Configuration Reference",
                        "## 🔧 Operational Procedures",
                        "## 📊 Monitoring & Validation"
                    ]
                    
                    missing_sections = []
                    for section in required_sections:
                        if section not in content:
                            missing_sections.append(section)
                    
                    if missing_sections:
                        self._add_result(f"Bible: {bible_filename}", "warning",
                                       f"Missing sections: {missing_sections}")
                    else:
                        self._add_result(f"Bible: {bible_filename}", "pass",
                                       "All required sections present")
                    
                except Exception as e:
                    self._add_result(f"Bible: {bible_filename}", "fail",
                                   f"Error reading bible file: {e}")
                    all_valid = False
            
            return all_valid
            
        except Exception as e:
            self._add_result("Bible Files", "fail", f"Error validating bibles: {e}")
            return False
    
    def validate_ai_system(self) -> bool:
        """Validate AI system connectivity and model availability"""
        self.logger.info("=== VALIDATING AI SYSTEM ===")
        
        # Check Ollama service
        success, stdout, stderr = self._run_command(["systemctl", "is-active", "ollama"])
        
        if not success:
            self._add_result("Ollama Service", "fail", f"Service not active: {stderr}")
            return False
        
        self._add_result("Ollama Service", "pass", "Service is active")
        
        # Check model availability
        model_name = self.config['ai_system']['model']['name']
        success, stdout, stderr = self._run_command(["ollama", "list"])
        
        if success and model_name in stdout:
            self._add_result("AI Model", "pass", f"Model {model_name} is available")
            
            # Test model connectivity
            try:
                endpoint = self.config['ai_system']['model']['endpoint']
                response = requests.get(f"{endpoint}/api/tags", timeout=10)
                
                if response.status_code == 200:
                    self._add_result("AI Endpoint", "pass", "API endpoint responding")
                    return True
                else:
                    self._add_result("AI Endpoint", "fail", 
                                   f"API returned status {response.status_code}")
                    return False
                    
            except Exception as e:
                self._add_result("AI Endpoint", "fail", f"API connection failed: {e}")
                return False
        else:
            self._add_result("AI Model", "fail", 
                           f"Model {model_name} not found. Available: {stdout}")
            return False
    
    def validate_git_integration(self) -> bool:
        """Validate git repository and integration"""
        self.logger.info("=== VALIDATING GIT INTEGRATION ===")
        
        # Check if we're in a git repository
        success, stdout, stderr = self._run_command(["git", "rev-parse", "--git-dir"])
        
        if not success:
            self._add_result("Git Repository", "fail", "Not a git repository")
            return False
        
        self._add_result("Git Repository", "pass", "Repository detected")
        
        # Check git status
        success, stdout, stderr = self._run_command(["git", "status", "--porcelain"])
        
        if success:
            if stdout.strip():
                self._add_result("Git Status", "warning", "Uncommitted changes detected")
            else:
                self._add_result("Git Status", "pass", "Working directory clean")
        
        # Check post-commit hook
        hooks_dir = Path(self.config['paths']['git_hooks'])
        post_commit_hook = hooks_dir / "post-commit"
        
        if post_commit_hook.exists() and os.access(post_commit_hook, os.X_OK):
            self._add_result("Git Hook", "pass", "Post-commit hook exists and executable")
        else:
            self._add_result("Git Hook", "warning", "Post-commit hook missing or not executable")
        
        return True
    
    def validate_systemd_service(self) -> bool:
        """Validate systemd service configuration"""
        self.logger.info("=== VALIDATING SYSTEMD SERVICE ===")
        
        service_name = self.config['integration']['systemd']['service_name']
        service_file = f"{service_name}.service"
        
        # Check if service file exists
        service_path = Path("/etc/systemd/system") / service_file
        
        if not service_path.exists():
            self._add_result("Systemd Service", "warning", 
                           f"Service file not found: {service_path}")
            return False
        
        # Check service status
        success, stdout, stderr = self._run_command(
            ["systemctl", "is-enabled", service_file]
        )
        
        if success and "enabled" in stdout:
            self._add_result("Systemd Service", "pass", "Service is enabled")
        else:
            self._add_result("Systemd Service", "warning", 
                           f"Service not enabled: {stdout}")
        
        # Check if service can be loaded
        success, stdout, stderr = self._run_command(
            ["systemctl", "status", service_file]
        )
        
        if "could not be found" in stderr:
            self._add_result("Systemd Service", "fail", "Service could not be loaded")
            return False
        else:
            self._add_result("Systemd Service", "pass", "Service configuration valid")
            return True
    
    def validate_system_resources(self) -> bool:
        """Validate system resources and capacity"""
        self.logger.info("=== VALIDATING SYSTEM RESOURCES ===")
        
        # Check disk space
        import shutil
        try:
            stat = shutil.disk_usage(self.base_dir)
            free_gb = stat.free / (1024**3)
            total_gb = stat.total / (1024**3)
            usage_percent = ((stat.total - stat.free) / stat.total) * 100
            
            if free_gb >= 1.0:
                self._add_result("Disk Space", "pass", 
                               f"{free_gb:.1f}GB free ({usage_percent:.1f}% used)")
            else:
                self._add_result("Disk Space", "warning", 
                               f"Low disk space: {free_gb:.1f}GB free")
            
        except Exception as e:
            self._add_result("Disk Space", "fail", f"Error checking disk space: {e}")
        
        # Check memory usage
        try:
            with open('/proc/meminfo', 'r') as f:
                meminfo = f.read()
            
            mem_total = int([line for line in meminfo.split('\n') if 'MemTotal:' in line][0].split()[1]) / 1024
            mem_available = int([line for line in meminfo.split('\n') if 'MemAvailable:' in line][0].split()[1]) / 1024
            
            if mem_available >= 512:  # 512 MB minimum
                self._add_result("Memory", "pass", 
                               f"{mem_available:.0f}MB available of {mem_total:.0f}MB")
            else:
                self._add_result("Memory", "warning", 
                               f"Low memory: {mem_available:.0f}MB available")
                
        except Exception as e:
            self._add_result("Memory", "warning", f"Error checking memory: {e}")
        
        return True
    
    def validate_cross_bible_consistency(self) -> bool:
        """Validate cross-bible consistency rules"""
        self.logger.info("=== VALIDATING CROSS-BIBLE CONSISTENCY ===")
        
        try:
            # Load bible categories for consistency rules
            categories_path = Path(self.config['paths']['bible_categories'])
            with open(categories_path, 'r') as f:
                categories = yaml.safe_load(f)
            
            consistency_rules = categories.get('consistency_rules', {})
            
            if not consistency_rules:
                self._add_result("Consistency Rules", "warning", "No consistency rules defined")
                return True
            
            # For now, just validate that the rules are well-formed
            for rule_name, rule_config in consistency_rules.items():
                required_fields = ['source_bible', 'dependent_bibles', 'validation']
                missing_fields = [field for field in required_fields if field not in rule_config]
                
                if missing_fields:
                    self._add_result(f"Rule: {rule_name}", "fail", 
                                   f"Missing fields: {missing_fields}")
                else:
                    self._add_result(f"Rule: {rule_name}", "pass", 
                                   "Rule definition is valid")
            
            return True
            
        except Exception as e:
            self._add_result("Cross-Bible Consistency", "fail", 
                           f"Error validating consistency: {e}")
            return False
    
    def run_health_check(self) -> bool:
        """Run basic health check (fast validation)"""
        self.logger.info("🏥 RUNNING BIBLE SYSTEM HEALTH CHECK")
        
        health_checks = [
            ("Configuration", self.validate_configuration_files),
            ("Directories", self.validate_directory_structure),
            ("AI System", self.validate_ai_system),
            ("Git Integration", self.validate_git_integration),
            ("System Resources", self.validate_system_resources)
        ]
        
        overall_health = True
        
        for check_name, check_func in health_checks:
            try:
                if not check_func():
                    overall_health = False
            except Exception as e:
                self.logger.error(f"Health check {check_name} failed with exception: {e}")
                overall_health = False
        
        return overall_health
    
    def run_full_validation(self) -> bool:
        """Run comprehensive validation (includes all checks)"""
        self.logger.info("🔍 RUNNING FULL BIBLE SYSTEM VALIDATION")
        
        validation_steps = [
            ("Configuration Files", self.validate_configuration_files),
            ("Directory Structure", self.validate_directory_structure),
            ("Bible Files", self.validate_bible_files),
            ("AI System", self.validate_ai_system),
            ("Git Integration", self.validate_git_integration),
            ("Systemd Service", self.validate_systemd_service),
            ("System Resources", self.validate_system_resources),
            ("Cross-Bible Consistency", self.validate_cross_bible_consistency)
        ]
        
        overall_valid = True
        
        for step_name, step_func in validation_steps:
            try:
                if not step_func():
                    overall_valid = False
            except Exception as e:
                self.logger.error(f"Validation step {step_name} failed with exception: {e}")
                overall_valid = False
        
        return overall_valid
    
    def generate_report(self) -> Dict[str, Any]:
        """Generate comprehensive validation report"""
        pass_count = len([r for r in self.results if r.status == "pass"])
        warning_count = len([r for r in self.results if r.status == "warning"])
        fail_count = len([r for r in self.results if r.status == "fail"])
        
        report = {
            "timestamp": datetime.now().isoformat(),
            "system": {
                "name": self.config['system']['name'],
                "version": self.config['system']['version'],
                "deployment_target": self.config['system']['deployment_target']
            },
            "summary": {
                "total_checks": len(self.results),
                "passed": pass_count,
                "warnings": warning_count,
                "failed": fail_count,
                "overall_status": "healthy" if fail_count == 0 else "degraded" if warning_count > 0 else "failed"
            },
            "results": [
                {
                    "component": r.component,
                    "status": r.status,
                    "message": r.message,
                    "timestamp": r.timestamp.isoformat(),
                    "details": r.details
                }
                for r in self.results
            ]
        }
        
        return report
    
    def print_summary(self):
        """Print validation summary to console"""
        pass_count = len([r for r in self.results if r.status == "pass"])
        warning_count = len([r for r in self.results if r.status == "warning"])
        fail_count = len([r for r in self.results if r.status == "fail"])
        
        print("\n" + "="*60)
        print("BIBLE SYSTEM VALIDATION SUMMARY")
        print("="*60)
        print(f"✅ Passed: {pass_count}")
        print(f"⚠️  Warnings: {warning_count}")
        print(f"❌ Failed: {fail_count}")
        print(f"📊 Total: {len(self.results)}")
        
        if fail_count == 0:
            print(f"\n🎉 System Status: HEALTHY")
        elif warning_count > 0:
            print(f"\n⚠️  System Status: DEGRADED (has warnings)")
        else:
            print(f"\n💥 System Status: FAILED")
        
        # Show failures and warnings
        if fail_count > 0:
            print(f"\n❌ FAILURES:")
            for result in self.results:
                if result.status == "fail":
                    print(f"  • {result.component}: {result.message}")
        
        if warning_count > 0:
            print(f"\n⚠️  WARNINGS:")
            for result in self.results:
                if result.status == "warning":
                    print(f"  • {result.component}: {result.message}")

def main():
    """Main validator entry point"""
    parser = argparse.ArgumentParser(description="Bible System Validator - Agent 8")
    parser.add_argument(
        "--config", 
        default="/etc/nixos/config/bible_system_config.yaml",
        help="Configuration file path"
    )
    parser.add_argument(
        "--health-check",
        action="store_true",
        help="Run basic health check only"
    )
    parser.add_argument(
        "--full-validation",
        action="store_true",
        help="Run comprehensive validation"
    )
    parser.add_argument(
        "--report",
        help="Generate JSON report to specified file"
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Suppress verbose output"
    )
    
    args = parser.parse_args()
    
    # Initialize validator
    validator = BibleSystemValidator(args.config)
    
    # Configure quiet mode
    if args.quiet:
        validator.logger.setLevel(logging.ERROR)
    
    # Run appropriate validation
    if args.health_check:
        success = validator.run_health_check()
    elif args.full_validation:
        success = validator.run_full_validation()
    else:
        # Default to health check
        success = validator.run_health_check()
    
    # Generate report if requested
    if args.report:
        report = validator.generate_report()
        with open(args.report, 'w') as f:
            json.dump(report, f, indent=2)
        print(f"Report saved to: {args.report}")
    
    # Print summary
    if not args.quiet:
        validator.print_summary()
    
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
EOF < /dev/null