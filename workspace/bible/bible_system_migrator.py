#\!/usr/bin/env python3
"""
AI Bible Documentation System - Configuration Migration & Upgrade Tool
Agent 8: Configuration & Deployment System

This script handles configuration migration, upgrades, and version management
for the AI Bible Documentation System.
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
from dataclasses import dataclass

@dataclass
class MigrationTask:
    """Migration task definition"""
    name: str
    description: str
    source_version: str
    target_version: str
    required: bool = True
    backup_required: bool = True

class BibleSystemMigrator:
    """Configuration migration and upgrade manager"""
    
    def __init__(self, config_path: str = "/etc/nixos/config/bible_system_config.yaml"):
        """Initialize migrator with configuration"""
        self.config_path = Path(config_path)
        self.config = self._load_config()
        self.base_dir = Path(self.config['paths']['base_directory'])
        self.backup_dir = Path(self.config['paths']['backups_directory']) / "migrations"
        
        # Migration tracking
        self.migration_log = []
        self.current_version = self._get_current_version()
        
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
        
        log_file = log_dir / f"bible_migrator_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
        
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(log_file),
                logging.StreamHandler(sys.stdout)
            ]
        )
        self.logger = logging.getLogger(__name__)
        self.logger.info("Bible System Migrator - Agent 8")
        self.logger.info(f"Current version: {self.current_version}")
        
    def _get_current_version(self) -> str:
        """Get current system version"""
        return self.config.get('system', {}).get('version', '0.0.0')
    
    def _create_backup(self, description: str) -> str:
        """Create system backup before migration"""
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        backup_name = f"pre_migration_{timestamp}_{description.replace(' ', '_')}"
        backup_path = self.backup_dir / backup_name
        
        self.backup_dir.mkdir(parents=True, exist_ok=True)
        
        # Backup critical files
        critical_paths = [
            self.config['paths']['config_directory'],
            self.config['paths']['bibles_directory'],
            self.config['paths']['scripts_directory']
        ]
        
        try:
            for path_str in critical_paths:
                path = Path(path_str)
                if path.exists():
                    backup_target = backup_path / path.name
                    if path.is_dir():
                        shutil.copytree(path, backup_target)
                    else:
                        shutil.copy2(path, backup_target)
            
            self.logger.info(f"Backup created: {backup_path}")
            return str(backup_path)
            
        except Exception as e:
            self.logger.error(f"Backup failed: {e}")
            raise
    
    def _restore_backup(self, backup_path: str):
        """Restore from backup"""
        backup = Path(backup_path)
        if not backup.exists():
            raise FileNotFoundError(f"Backup not found: {backup_path}")
        
        try:
            # Restore critical directories
            for item in backup.iterdir():
                if item.name == "config":
                    target = Path(self.config['paths']['config_directory'])
                elif item.name == "bibles":
                    target = Path(self.config['paths']['bibles_directory'])
                elif item.name == "scripts":
                    target = Path(self.config['paths']['scripts_directory'])
                else:
                    continue
                
                # Remove current and restore backup
                if target.exists():
                    if target.is_dir():
                        shutil.rmtree(target)
                    else:
                        target.unlink()
                
                if item.is_dir():
                    shutil.copytree(item, target)
                else:
                    shutil.copy2(item, target)
            
            self.logger.info(f"Restored from backup: {backup_path}")
            
        except Exception as e:
            self.logger.error(f"Restore failed: {e}")
            raise
    
    def detect_legacy_configuration(self) -> Dict[str, Any]:
        """Detect and analyze legacy configuration"""
        self.logger.info("=== DETECTING LEGACY CONFIGURATION ===")
        
        legacy_analysis = {
            "has_legacy": False,
            "legacy_files": [],
            "migration_required": False,
            "compatibility_issues": []
        }
        
        # Check for old configuration patterns
        legacy_patterns = [
            ("Old AI docs structure", "docs/AI_DOCUMENTATION_*"),
            ("Legacy monitoring files", "docs/MONITORING*.md"),
            ("Old architecture files", "docs/*ARCHITECTURE*.md"),
            ("Completed task logs", "docs/COMPLETED_TASKS_LOG.md"),
            ("Master todo lists", "docs/MASTER_TODO_LIST.md")
        ]
        
        docs_dir = Path(self.config['paths']['docs_directory'])
        
        for pattern_name, pattern in legacy_patterns:
            from pathlib import Path
            import glob
            
            matches = list(docs_dir.glob(pattern.split('/')[-1]))
            if matches:
                legacy_analysis["has_legacy"] = True
                legacy_analysis["legacy_files"].extend([(pattern_name, str(f)) for f in matches])
        
        # Check if bible files need to be created
        bibles_dir = Path(self.config['paths']['bibles_directory'])
        if not any(bibles_dir.glob("*_BIBLE.md")):
            legacy_analysis["migration_required"] = True
            legacy_analysis["compatibility_issues"].append("No bible files found - migration needed")
        
        self.logger.info(f"Legacy analysis: {legacy_analysis}")
        return legacy_analysis
    
    def migrate_legacy_documentation(self) -> bool:
        """Migrate legacy documentation to bible structure"""
        self.logger.info("=== MIGRATING LEGACY DOCUMENTATION ===")
        
        try:
            # Load bible categories to understand target structure
            categories_path = Path(self.config['paths']['bible_categories'])
            with open(categories_path, 'r') as f:
                categories = yaml.safe_load(f)
            
            bibles_dir = Path(self.config['paths']['bibles_directory'])
            bibles_dir.mkdir(parents=True, exist_ok=True)
            
            migration_success = True
            
            # Process each bible category
            for category_key, category_data in categories['bible_categories'].items():
                bible_name = category_data['filename']
                bible_path = bibles_dir / bible_name
                
                self.logger.info(f"Processing {bible_name}")
                
                # If bible doesn't exist, create from template and source files
                if not bible_path.exists():
                    success = self._create_bible_from_sources(category_key, category_data, bible_path)
                    if not success:
                        migration_success = False
                        continue
                
                self.migration_log.append(f"Processed {bible_name}")
            
            # Archive legacy files
            if migration_success:
                self._archive_legacy_files(categories)
            
            return migration_success
            
        except Exception as e:
            self.logger.error(f"Migration failed: {e}")
            return False
    
    def _create_bible_from_sources(self, category_key: str, category_data: Dict, bible_path: Path) -> bool:
        """Create bible file from source documentation"""
        try:
            # Load template
            template_path = Path(self.config['paths']['bible_template'])
            if not template_path.exists():
                self.logger.error(f"Bible template not found: {template_path}")
                return False
            
            with open(template_path, 'r') as f:
                template_content = f.read()
            
            # Replace template placeholders with category-specific information
            bible_content = template_content.replace(
                "[Bible Name]", category_data['name']
            ).replace(
                "[Clear definition of the main functional area this bible addresses]",
                category_data['description']
            )
            
            # Add scope information
            if 'scope' in category_data:
                scope_text = "\n".join([f"- {item}" for item in category_data['scope']])
                bible_content = bible_content.replace(
                    "- **Primary Domain**: [Clear definition of the main functional area this bible addresses]",
                    f"- **Primary Domain**: {category_data['description']}\n\n**Key Areas Covered**:\n{scope_text}"
                )
            
            # Try to integrate content from source files
            if 'source_files' in category_data:
                integrated_content = self._integrate_source_content(category_data['source_files'], bible_content)
                bible_content = integrated_content
            
            # Write bible file
            with open(bible_path, 'w') as f:
                f.write(bible_content)
            
            # Set proper permissions
            os.chmod(bible_path, int(self.config['security']['access_control']['file_permissions'], 8))
            
            self.logger.info(f"Created bible: {bible_path}")
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to create {bible_path}: {e}")
            return False
    
    def _integrate_source_content(self, source_files: Dict, template_content: str) -> str:
        """Integrate content from source files into bible template"""
        docs_dir = Path(self.config['paths']['docs_directory'])
        
        # Start with template
        integrated_content = template_content
        
        # Look for primary source files
        primary_files = source_files.get('primary', [])
        for source_file in primary_files:
            source_path = docs_dir / source_file
            if source_path.exists():
                try:
                    with open(source_path, 'r') as f:
                        source_content = f.read()
                    
                    # Extract useful sections and integrate
                    # This is a simplified integration - in a full implementation,
                    # this would use more sophisticated content extraction
                    self.logger.info(f"Integrating content from {source_file}")
                    
                    # Add source content reference
                    integrated_content += f"\n\n## Source Content Integration\n\n"
                    integrated_content += f"*Content integrated from: {source_file}*\n\n"
                    integrated_content += "```markdown\n"
                    integrated_content += source_content[:1000] + "...\n"  # Sample content
                    integrated_content += "```\n"
                    
                except Exception as e:
                    self.logger.warning(f"Could not integrate {source_file}: {e}")
        
        return integrated_content
    
    def _archive_legacy_files(self, categories: Dict):
        """Archive legacy files after successful migration"""
        self.logger.info("=== ARCHIVING LEGACY FILES ===")
        
        archive_dir = Path(self.config['paths']['archive_directory'])
        archive_dir.mkdir(parents=True, exist_ok=True)
        
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        migration_archive = archive_dir / f"migration_{timestamp}"
        migration_archive.mkdir(exist_ok=True)
        
        # Archive files listed in categories config
        if 'archive_files' in categories:
            for archive_item in categories['archive_files']:
                filename = archive_item['filename']
                source_path = Path(self.config['paths']['docs_directory']) / filename
                
                if source_path.exists():
                    target_path = migration_archive / filename
                    shutil.move(str(source_path), str(target_path))
                    self.logger.info(f"Archived: {filename}")
        
        self.logger.info(f"Legacy files archived to: {migration_archive}")
    
    def upgrade_configuration(self, target_version: str) -> bool:
        """Upgrade configuration to target version"""
        self.logger.info(f"=== UPGRADING CONFIGURATION TO {target_version} ===")
        
        if self.current_version == target_version:
            self.logger.info("Already at target version")
            return True
        
        # Define upgrade paths
        upgrade_tasks = self._get_upgrade_tasks(self.current_version, target_version)
        
        if not upgrade_tasks:
            self.logger.warning("No upgrade path found")
            return False
        
        # Create backup
        backup_path = self._create_backup(f"upgrade_to_{target_version}")
        
        try:
            # Execute upgrade tasks
            for task in upgrade_tasks:
                self.logger.info(f"Executing: {task.description}")
                success = self._execute_upgrade_task(task)
                
                if not success and task.required:
                    self.logger.error(f"Required upgrade task failed: {task.name}")
                    self._restore_backup(backup_path)
                    return False
                elif not success:
                    self.logger.warning(f"Optional upgrade task failed: {task.name}")
                
                self.migration_log.append(f"Executed: {task.description}")
            
            # Update version in config
            self._update_config_version(target_version)
            
            self.logger.info(f"Upgrade to {target_version} completed successfully")
            return True
            
        except Exception as e:
            self.logger.error(f"Upgrade failed: {e}")
            self._restore_backup(backup_path)
            return False
    
    def _get_upgrade_tasks(self, current: str, target: str) -> List[MigrationTask]:
        """Get list of upgrade tasks for version transition"""
        tasks = []
        
        # Version-specific upgrade tasks
        if current == "0.0.0" and target == "1.0.0":
            tasks = [
                MigrationTask(
                    "create_directories", 
                    "Create required directory structure",
                    current, target, True, True
                ),
                MigrationTask(
                    "migrate_documentation", 
                    "Migrate legacy documentation to bible structure",
                    current, target, True, True
                ),
                MigrationTask(
                    "setup_systemd", 
                    "Setup systemd service configuration",
                    current, target, False, False
                ),
                MigrationTask(
                    "validate_ai_integration", 
                    "Validate AI system integration",
                    current, target, True, False
                )
            ]
        
        return tasks
    
    def _execute_upgrade_task(self, task: MigrationTask) -> bool:
        """Execute a specific upgrade task"""
        try:
            if task.name == "create_directories":
                return self._create_required_directories()
            elif task.name == "migrate_documentation":
                return self.migrate_legacy_documentation()
            elif task.name == "setup_systemd":
                return self._setup_systemd_service()
            elif task.name == "validate_ai_integration":
                return self._validate_ai_integration()
            else:
                self.logger.warning(f"Unknown upgrade task: {task.name}")
                return False
                
        except Exception as e:
            self.logger.error(f"Upgrade task {task.name} failed: {e}")
            return False
    
    def _create_required_directories(self) -> bool:
        """Create required directory structure"""
        required_dirs = [
            self.config['paths']['bibles_directory'],
            self.config['paths']['backups_directory'],
            self.config['paths']['archive_directory'],
            self.config['paths']['logs_directory']
        ]
        
        try:
            for dir_path in required_dirs:
                path = Path(dir_path)
                path.mkdir(parents=True, exist_ok=True)
                os.chmod(path, int(self.config['security']['access_control']['directory_permissions'], 8))
            
            return True
        except Exception as e:
            self.logger.error(f"Directory creation failed: {e}")
            return False
    
    def _setup_systemd_service(self) -> bool:
        """Setup systemd service (optional task)"""
        try:
            # This would normally call the installer's systemd setup
            self.logger.info("Systemd service setup deferred to installer")
            return True
        except Exception as e:
            self.logger.error(f"Systemd setup failed: {e}")
            return False
    
    def _validate_ai_integration(self) -> bool:
        """Validate AI system integration"""
        try:
            # Check if ollama is running
            result = subprocess.run(
                ["systemctl", "is-active", "ollama"],
                capture_output=True, text=True
            )
            return result.returncode == 0
        except Exception as e:
            self.logger.error(f"AI validation failed: {e}")
            return False
    
    def _update_config_version(self, new_version: str):
        """Update version in configuration file"""
        self.config['system']['version'] = new_version
        self.config['system']['last_updated'] = datetime.now().strftime('%Y-%m-%d')
        
        with open(self.config_path, 'w') as f:
            yaml.dump(self.config, f, default_flow_style=False, sort_keys=False)
        
        self.logger.info(f"Configuration version updated to {new_version}")
    
    def cleanup_old_versions(self, keep_count: int = 5) -> bool:
        """Clean up old backup versions"""
        self.logger.info(f"=== CLEANING UP OLD VERSIONS (keeping {keep_count}) ===")
        
        try:
            # Clean backup directory
            backup_dirs = sorted([
                d for d in self.backup_dir.iterdir() 
                if d.is_dir() and d.name.startswith('pre_migration_')
            ], key=lambda x: x.stat().st_mtime)
            
            if len(backup_dirs) > keep_count:
                for old_backup in backup_dirs[:-keep_count]:
                    shutil.rmtree(old_backup)
                    self.logger.info(f"Removed old backup: {old_backup}")
            
            return True
            
        except Exception as e:
            self.logger.error(f"Cleanup failed: {e}")
            return False

def main():
    """Main migrator entry point"""
    parser = argparse.ArgumentParser(description="Bible System Migrator - Agent 8")
    parser.add_argument(
        "--config", 
        default="/etc/nixos/config/bible_system_config.yaml",
        help="Configuration file path"
    )
    parser.add_argument(
        "--detect-legacy",
        action="store_true",
        help="Detect legacy configuration"
    )
    parser.add_argument(
        "--migrate-docs",
        action="store_true", 
        help="Migrate legacy documentation to bible structure"
    )
    parser.add_argument(
        "--upgrade",
        help="Upgrade to specified version"
    )
    parser.add_argument(
        "--cleanup",
        action="store_true",
        help="Clean up old backup versions"
    )
    parser.add_argument(
        "--backup-only",
        help="Create backup with specified description"
    )
    
    args = parser.parse_args()
    
    # Initialize migrator
    migrator = BibleSystemMigrator(args.config)
    success = True
    
    if args.detect_legacy:
        legacy_info = migrator.detect_legacy_configuration()
        print("\nLegacy Analysis:")
        print(json.dumps(legacy_info, indent=2))
        
    elif args.migrate_docs:
        success = migrator.migrate_legacy_documentation()
        
    elif args.upgrade:
        success = migrator.upgrade_configuration(args.upgrade)
        
    elif args.cleanup:
        success = migrator.cleanup_old_versions()
        
    elif args.backup_only:
        try:
            backup_path = migrator._create_backup(args.backup_only)
            print(f"Backup created: {backup_path}")
        except Exception as e:
            print(f"Backup failed: {e}")
            success = False
    else:
        parser.print_help()
    
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
EOF < /dev/null