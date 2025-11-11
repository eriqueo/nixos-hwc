#\!/usr/bin/env python3
"""
AI Bible Documentation System - Cleanup & Maintenance Tool
Agent 8: Configuration & Deployment System

This script handles system cleanup, maintenance, and uninstallation procedures.
"""

import os
import sys
import yaml
import shutil
import logging
import argparse
import subprocess
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional
from datetime import datetime, timedelta

class BibleSystemCleanup:
    """System cleanup and maintenance manager"""
    
    def __init__(self, config_path: str = "/etc/nixos/config/bible_system_config.yaml"):
        """Initialize cleanup manager"""
        self.config_path = Path(config_path)
        self.config = self._load_config() if self.config_path.exists() else {}
        self.base_dir = Path("/etc/nixos")
        
        # Setup logging
        self._setup_logging()
        
    def _load_config(self) -> Dict[str, Any]:
        """Load system configuration if available"""
        try:
            with open(self.config_path, 'r') as f:
                return yaml.safe_load(f)
        except Exception as e:
            print(f"Warning: Could not load config: {e}")
            return {}
    
    def _setup_logging(self):
        """Setup logging configuration"""
        log_dir = Path("/etc/nixos/docs/logs") if self.config else Path("/tmp")
        log_dir.mkdir(parents=True, exist_ok=True)
        
        log_file = log_dir / f"bible_cleanup_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
        
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(log_file),
                logging.StreamHandler(sys.stdout)
            ]
        )
        self.logger = logging.getLogger(__name__)
        self.logger.info("Bible System Cleanup - Agent 8")
    
    def _run_command(self, command: List[str]) -> Tuple[bool, str]:
        """Run system command"""
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=60)
            return result.returncode == 0, result.stdout if result.returncode == 0 else result.stderr
        except Exception as e:
            return False, str(e)
    
    def cleanup_old_logs(self, days_to_keep: int = 30) -> bool:
        """Clean up old log files"""
        self.logger.info(f"=== CLEANING UP LOGS OLDER THAN {days_to_keep} DAYS ===")
        
        log_dirs = []
        if self.config and 'paths' in self.config:
            log_dirs.append(Path(self.config['paths']['logs_directory']))
        else:
            # Default locations
            log_dirs.extend([
                Path("/etc/nixos/docs/logs"),
                Path("/var/log"),
                Path("/tmp")
            ])
        
        cutoff_date = datetime.now() - timedelta(days=days_to_keep)
        cleaned_count = 0
        
        for log_dir in log_dirs:
            if not log_dir.exists():
                continue
            
            try:
                for log_file in log_dir.glob("bible_*"):
                    if log_file.is_file():
                        file_time = datetime.fromtimestamp(log_file.stat().st_mtime)
                        if file_time < cutoff_date:
                            log_file.unlink()
                            self.logger.info(f"Removed old log: {log_file}")
                            cleaned_count += 1
            except Exception as e:
                self.logger.warning(f"Error cleaning {log_dir}: {e}")
        
        self.logger.info(f"Cleaned {cleaned_count} old log files")
        return True
    
    def cleanup_old_backups(self, keep_count: int = 10) -> bool:
        """Clean up old backup files"""
        self.logger.info(f"=== CLEANING UP OLD BACKUPS (keeping {keep_count}) ===")
        
        backup_dirs = []
        if self.config and 'paths' in self.config:
            backup_dirs.append(Path(self.config['paths']['backups_directory']))
        else:
            backup_dirs.append(Path("/etc/nixos/docs/bibles/backups"))
        
        cleaned_count = 0
        
        for backup_dir in backup_dirs:
            if not backup_dir.exists():
                continue
            
            try:
                # Get all backup files/directories sorted by modification time
                backups = sorted([
                    item for item in backup_dir.iterdir()
                    if item.name.startswith(('pre_migration_', 'bible_', 'backup_'))
                ], key=lambda x: x.stat().st_mtime, reverse=True)
                
                # Keep only the newest ones
                for old_backup in backups[keep_count:]:
                    if old_backup.is_dir():
                        shutil.rmtree(old_backup)
                    else:
                        old_backup.unlink()
                    
                    self.logger.info(f"Removed old backup: {old_backup}")
                    cleaned_count += 1
                    
            except Exception as e:
                self.logger.warning(f"Error cleaning backups in {backup_dir}: {e}")
        
        self.logger.info(f"Cleaned {cleaned_count} old backup files")
        return True
    
    def cleanup_temp_files(self) -> bool:
        """Clean up temporary files"""
        self.logger.info("=== CLEANING UP TEMPORARY FILES ===")
        
        temp_patterns = [
            "/tmp/bible_*",
            "/tmp/ollama_*",
            "/tmp/*.tmp",
            "/etc/nixos/.git/hooks/*.tmp",
            "/etc/nixos/scripts/*.pyc"
        ]
        
        cleaned_count = 0
        
        for pattern in temp_patterns:
            try:
                import glob
                for file_path in glob.glob(pattern):
                    path = Path(file_path)
                    if path.exists() and path.is_file():
                        # Check if file is older than 1 day
                        file_time = datetime.fromtimestamp(path.stat().st_mtime)
                        if file_time < datetime.now() - timedelta(days=1):
                            path.unlink()
                            self.logger.info(f"Removed temp file: {path}")
                            cleaned_count += 1
            except Exception as e:
                self.logger.warning(f"Error cleaning pattern {pattern}: {e}")
        
        self.logger.info(f"Cleaned {cleaned_count} temporary files")
        return True
    
    def validate_disk_usage(self) -> Dict[str, Any]:
        """Validate and report disk usage"""
        self.logger.info("=== VALIDATING DISK USAGE ===")
        
        disk_report = {
            "total_gb": 0,
            "free_gb": 0,
            "used_percent": 0,
            "status": "unknown",
            "paths": {}
        }
        
        try:
            stat = shutil.disk_usage(self.base_dir)
            disk_report["total_gb"] = stat.total / (1024**3)
            disk_report["free_gb"] = stat.free / (1024**3)
            disk_report["used_percent"] = ((stat.total - stat.free) / stat.total) * 100
            
            if disk_report["free_gb"] >= 2.0:
                disk_report["status"] = "healthy"
            elif disk_report["free_gb"] >= 0.5:
                disk_report["status"] = "warning"
            else:
                disk_report["status"] = "critical"
            
            # Check specific directories
            check_paths = [
                "/etc/nixos",
                "/etc/nixos/docs",
                "/etc/nixos/docs/bibles",
                "/etc/nixos/docs/logs"
            ]
            
            for check_path in check_paths:
                path = Path(check_path)
                if path.exists():
                    try:
                        # Get directory size
                        size_bytes = sum(f.stat().st_size for f in path.rglob('*') if f.is_file())
                        size_mb = size_bytes / (1024**2)
                        disk_report["paths"][check_path] = {
                            "size_mb": round(size_mb, 2),
                            "exists": True
                        }
                    except Exception as e:
                        disk_report["paths"][check_path] = {
                            "error": str(e),
                            "exists": True
                        }
                else:
                    disk_report["paths"][check_path] = {"exists": False}
            
            self.logger.info(f"Disk status: {disk_report['status']} "
                           f"({disk_report['free_gb']:.1f}GB free, "
                           f"{disk_report['used_percent']:.1f}% used)")
            
        except Exception as e:
            self.logger.error(f"Error checking disk usage: {e}")
            disk_report["error"] = str(e)
        
        return disk_report
    
    def uninstall_bible_system(self, preserve_docs: bool = True) -> bool:
        """Complete uninstallation of bible system"""
        self.logger.info("🗑️  UNINSTALLING AI BIBLE SYSTEM")
        
        uninstall_steps = [
            ("Stopping systemd service", self._stop_systemd_service),
            ("Removing systemd service", self._remove_systemd_service),
            ("Cleaning up scripts", self._cleanup_scripts),
            ("Removing configuration", lambda: self._remove_config_files(preserve_docs)),
            ("Cleaning up logs", lambda: self.cleanup_old_logs(0)),  # Remove all logs
            ("Final cleanup", self.cleanup_temp_files)
        ]
        
        success_count = 0
        for step_name, step_func in uninstall_steps:
            try:
                self.logger.info(f"Executing: {step_name}")
                if step_func():
                    success_count += 1
                    self.logger.info(f"✓ {step_name}")
                else:
                    self.logger.warning(f"⚠ {step_name} - had issues")
            except Exception as e:
                self.logger.error(f"✗ {step_name} failed: {e}")
        
        if success_count == len(uninstall_steps):
            self.logger.info("🎉 UNINSTALL COMPLETED SUCCESSFULLY")
            if preserve_docs:
                self.logger.info("📚 Documentation files were preserved")
            return True
        else:
            self.logger.warning(f"⚠️ UNINSTALL COMPLETED WITH {len(uninstall_steps) - success_count} ISSUES")
            return False
    
    def _stop_systemd_service(self) -> bool:
        """Stop systemd service"""
        success, output = self._run_command(["systemctl", "stop", "bible-system.service"])
        return success  # It's OK if service doesn't exist
    
    def _remove_systemd_service(self) -> bool:
        """Remove systemd service file"""
        try:
            # Disable service first
            self._run_command(["systemctl", "disable", "bible-system.service"])
            
            # Remove service file
            service_file = Path("/etc/systemd/system/bible-system.service")
            if service_file.exists():
                service_file.unlink()
                self.logger.info("Removed systemd service file")
            
            # Reload systemd
            success, _ = self._run_command(["systemctl", "daemon-reload"])
            return success
            
        except Exception as e:
            self.logger.warning(f"Error removing systemd service: {e}")
            return False
    
    def _cleanup_scripts(self) -> bool:
        """Clean up bible system scripts"""
        try:
            scripts_to_remove = [
                "/etc/nixos/scripts/bible_system_installer.py",
                "/etc/nixos/scripts/bible_system_validator.py", 
                "/etc/nixos/scripts/bible_system_migrator.py",
                "/etc/nixos/scripts/bible_system_cleanup.py"
            ]
            
            for script_path in scripts_to_remove:
                path = Path(script_path)
                if path.exists() and path \!= Path(__file__):  # Don't delete ourselves yet
                    path.unlink()
                    self.logger.info(f"Removed script: {script_path}")
            
            return True
        except Exception as e:
            self.logger.warning(f"Error cleaning up scripts: {e}")
            return False
    
    def _remove_config_files(self, preserve_docs: bool) -> bool:
        """Remove configuration files"""
        try:
            config_files = [
                "/etc/nixos/config/bible_system_config.yaml"
            ]
            
            for config_file in config_files:
                path = Path(config_file)
                if path.exists():
                    path.unlink()
                    self.logger.info(f"Removed config: {config_file}")
            
            # Optionally remove bible files
            if not preserve_docs:
                bible_dirs = [
                    "/etc/nixos/docs/bibles",
                    "/etc/nixos/docs/archive"
                ]
                
                for bible_dir in bible_dirs:
                    path = Path(bible_dir)
                    if path.exists():
                        shutil.rmtree(path)
                        self.logger.info(f"Removed directory: {bible_dir}")
            
            return True
        except Exception as e:
            self.logger.warning(f"Error removing config files: {e}")
            return False
    
    def maintenance_report(self) -> Dict[str, Any]:
        """Generate system maintenance report"""
        self.logger.info("=== GENERATING MAINTENANCE REPORT ===")
        
        report = {
            "timestamp": datetime.now().isoformat(),
            "system_status": "unknown",
            "disk_usage": self.validate_disk_usage(),
            "cleanup_recommendations": [],
            "health_issues": []
        }
        
        # Analyze disk usage for recommendations
        disk = report["disk_usage"]
        if disk["status"] == "critical":
            report["cleanup_recommendations"].extend([
                "Immediately clean up disk space",
                "Remove old backups and logs",
                "Archive or remove large documentation files"
            ])
            report["health_issues"].append("Critical disk space shortage")
        elif disk["status"] == "warning":
            report["cleanup_recommendations"].extend([
                "Consider cleaning up old files",
                "Review backup retention policy"
            ])
        
        # Check for large directories
        for path, info in disk["paths"].items():
            if isinstance(info, dict) and "size_mb" in info:
                if info["size_mb"] > 100:  # > 100MB
                    report["cleanup_recommendations"].append(
                        f"Review large directory: {path} ({info['size_mb']:.1f}MB)"
                    )
        
        # Overall status
        if not report["health_issues"]:
            report["system_status"] = "healthy"
        elif disk["status"] == "critical":
            report["system_status"] = "critical"
        else:
            report["system_status"] = "needs_attention"
        
        self.logger.info(f"System status: {report['system_status']}")
        return report

