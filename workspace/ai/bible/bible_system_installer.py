#\!/usr/bin/env python3
"""
AI Bible Documentation System - Installer & Setup Script
Agent 8: Configuration & Deployment System

This script automates the installation and setup of the AI Bible Documentation System
for the NixOS homeserver environment.
"""

import os
import sys
import yaml
import json
import shutil
import logging
import argparse
import subprocess
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional
from datetime import datetime

class BibleSystemInstaller:
    """Automated installer for the AI Bible Documentation System"""
    
    def __init__(self, config_path: str = "/etc/nixos/config/bible_system_config.yaml"):
        """Initialize installer with configuration"""
        self.config_path = Path(config_path)
        self.config = self._load_config()
        self.base_dir = Path(self.config['paths']['base_directory'])
        self.success_count = 0
        self.error_count = 0
        self.warnings = []
        
        # Setup logging
        self._setup_logging()
        
    def _load_config(self) -> Dict[str, Any]:
        """Load system configuration"""
        try:
            with open(self.config_path, 'r') as f:
                return yaml.safe_load(f)
        except FileNotFoundError:
            self._fatal_error(f"Configuration file not found: {self.config_path}")
        except yaml.YAMLError as e:
            self._fatal_error(f"Invalid YAML configuration: {e}")
    
    def _setup_logging(self):
        """Setup logging configuration"""
        log_dir = Path(self.config['paths']['logs_directory'])
        log_dir.mkdir(parents=True, exist_ok=True)
        
        log_file = log_dir / f"bible_installer_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
        
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(log_file),
                logging.StreamHandler(sys.stdout)
            ]
        )
        self.logger = logging.getLogger(__name__)
        self.logger.info("AI Bible System Installer - Agent 8")
        self.logger.info(f"Configuration: {self.config_path}")
        self.logger.info(f"Log file: {log_file}")
    
    def _fatal_error(self, message: str):
        """Handle fatal errors"""
        print(f"FATAL ERROR: {message}")
        sys.exit(1)
    
    def _run_command(self, command: List[str], description: str) -> Tuple[bool, str]:
        """Run system command with error handling"""
        try:
            self.logger.info(f"Running: {description}")
            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                timeout=300
            )
            
            if result.returncode == 0:
                self.logger.info(f"Success: {description}")
                return True, result.stdout
            else:
                self.logger.error(f"Failed: {description} - {result.stderr}")
                return False, result.stderr
                
        except subprocess.TimeoutExpired:
            self.logger.error(f"Timeout: {description}")
            return False, "Command timeout"
        except Exception as e:
            self.logger.error(f"Exception in {description}: {e}")
            return False, str(e)
    
    def validate_prerequisites(self) -> bool:
        """Validate system prerequisites"""
        self.logger.info("=== VALIDATING PREREQUISITES ===")
        
        prerequisites = [
            ("Python 3.8+", self._check_python_version),
            ("NixOS system", self._check_nixos),
            ("Git repository", self._check_git_repo),
            ("Ollama service", self._check_ollama),
            ("File permissions", self._check_permissions),
            ("Disk space", self._check_disk_space)
        ]
        
        all_valid = True
        for name, check_func in prerequisites:
            try:
                if check_func():
                    self.logger.info(f"✓ {name}")
                    self.success_count += 1
                else:
                    self.logger.error(f"✗ {name}")
                    self.error_count += 1
                    all_valid = False
            except Exception as e:
                self.logger.error(f"✗ {name}: {e}")
                self.error_count += 1
                all_valid = False
        
        if all_valid:
            self.logger.info("All prerequisites satisfied")
        else:
            self.logger.error(f"Prerequisites failed: {self.error_count} errors")
        
        return all_valid
    
    def _check_python_version(self) -> bool:
        """Check Python version"""
        version = sys.version_info
        return version.major >= 3 and version.minor >= 8
    
    def _check_nixos(self) -> bool:
        """Check if running on NixOS"""
        return Path("/etc/nixos").exists() and Path("/run/current-system").exists()
    
    def _check_git_repo(self) -> bool:
        """Check if base directory is a git repository"""
        return (self.base_dir / ".git").exists()
    
    def _check_ollama(self) -> bool:
        """Check if Ollama service is available"""
        success, _ = self._run_command(
            ["systemctl", "is-active", "ollama"],
            "Check Ollama service status"
        )
        return success
    
    def _check_permissions(self) -> bool:
        """Check file system permissions"""
        test_dirs = [
            self.config['paths']['docs_directory'],
            self.config['paths']['scripts_directory'],
            self.config['paths']['config_directory']
        ]
        
        for dir_path in test_dirs:
            path = Path(dir_path)
            if not path.exists():
                continue
            if not os.access(path, os.W_OK):
                return False
        return True
    
    def _check_disk_space(self) -> bool:
        """Check available disk space"""
        stat = shutil.disk_usage(self.base_dir)
        free_gb = stat.free / (1024**3)
        return free_gb >= 1.0  # Require at least 1GB free
    
    def create_directory_structure(self) -> bool:
        """Create required directory structure"""
        self.logger.info("=== CREATING DIRECTORY STRUCTURE ===")
        
        directories = [
            self.config['paths']['bibles_directory'],
            self.config['paths']['backups_directory'],
            self.config['paths']['archive_directory'],
            self.config['paths']['logs_directory']
        ]
        
        success = True
        for dir_path in directories:
            try:
                path = Path(dir_path)
                path.mkdir(parents=True, exist_ok=True)
                
                # Set proper permissions
                os.chmod(path, int(self.config['security']['access_control']['directory_permissions'], 8))
                
                self.logger.info(f"✓ Created: {dir_path}")
                self.success_count += 1
                
            except Exception as e:
                self.logger.error(f"✗ Failed to create {dir_path}: {e}")
                self.error_count += 1
                success = False
        
        return success
    
    def install_bible_template(self) -> bool:
        """Install bible template if it doesn't exist"""
        self.logger.info("=== INSTALLING BIBLE TEMPLATE ===")
        
        template_path = Path(self.config['paths']['bible_template'])
        
        if template_path.exists():
            self.logger.info(f"✓ Bible template already exists: {template_path}")
            return True
        
        # Template should already exist from git pull, but verify
        if not template_path.exists():
            self.logger.warning(f"Bible template not found: {template_path}")
            self.warnings.append("Bible template missing - may need manual creation")
            return False
        
        return True
    
    def configure_systemd_service(self) -> bool:
        """Configure systemd service for bible system"""
        self.logger.info("=== CONFIGURING SYSTEMD SERVICE ===")
        
        service_config = self._generate_systemd_service()
        service_path = Path("/etc/systemd/system/bible-system.service")
        
        try:
            with open(service_path, 'w') as f:
                f.write(service_config)
            
            os.chmod(service_path, 0o644)
            
            # Reload systemd and enable service
            success, _ = self._run_command(
                ["systemctl", "daemon-reload"],
                "Reload systemd configuration"
            )
            
            if success and self.config['integration']['systemd']['service_enabled']:
                success, _ = self._run_command(
                    ["systemctl", "enable", "bible-system.service"],
                    "Enable bible-system service"
                )
            
            if success:
                self.logger.info("✓ Systemd service configured")
                self.success_count += 1
                return True
            else:
                self.logger.error("✗ Failed to configure systemd service")
                self.error_count += 1
                return False
                
        except Exception as e:
            self.logger.error(f"✗ Systemd service configuration failed: {e}")
            self.error_count += 1
            return False
    
    def _generate_systemd_service(self) -> str:
        """Generate systemd service configuration"""
        return f"""[Unit]
Description=AI Bible Documentation System
After=ollama.service
Requires=ollama.service
PartOf=multi-user.target

[Service]
Type=oneshot
RemainAfterExit=yes
User=root
WorkingDirectory={self.config['paths']['base_directory']}
Environment=PYTHONPATH={self.config['paths']['scripts_directory']}
ExecStart={self.config['paths']['scripts_directory']}/bible_system_validator.py --health-check
ExecReload={self.config['paths']['scripts_directory']}/bible_system_validator.py --full-validation
StandardOutput=journal
StandardError=journal
Restart=no

[Install]
WantedBy=multi-user.target
"""
    
    def setup_git_integration(self) -> bool:
        """Setup git hooks for bible system"""
        self.logger.info("=== SETTING UP GIT INTEGRATION ===")
        
        if not self.config['integration']['git']['enabled']:
            self.logger.info("Git integration disabled in config")
            return True
        
        hooks_dir = Path(self.config['paths']['git_hooks'])
        
        # Check if post-commit hook exists
        post_commit_hook = hooks_dir / "post-commit"
        
        if post_commit_hook.exists():
            self.logger.info("✓ Git post-commit hook already exists")
            
            # Verify it includes bible system integration
            with open(post_commit_hook, 'r') as f:
                content = f.read()
                if "bible" in content.lower():
                    self.logger.info("✓ Bible system integration found in git hook")
                    self.success_count += 1
                    return True
                else:
                    self.warnings.append("Git hook exists but may not include bible system integration")
        
        return True
    
    def validate_ai_model(self) -> bool:
        """Validate AI model availability"""
        self.logger.info("=== VALIDATING AI MODEL ===")
        
        model_name = self.config['ai_system']['model']['name']
        endpoint = self.config['ai_system']['model']['endpoint']
        
        # Check if Ollama is running
        success, _ = self._run_command(
            ["ollama", "list"],
            f"Check available Ollama models"
        )
        
        if success:
            self.logger.info("✓ Ollama service accessible")
            
            # Check specific model
            success, output = self._run_command(
                ["ollama", "show", model_name],
                f"Verify model {model_name}"
            )
            
            if success:
                self.logger.info(f"✓ Model {model_name} available")
                self.success_count += 1
                return True
            else:
                self.logger.warning(f"Model {model_name} not found - may need to be pulled")
                self.warnings.append(f"AI model {model_name} needs to be installed")
                return False
        else:
            self.logger.error("✗ Ollama service not accessible")
            self.error_count += 1
            return False
    
    def create_initial_bibles(self) -> bool:
        """Create initial bible files if they don't exist"""
        self.logger.info("=== CREATING INITIAL BIBLE FILES ===")
        
        bibles_dir = Path(self.config['paths']['bibles_directory'])
        categories_config = self._load_bible_categories()
        
        success = True
        for category_key, category_data in categories_config['bible_categories'].items():
            bible_filename = category_data['filename']
            bible_path = bibles_dir / bible_filename
            
            if not bible_path.exists():
                # Create initial bible from template
                template_path = Path(self.config['paths']['bible_template'])
                if template_path.exists():
                    try:
                        with open(template_path, 'r') as f:
                            template_content = f.read()
                        
                        # Replace template placeholders
                        bible_content = template_content.replace(
                            "[Bible Name]", category_data['name']
                        ).replace(
                            "[Clear definition of the main functional area this bible addresses]",
                            category_data['description']
                        )
                        
                        with open(bible_path, 'w') as f:
                            f.write(bible_content)
                        
                        os.chmod(bible_path, int(self.config['security']['access_control']['file_permissions'], 8))
                        
                        self.logger.info(f"✓ Created initial bible: {bible_filename}")
                        self.success_count += 1
                        
                    except Exception as e:
                        self.logger.error(f"✗ Failed to create {bible_filename}: {e}")
                        self.error_count += 1
                        success = False
                else:
                    self.logger.warning(f"Template not found, skipping {bible_filename}")
                    self.warnings.append(f"Could not create {bible_filename} - template missing")
            else:
                self.logger.info(f"✓ Bible already exists: {bible_filename}")
        
        return success
    
    def _load_bible_categories(self) -> Dict[str, Any]:
        """Load bible categories configuration"""
        categories_path = Path(self.config['paths']['bible_categories'])
        with open(categories_path, 'r') as f:
            return yaml.safe_load(f)
    
    def run_installation(self, skip_validation: bool = False) -> bool:
        """Run complete installation process"""
        self.logger.info("🚀 STARTING AI BIBLE SYSTEM INSTALLATION")
        self.logger.info(f"Target: {self.config['system']['deployment_target']}")
        self.logger.info(f"Version: {self.config['system']['version']}")
        
        installation_steps = [
            ("Prerequisites Validation", lambda: skip_validation or self.validate_prerequisites()),
            ("Directory Structure", self.create_directory_structure),
            ("Bible Template", self.install_bible_template),
            ("Systemd Service", self.configure_systemd_service),
            ("Git Integration", self.setup_git_integration),
            ("AI Model Validation", self.validate_ai_model),
            ("Initial Bible Files", self.create_initial_bibles)
        ]
        
        overall_success = True
        
        for step_name, step_func in installation_steps:
            self.logger.info(f"\n--- {step_name} ---")
            try:
                if not step_func():
                    self.logger.error(f"❌ {step_name} failed")
                    overall_success = False
                else:
                    self.logger.info(f"✅ {step_name} completed")
            except Exception as e:
                self.logger.error(f"❌ {step_name} exception: {e}")
                self.error_count += 1
                overall_success = False
        
        # Installation summary
        self.logger.info("\n" + "="*60)
        self.logger.info("INSTALLATION SUMMARY")
        self.logger.info("="*60)
        self.logger.info(f"✅ Successful operations: {self.success_count}")
        self.logger.info(f"❌ Failed operations: {self.error_count}")
        self.logger.info(f"⚠️  Warnings: {len(self.warnings)}")
        
        if self.warnings:
            self.logger.info("\nWarnings:")
            for warning in self.warnings:
                self.logger.info(f"  ⚠️  {warning}")
        
        if overall_success:
            self.logger.info("\n🎉 AI BIBLE SYSTEM INSTALLATION COMPLETED SUCCESSFULLY")
            self.logger.info("\nNext Steps:")
            self.logger.info("1. Run: bible_system_validator.py --full-validation")
            self.logger.info("2. Consider starting: systemctl start bible-system")
            self.logger.info("3. Review warnings if any")
        else:
            self.logger.error("\n💥 INSTALLATION COMPLETED WITH ERRORS")
            self.logger.error("Please review the errors above and retry installation")
        
        return overall_success
    
    def uninstall_system(self) -> bool:
        """Uninstall bible system (for development/testing)"""
        self.logger.info("🗑️  UNINSTALLING AI BIBLE SYSTEM")
        
        # Stop and disable service
        self._run_command(
            ["systemctl", "stop", "bible-system.service"],
            "Stop bible system service"
        )
        self._run_command(
            ["systemctl", "disable", "bible-system.service"],
            "Disable bible system service"
        )
        
        # Remove systemd service file
        service_path = Path("/etc/systemd/system/bible-system.service")
        if service_path.exists():
            service_path.unlink()
            self._run_command(
                ["systemctl", "daemon-reload"],
                "Reload systemd after service removal"
            )
        
        self.logger.info("✅ Uninstall completed")
        return True

def main():
    """Main installer entry point"""
    parser = argparse.ArgumentParser(description="AI Bible System Installer - Agent 8")
    parser.add_argument(
        "--config", 
        default="/etc/nixos/config/bible_system_config.yaml",
        help="Configuration file path"
    )
    parser.add_argument(
        "--skip-validation",
        action="store_true",
        help="Skip prerequisite validation"
    )
    parser.add_argument(
        "--uninstall",
        action="store_true",
        help="Uninstall the bible system"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be done without making changes"
    )
    
    args = parser.parse_args()
    
    if args.dry_run:
        print("DRY RUN MODE - No changes will be made")
        return
    
    # Initialize installer
    installer = BibleSystemInstaller(args.config)
    
    if args.uninstall:
        success = installer.uninstall_system()
    else:
        success = installer.run_installation(args.skip_validation)
    
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
EOF < /dev/null