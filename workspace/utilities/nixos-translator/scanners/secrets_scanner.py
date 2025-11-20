"""
Secrets Scanner - Creates inventory of secrets (without decrypting)

Scans agenix secrets and creates a manifest of:
- Secret names and locations
- Which services consume which secrets
- Secret categories
- Migration guide for SOPS or other secret managers
"""

import re
from pathlib import Path
from typing import Dict, List, Set


class SecretsScanner:
    def __init__(self, source_path: Path, verbose: bool = False):
        self.source_path = Path(source_path)
        self.verbose = verbose
        self.secrets = {}
        self.secret_consumers = {}  # Which services use which secrets

    def log(self, message):
        if self.verbose:
            print(f"  [secrets-scanner] {message}")

    def scan(self) -> Dict:
        """Scan for secrets definitions"""
        self.log("Scanning secrets...")

        secrets_domain = self.source_path / 'domains' / 'secrets'
        if not secrets_domain.exists():
            return {'secrets': [], 'total': 0}

        # Scan declarations
        declarations_dir = secrets_domain / 'declarations'
        if declarations_dir.exists():
            self._scan_declarations(declarations_dir)

        # Scan parts for encrypted files
        parts_dir = secrets_domain / 'parts'
        if parts_dir.exists():
            self._scan_encrypted_files(parts_dir)

        # Scan for secret usage
        self._scan_secret_usage()

        self.log(f"Found {len(self.secrets)} secrets")

        return {
            'secrets': list(self.secrets.values()),
            'total': len(self.secrets),
            'consumers': self.secret_consumers,
            'categories': self._categorize_secrets()
        }

    def _scan_declarations(self, declarations_dir: Path):
        """Scan secret declarations"""
        for decl_file in declarations_dir.rglob('*.nix'):
            self._extract_secret_declarations(decl_file)

    def _extract_secret_declarations(self, file_path: Path):
        """Extract secret declarations from .nix files"""
        try:
            with open(file_path, 'r') as f:
                content = f.read()

            # Find age.secrets.NAME declarations
            secret_pattern = r'age\.secrets\.([a-zA-Z0-9_-]+)\s*=\s*\{'
            for match in re.finditer(secret_pattern, content):
                secret_name = match.group(1)

                # Get the category from the file path
                category = self._infer_category_from_path(file_path)

                secret_info = {
                    'name': secret_name,
                    'category': category,
                    'declaration_file': str(file_path.relative_to(self.source_path)),
                    'encrypted_file': None,
                    'consumers': []
                }

                # Try to find the encrypted file reference
                encrypted_match = re.search(
                    rf'{secret_name}\s*=.*?file\s*=\s*[./]*parts/([^;]+\.age)',
                    content,
                    re.DOTALL
                )
                if encrypted_match:
                    secret_info['encrypted_file'] = f"parts/{encrypted_match.group(1)}"

                self.secrets[secret_name] = secret_info

        except Exception as e:
            self.log(f"Error extracting secrets from {file_path}: {e}")

    def _scan_encrypted_files(self, parts_dir: Path):
        """Scan for .age encrypted files"""
        for age_file in parts_dir.rglob('*.age'):
            secret_name = age_file.stem  # filename without .age extension

            # If this secret wasn't found in declarations, add it
            if secret_name not in self.secrets:
                category = self._infer_category_from_path(age_file)

                self.secrets[secret_name] = {
                    'name': secret_name,
                    'category': category,
                    'declaration_file': None,
                    'encrypted_file': str(age_file.relative_to(self.source_path)),
                    'consumers': []
                }

    def _scan_secret_usage(self):
        """Scan codebase for secret usage"""
        # Scan all .nix files for config.age.secrets.* references
        for nix_file in self.source_path.rglob('*.nix'):
            if 'secrets' in str(nix_file):
                continue  # Skip secret files themselves

            try:
                with open(nix_file, 'r') as f:
                    content = f.read()

                # Find secret references
                secret_refs = re.findall(r'config\.age\.secrets\.([a-zA-Z0-9_-]+)', content)

                for secret_name in set(secret_refs):
                    if secret_name in self.secrets:
                        consumer = self._infer_consumer_from_file(nix_file)
                        if consumer and consumer not in self.secrets[secret_name]['consumers']:
                            self.secrets[secret_name]['consumers'].append(consumer)

                        # Track reverse mapping
                        if consumer:
                            if consumer not in self.secret_consumers:
                                self.secret_consumers[consumer] = []
                            if secret_name not in self.secret_consumers[consumer]:
                                self.secret_consumers[consumer].append(secret_name)

            except Exception as e:
                pass

    def _infer_category_from_path(self, file_path: Path) -> str:
        """Infer secret category from file path"""
        path_str = str(file_path)

        if 'system' in path_str:
            return 'system'
        elif 'home' in path_str:
            return 'home'
        elif 'infrastructure' in path_str:
            return 'infrastructure'
        elif 'server' in path_str:
            return 'server'
        else:
            return 'other'

    def _infer_consumer_from_file(self, file_path: Path) -> str:
        """Infer which service/component is consuming the secret"""
        path_parts = file_path.parts

        # Look for container names
        if 'containers' in path_parts:
            idx = path_parts.index('containers')
            if idx + 1 < len(path_parts):
                return path_parts[idx + 1]

        # Look for service names
        if 'server' in path_parts:
            idx = path_parts.index('server')
            if idx + 1 < len(path_parts):
                component = path_parts[idx + 1]
                if component != 'containers':
                    return component

        return None

    def _categorize_secrets(self) -> Dict[str, List[str]]:
        """Categorize secrets by type"""
        categories = {
            'system': [],
            'home': [],
            'infrastructure': [],
            'server': [],
            'other': []
        }

        for secret_name, secret_info in self.secrets.items():
            category = secret_info['category']
            if category in categories:
                categories[category].append(secret_name)
            else:
                categories['other'].append(secret_name)

        # Remove empty categories
        return {k: v for k, v in categories.items() if v}

    def generate_sops_migration_guide(self, secrets: List[Dict]) -> Dict:
        """Generate a guide for migrating from agenix to SOPS"""
        migration = {
            'instructions': [],
            'sops_yaml_template': {},
            'age_key_location': '/etc/age/keys.txt'
        }

        # Build SOPS YAML structure
        yaml_structure = {}

        for secret in secrets:
            category = secret['category']
            name = secret['name']

            if category not in yaml_structure:
                yaml_structure[category] = {}

            yaml_structure[category][name] = 'REPLACE_WITH_VALUE'

        migration['sops_yaml_template'] = yaml_structure

        # Generate instructions
        migration['instructions'] = [
            "1. Install SOPS: sudo pacman -S sops (Arch) or appropriate package manager",
            "2. Copy age key from NixOS: sudo cat /etc/age/keys.txt > ~/.config/sops/age/keys.txt",
            "3. Create .sops.yaml in repository root with age key configuration",
            f"4. Create secrets.yaml with {len(secrets)} secrets using the template",
            "5. Encrypt with SOPS: sops -e -i secrets.yaml",
            "6. Deploy secrets using provided script",
        ]

        return migration