def main():
    """Main cleanup entry point"""
    parser = argparse.ArgumentParser(description="Bible System Cleanup - Agent 8")
    parser.add_argument(
        "--config", 
        default="/etc/nixos/config/bible_system_config.yaml",
        help="Configuration file path"
    )
    parser.add_argument(
        "--cleanup-logs",
        type=int,
        default=30,
        help="Clean logs older than N days"
    )
    parser.add_argument(
        "--cleanup-backups",
        type=int,
        default=10,
        help="Keep N most recent backups"
    )
    parser.add_argument(
        "--cleanup-temp",
        action="store_true",
        help="Clean temporary files"
    )
    parser.add_argument(
        "--disk-report",
        action="store_true",
        help="Generate disk usage report"
    )
    parser.add_argument(
        "--maintenance-report",
        action="store_true",
        help="Generate maintenance report"
    )
    parser.add_argument(
        "--uninstall",
        action="store_true",
        help="Completely uninstall bible system"
    )
    parser.add_argument(
        "--preserve-docs",
        action="store_true",
        help="Preserve documentation during uninstall"
    )
    parser.add_argument(
        "--all-cleanup",
        action="store_true",
        help="Perform all cleanup operations"
    )
    
    args = parser.parse_args()
    
    # Initialize cleanup manager
    cleanup = BibleSystemCleanup(args.config)
    success = True
    
    if args.uninstall:
        success = cleanup.uninstall_bible_system(args.preserve_docs)
        
    elif args.all_cleanup:
        cleanup.cleanup_old_logs(args.cleanup_logs)
        cleanup.cleanup_old_backups(args.cleanup_backups)
        cleanup.cleanup_temp_files()
        
    else:
        if args.cleanup_logs:
            cleanup.cleanup_old_logs(args.cleanup_logs)
            
        if args.cleanup_backups:
            cleanup.cleanup_old_backups(args.cleanup_backups)
            
        if args.cleanup_temp:
            cleanup.cleanup_temp_files()
            
        if args.disk_report:
            report = cleanup.validate_disk_usage()
            print("\nDisk Usage Report:")
            print(f"Status: {report['status']}")
            print(f"Free Space: {report['free_gb']:.1f}GB")
            print(f"Used: {report['used_percent']:.1f}%")
            
        if args.maintenance_report:
            report = cleanup.maintenance_report()
            print(f"\nMaintenance Report:")
            print(f"System Status: {report['system_status']}")
            if report['cleanup_recommendations']:
                print("Recommendations:")
                for rec in report['cleanup_recommendations']:
                    print(f"  - {rec}")
    
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
EOF < /dev/null