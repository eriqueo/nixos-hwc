#!/usr/bin/env python3
"""
SABnzbd Configuration Analyzer - Checks critical SABnzbd functionality
Specifically validates the events system fix from 2025-09-28
"""

import re
import json
import sys
from pathlib import Path

def analyze_sabnzbd_config(config_path):
    """Analyze SABnzbd configuration for critical components"""
    config_path = Path(config_path)
    
    result = {
        "config_path": str(config_path),
        "sabnzbd_container": {
            "found": False,
            "volumes": [],
            "has_events_mount": False,
            "has_scripts_mount": False,
            "has_downloads_mount": False,
            "file": None
        },
        "media_orchestrator": {
            "found": False,
            "file": None
        },
        "scripts": {
            "sab_finished_py": False,
            "media_orchestrator_py": False,
            "script_directory": None
        },
        "validation": {
            "events_system_working": False,
            "missing_components": []
        }
    }
    
    # Find SABnzbd container definition
    container_files = list(config_path.glob("**/*sabnzbd*.nix")) + \
                     list(config_path.glob("**/media-containers.nix"))
    
    for file_path in container_files:
        try:
            with open(file_path) as f:
                content = f.read()
                
                # Look for SABnzbd container
                if "sabnzbd" in content:
                    result["sabnzbd_container"]["found"] = True
                    result["sabnzbd_container"]["file"] = str(file_path.relative_to(config_path))
                    
                    # Extract volumes
                    volumes_match = re.search(r'volumes\s*=\s*\[([^\]]+)\]', content, re.DOTALL)
                    if volumes_match:
                        volumes_text = volumes_match.group(1)
                        volumes = re.findall(r'["\']([^"\']+)["\']', volumes_text)
                        result["sabnzbd_container"]["volumes"] = volumes
                        
                        # Check for critical mounts
                        for volume in volumes:
                            if "/mnt/hot/events" in volume:
                                result["sabnzbd_container"]["has_events_mount"] = True
                            if "scripts" in volume and "/config/scripts" in volume:
                                result["sabnzbd_container"]["has_scripts_mount"] = True
                            if "/downloads" in volume:
                                result["sabnzb_container"]["has_downloads_mount"] = True
                    
        except Exception as e:
            pass
    
    # Find media orchestrator service
    service_files = list(config_path.glob("**/*orchestrator*.nix"))
    for file_path in service_files:
        try:
            with open(file_path) as f:
                content = f.read()
                if "media-orchestrator" in content and "systemd.services" in content:
                    result["media_orchestrator"]["found"] = True
                    result["media_orchestrator"]["file"] = str(file_path.relative_to(config_path))
        except:
            pass
    
    # Check for scripts
    script_locations = [
        config_path / "scripts",
        config_path / "opt" / "downloads" / "scripts"
    ]
    
    for script_dir in script_locations:
        if script_dir.exists():
            result["scripts"]["script_directory"] = str(script_dir.relative_to(config_path))
            
            if (script_dir / "sab-finished.py").exists():
                result["scripts"]["sab_finished_py"] = True
            
            if (script_dir / "media-orchestrator.py").exists():
                result["scripts"]["media_orchestrator_py"] = True
    
    # Validation logic
    missing = []
    
    if not result["sabnzbd_container"]["found"]:
        missing.append("SABnzbd container definition")
    else:
        if not result["sabnzbd_container"]["has_events_mount"]:
            missing.append("SABnzbd events directory mount (/mnt/hot/events)")
        if not result["sabnzbd_container"]["has_scripts_mount"]:
            missing.append("SABnzbd scripts directory mount")
    
    if not result["media_orchestrator"]["found"]:
        missing.append("Media orchestrator service")
    
    if not result["scripts"]["sab_finished_py"]:
        missing.append("sab-finished.py script")
    
    result["validation"]["missing_components"] = missing
    result["validation"]["events_system_working"] = len(missing) == 0
    
    return result

def main():
    if len(sys.argv) < 2:
        print("Usage: sabnzbd-analyzer.py <config-path>")
        sys.exit(1)
    
    config_path = sys.argv[1]
    result = analyze_sabnzbd_config(config_path)
    
    print(json.dumps(result, indent=2))

if __name__ == "__main__":
    main()