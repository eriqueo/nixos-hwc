"""
System Config Scanner - Extracts system-level configurations

Extracts:
- User and group definitions
- Networking configuration (SSH, Tailscale, etc.)
- Firewall rules
- Filesystem mounts and paths
- System services
"""

import re
from pathlib import Path
from typing import Dict, List, Set

import re as _compiled_re

# Fixed patterns compile once; matching stays at the original call sites.
__EXTRACT_USER_INFO_SEARCH_RE = _compiled_re.compile(r'users\.users\.(\w+)\s*=')
__EXTRACT_USER_INFO_SEARCH_RE_2 = _compiled_re.compile(r'extraGroups\s*=\s*\[(.*?)\]', _compiled_re.DOTALL)
__EXTRACT_USER_INFO_SEARCH_RE_3 = _compiled_re.compile(r'shell\s*=.*?/(\w+)')
__EXTRACT_FIREWALL_RULES_FINDALL_RE = _compiled_re.compile(r'allowedTCPPorts\s*=.*?\[(.*?)\]', _compiled_re.DOTALL)
__EXTRACT_FIREWALL_RULES_FINDALL_RE_2 = _compiled_re.compile(r'allowedUDPPorts\s*=.*?\[(.*?)\]', _compiled_re.DOTALL)
__EXTRACT_MACHINE_CONFIG_FINDALL_RE = _compiled_re.compile(r'hwc\.paths\.(\w+)\s*=\s*"([^"]+)"')
__EXTRACT_USER_INFO_FINDALL_RE = _compiled_re.compile(r'"(\w+)"')
__EXTRACT_FIREWALL_RULES_FINDALL_RE_3 = _compiled_re.compile(r'(\d+)')



