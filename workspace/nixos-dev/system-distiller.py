#!/usr/bin/env python3
"""
NixOS System Distiller - Extract and normalize system configuration
Outputs a canonical representation of what the system actually does,
regardless of how the Nix configuration is structured.

Usage:
    ./system-distiller.py > old-system.json
    # Deploy to new repo and run
    ./system-distiller.py > new-system.json
    # Compare
    diff <(jq -S . old-system.json) <(jq -S . new-system.json)
"""

import json
import subprocess
import re
import os
from pathlib import Path
from typing import Dict, List, Any, Optional
import sys

class SystemDistiller:
    def __init__(self):
        self.output = {
            "metadata": {},
            "systemd": {
                "services": {},
                "timers": {},
                "targets": {}
            },
            "containers": {},
            "networking": {
                "firewall": {},
                "interfaces": {},
                "services": {}
            },
            "filesystems": {},
            "secrets": {},
            "environment": {},
            "users": {},
            "packages": []
        }
    
    def run_cmd(self, cmd: List[str], capture_errors=True) -> Optional[str]:
        """Run command and return output, or None if failed"""
        try:
            result = subprocess.run(
                cmd, capture_output=True, text=True, 
                check=not capture_errors
            )
            return result.stdout.strip() if result.returncode == 0 else None
        except Exception as e:
            print(f"Command failed: {' '.join(cmd)} - {e}", file=sys.stderr)
            return None
    
    def extract_metadata(self):
        """Extract basic system metadata"""
        self.output["metadata"] = {
            "hostname": self.run_cmd(["hostname"]) or "unknown",
            "nixos_version": self.run_cmd(["nixos-version"]) or "unknown",
            "kernel": self.run_cmd(["uname", "-r"]) or "unknown",
            "architecture": self.run_cmd(["uname", "-m"]) or "unknown"
        }
    
    def extract_systemd_services(self):
        """Extract all systemd services and their key properties"""
        # Get all services
        services_raw = self.run_cmd(["systemctl", "list-units", "--type=service", "--all", "--no-legend"])
        if not services_raw:
            return
            
        for line in services_raw.split('\n'):
            if not line.strip():
                continue
            parts = line.split()
            if len(parts) < 4:
                continue
            
            service_name = parts[0]
            load_state = parts[1]
            active_state = parts[2]
            sub_state = parts[3]
            
            # Get detailed service info
            service_info = self.get_service_details(service_name)
            
            self.output["systemd"]["services"][service_name] = {
                "load_state": load_state,
                "active_state": active_state,
                "sub_state": sub_state,
                **service_info
            }
    
    def get_service_details(self, service_name: str) -> Dict[str, Any]:
        """Get detailed information about a specific service"""
        details = {}
        
        # Get service properties
        props_cmd = ["systemctl", "show", service_name, "--no-page"]
        props_raw = self.run_cmd(props_cmd)
        
        if props_raw:
            for line in props_raw.split('\n'):
                if '=' in line:
                    key, value = line.split('=', 1)
                    
                    # Extract key properties
                    if key in ['ExecStart', 'ExecReload', 'ExecStop', 'Environment', 
                              'EnvironmentFiles', 'User', 'Group', 'WorkingDirectory',
                              'Requires', 'After', 'Before', 'WantedBy', 'Wants']:
                        details[key.lower()] = value
        
        return details
    
    def extract_containers(self):
        """Extract container configurations"""
        # Podman containers
        containers_raw = self.run_cmd(["podman", "ps", "-a", "--format", "json"])
        if containers_raw:
            try:
                containers = json.loads(containers_raw)
                for container in containers:
                    name = container.get('Names', ['unknown'])[0]
                    
                    # Get detailed container info
                    inspect_raw = self.run_cmd(["podman", "inspect", name])
                    if inspect_raw:
                        try:
                            inspect_data = json.loads(inspect_raw)[0]
                            self.output["containers"][name] = self.normalize_container(inspect_data)
                        except:
                            self.output["containers"][name] = {"error": "failed_to_inspect"}
            except json.JSONDecodeError:
                pass
    
    def normalize_container(self, inspect_data: Dict) -> Dict[str, Any]:
        """Normalize container configuration to comparable format"""
        config = inspect_data.get('Config', {})
        host_config = inspect_data.get('HostConfig', {})
        
        # Handle both HostConfig.Binds and Mounts structures
        volumes = []
        
        # From HostConfig.Binds (older format)
        for bind in host_config.get('Binds', []):
            if isinstance(bind, str):
                volumes.append(bind)
        
        # From Mounts (newer format)
        for mount in inspect_data.get('Mounts', []):
            if mount.get('Type') == 'bind':
                source = mount.get('Source', '')
                dest = mount.get('Destination', '')
                rw = 'rw' if mount.get('RW', True) else 'ro'
                volumes.append(f"{source}:{dest}:{rw}")
        
        return {
            "image": config.get('Image', ''),
            "state": inspect_data.get('State', {}).get('Status', ''),
            "environment": sorted(config.get('Env', [])),
            "volumes": sorted(volumes),
            "ports": sorted([
                f"{host_port.get('HostIp', '')}:{host_port.get('HostPort', '')}:{container_port}"
                for container_port, host_ports in host_config.get('PortBindings', {}).items()
                for host_port in host_ports or []
            ]),
            "networks": list(inspect_data.get('NetworkSettings', {}).get('Networks', {}).keys()),
            "restart_policy": host_config.get('RestartPolicy', {}),
            "devices": sorted([
                f"{dev.get('PathOnHost', '')}:{dev.get('PathInContainer', '')}:{dev.get('CgroupPermissions', '')}"
                for dev in host_config.get('Devices', [])
            ])
        }
    
    def extract_networking(self):
        """Extract networking configuration"""
        # Firewall rules
        iptables_raw = self.run_cmd(["iptables", "-L", "-n"])
        if iptables_raw:
            self.output["networking"]["firewall"]["iptables"] = iptables_raw
        
        # Network interfaces
        ip_addr_raw = self.run_cmd(["ip", "addr", "show"])
        if ip_addr_raw:
            self.output["networking"]["interfaces"] = self.parse_ip_addr(ip_addr_raw)
        
        # Listening services
        ss_raw = self.run_cmd(["ss", "-tlnp"])
        if ss_raw:
            self.output["networking"]["services"] = self.parse_listening_ports(ss_raw)
    
    def parse_ip_addr(self, ip_output: str) -> Dict[str, Any]:
        """Parse ip addr output"""
        interfaces = {}
        current_interface = None
        
        for line in ip_output.split('\n'):
            # Interface line: "2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500"
            if re.match(r'^\d+:', line):
                parts = line.split()
                if len(parts) >= 2:
                    current_interface = parts[1].rstrip(':')
                    interfaces[current_interface] = {
                        "flags": [],
                        "addresses": []
                    }
                    if '<' in line and '>' in line:
                        flags_str = line.split('<')[1].split('>')[0]
                        interfaces[current_interface]["flags"] = flags_str.split(',')
            
            # Address line: "    inet 192.168.1.13/24 brd 192.168.1.255 scope global eth0"
            elif current_interface and ('inet' in line or 'inet6' in line):
                parts = line.strip().split()
                if len(parts) >= 2:
                    interfaces[current_interface]["addresses"].append(parts[1])
        
        return interfaces
    
    def parse_listening_ports(self, ss_output: str) -> List[Dict[str, str]]:
        """Parse ss output for listening ports"""
        ports = []
        
        for line in ss_output.split('\n')[1:]:  # Skip header
            if not line.strip():
                continue
            
            parts = line.split()
            if len(parts) >= 4:
                ports.append({
                    "protocol": parts[0],
                    "local_address": parts[3],
                    "process": parts[5] if len(parts) > 5 else ""
                })
        
        return sorted(ports, key=lambda x: (x["protocol"], x["local_address"]))
    
    def extract_filesystems(self):
        """Extract filesystem mounts"""
        mount_raw = self.run_cmd(["mount"])
        if mount_raw:
            mounts = []
            for line in mount_raw.split('\n'):
                if ' on ' in line and ' type ' in line:
                    parts = line.split()
                    if len(parts) >= 6:
                        mounts.append({
                            "device": parts[0],
                            "mountpoint": parts[2],
                            "fstype": parts[4],
                            "options": parts[5].strip('()')
                        })
            
            self.output["filesystems"]["mounts"] = sorted(mounts, key=lambda x: x["mountpoint"])
    
    def extract_secrets(self):
        """Extract secrets/SOPS configuration"""
        sops_files = []
        
        # Look for SOPS files
        for pattern in ["/run/secrets/*", "/etc/sops/*"]:
            files = self.run_cmd(["find"] + pattern.split('*')[:-1] + ["-name", "*" + pattern.split('*')[-1]])
            if files:
                sops_files.extend(files.split('\n'))
        
        # Also check for age keys
        age_key_file = "/etc/sops/age/keys.txt"
        if os.path.exists(age_key_file):
            sops_files.append(age_key_file)
        
        self.output["secrets"]["files"] = sorted(list(set(sops_files)))
    
    def extract_environment(self):
        """Extract environment packages and configuration"""
        # System packages (approximation)
        nix_store_raw = self.run_cmd(["nix-store", "-q", "--references", "/run/current-system"])
        if nix_store_raw:
            packages = []
            for line in nix_store_raw.split('\n'):
                if line.strip():
                    # Extract package name from store path
                    name = os.path.basename(line)
                    if '-' in name:
                        # Remove hash prefix
                        name = '-'.join(name.split('-')[1:])
                    packages.append(name)
            
            self.output["environment"]["system_packages"] = sorted(packages)
    
    def extract_users(self):
        """Extract user configuration"""
        # Get users from /etc/passwd
        passwd_raw = self.run_cmd(["cat", "/etc/passwd"])
        if passwd_raw:
            users = {}
            for line in passwd_raw.split('\n'):
                if ':' in line:
                    parts = line.split(':')
                    if len(parts) >= 7:
                        username = parts[0]
                        users[username] = {
                            "uid": parts[2],
                            "gid": parts[3],
                            "home": parts[5],
                            "shell": parts[6]
                        }
            
            self.output["users"] = users
    
    def distill(self) -> Dict[str, Any]:
        """Run all extraction methods and return complete system distillation"""
        print("Extracting metadata...", file=sys.stderr)
        self.extract_metadata()
        
        print("Extracting systemd services...", file=sys.stderr)
        self.extract_systemd_services()
        
        print("Extracting containers...", file=sys.stderr)
        self.extract_containers()
        
        print("Extracting networking...", file=sys.stderr)
        self.extract_networking()
        
        print("Extracting filesystems...", file=sys.stderr)
        self.extract_filesystems()
        
        print("Extracting secrets...", file=sys.stderr)
        self.extract_secrets()
        
        print("Extracting environment...", file=sys.stderr)
        self.extract_environment()
        
        print("Extracting users...", file=sys.stderr)
        self.extract_users()
        
        return self.output

def main():
    if len(sys.argv) > 1 and sys.argv[1] in ['-h', '--help']:
        print(__doc__)
        sys.exit(0)
    
    distiller = SystemDistiller()
    result = distiller.distill()
    
    print(json.dumps(result, indent=2, sort_keys=True))

if __name__ == "__main__":
    main()