class SystemScanner:
    def __init__(self, source_path: Path, verbose: bool = False):
        self.source_path = Path(source_path)
        self.verbose = verbose
        self.users = {}
        self.networking = {}
        self.firewall = {'tcp_ports': set(), 'udp_ports': set()}
        self.filesystems = {'mounts': [], 'paths': {}}

    def log(self, message):
        if self.verbose:
            print(f"  [system-scanner] {message}")

    def scan(self) -> Dict:
        """Scan for system-level configurations"""
        self.log("Scanning system configurations...")

        # Scan domains/system for system configs
        system_domain = self.source_path / 'domains' / 'system'
        if system_domain.exists():
            self._scan_system_domain(system_domain)

        # Scan infrastructure domain for paths
        infra_domain = self.source_path / 'domains' / 'infrastructure'
        if infra_domain.exists():
            self._scan_infrastructure_domain(infra_domain)

        # Scan machine configs for machine-specific settings
        machines_dir = self.source_path / 'machines'
        if machines_dir.exists():
            self._scan_machines(machines_dir)

        self.log(f"Found {len(self.users)} users, {len(self.firewall['tcp_ports'])} TCP ports")

        return {
            'users': list(self.users.values()),
            'networking': self.networking,
            'firewall': {
                'tcp_ports': sorted(list(self.firewall['tcp_ports'])),
                'udp_ports': sorted(list(self.firewall['udp_ports']))
            },
            'filesystems': self.filesystems
        }

    def _scan_system_domain(self, system_dir: Path):
        """Scan the system domain"""
        # Scan for users
        users_file = system_dir / 'users' / 'eric.nix'
        if users_file.exists():
            self._extract_user_info(users_file)

        # Scan networking configs
        networking_dir = system_dir / 'services' / 'networking'
        if networking_dir.exists():
            self._scan_networking(networking_dir)

    def _scan_infrastructure_domain(self, infra_dir: Path):
        """Scan infrastructure domain for paths and mounts"""
        # Look for storage configuration
        storage_dir = infra_dir / 'storage'
        if storage_dir.exists():
            for config_file in storage_dir.rglob('*.nix'):
                self._extract_paths(config_file)

    def _scan_machines(self, machines_dir: Path):
        """Scan machine-specific configs"""
        for machine_dir in machines_dir.iterdir():
            if machine_dir.is_dir():
                config_file = machine_dir / 'config.nix'
                if config_file.exists():
                    self._extract_machine_config(config_file)

    def _extract_user_info(self, file_path: Path):
        """Extract user definitions"""
        try:
            with open(file_path, 'r') as f:
                content = f.read()

            # Extract username
            user_match = __EXTRACT_USER_INFO_SEARCH_RE.search(content)
            if not user_match:
                return

            username = user_match.group(1)

            user_info = {
                'name': username,
                'groups': [],
                'shell': '/bin/bash',
                'uid': None
            }

            # Extract groups
            groups_match = __EXTRACT_USER_INFO_SEARCH_RE_2.search(content)
            if groups_match:
                groups_text = groups_match.group(1)
                groups = __EXTRACT_USER_INFO_FINDALL_RE.findall(groups_text)
                user_info['groups'] = groups

            # Extract shell
            shell_match = __EXTRACT_USER_INFO_SEARCH_RE_3.search(content)
            if shell_match:
                user_info['shell'] = f"/bin/{shell_match.group(1)}"

            self.users[username] = user_info

        except Exception as e:
            self.log(f"Error extracting user info: {e}")

    def _scan_networking(self, networking_dir: Path):
        """Scan networking configurations"""
        # Check for SSH
        ssh_file = networking_dir / 'ssh' / 'index.nix'
        if ssh_file.exists():
            self.networking['ssh'] = {'enabled': True, 'port': 22}

        # Check for Tailscale
        tailscale_dir = networking_dir / 'tailscale'
        if tailscale_dir.exists():
            self.networking['tailscale'] = {'enabled': True}

        # Check for Samba
        samba_dir = networking_dir / 'samba'
        if samba_dir.exists():
            self.networking['samba'] = {'enabled': True}

        # Scan for firewall rules
        for config_file in networking_dir.rglob('*.nix'):
            self._extract_firewall_rules(config_file)

    def _extract_firewall_rules(self, file_path: Path):
        """Extract firewall rules from config files"""
        try:
            with open(file_path, 'r') as f:
                content = f.read()

            # Extract TCP ports
            tcp_match = __EXTRACT_FIREWALL_RULES_FINDALL_RE.findall(content)
            for match in tcp_match:
                ports = __EXTRACT_FIREWALL_RULES_FINDALL_RE_3.findall(match)
                self.firewall['tcp_ports'].update(map(int, ports))

            # Extract UDP ports
            udp_match = __EXTRACT_FIREWALL_RULES_FINDALL_RE_2.findall(content)
            for match in udp_match:
                ports = __EXTRACT_FIREWALL_RULES_FINDALL_RE_3.findall(match)
                self.firewall['udp_ports'].update(map(int, ports))

        except Exception as e:
            pass  # Silently skip files without firewall rules

    def _extract_paths(self, file_path: Path):
        """Extract filesystem paths and mounts"""
        try:
            with open(file_path, 'r') as f:
                content = f.read()

            # Look for hwc.paths definitions
            path_patterns = [
                (r'hwc\.paths\.hot\s*=\s*"([^"]+)"', 'hot'),
                (r'hwc\.paths\.media\s*=\s*"([^"]+)"', 'media'),
                (r'hwc\.paths\.backup\s*=\s*"([^"]+)"', 'backup'),
            ]

            for pattern, name in path_patterns:
                match = re.search(pattern, content)
                if match:
                    self.filesystems['paths'][name] = match.group(1)

        except Exception as e:
            pass

    def _extract_machine_config(self, file_path: Path):
        """Extract machine-specific configuration"""
        try:
            with open(file_path, 'r') as f:
                content = f.read()

            # Extract paths from machine config
            path_assignments = __EXTRACT_MACHINE_CONFIG_FINDALL_RE.findall(content)
            for path_name, path_value in path_assignments:
                self.filesystems['paths'][path_name] = path_value

        except Exception as e:
            pass
