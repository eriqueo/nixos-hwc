"""
Dotfiles Scanner - Identifies home-manager managed configurations

Scans home-manager configurations and creates a manifest for:
- Config file locations (~/.config/*)
- Dotfiles (~/.*)
- Application data (~/.local/share/*)
- Organizing them into GNU Stow compatible structure
"""

import re
from pathlib import Path
from typing import Dict, List


class DotfilesScanner:
    def __init__(self, source_path: Path, verbose: bool = False):
        self.source_path = Path(source_path)
        self.verbose = verbose
        self.dotfiles_apps = {}

    def log(self, message):
        if self.verbose:
            print(f"  [dotfiles-scanner] {message}")

    def scan(self) -> Dict:
        """Scan for home-manager managed applications"""
        self.log("Scanning for home-manager apps...")

        # Scan domains/home for application configurations
        home_domain = self.source_path / 'domains' / 'home'
        if not home_domain.exists():
            return {'apps': [], 'total': 0}

        # Scan apps directory
        apps_dir = home_domain / 'apps'
        if apps_dir.exists():
            self._scan_apps_directory(apps_dir)

        # Scan shell configs
        shell_dir = home_domain / 'shell'
        if shell_dir.exists():
            self._scan_shell_configs(shell_dir)

        self.log(f"Found {len(self.dotfiles_apps)} home-manager managed apps")

        return {
            'apps': list(self.dotfiles_apps.values()),
            'total': len(self.dotfiles_apps),
            'categories': self._categorize_apps()
        }

    def _scan_apps_directory(self, apps_dir: Path):
        """Scan the apps directory for individual app configs"""
        for app_dir in apps_dir.iterdir():
            if app_dir.is_dir() and app_dir.name != 'index.nix':
                self._scan_app_module(app_dir)

    def _scan_app_module(self, app_dir: Path):
        """Scan a single app module"""
        app_name = app_dir.name
        self.log(f"Scanning {app_name}...")

        app_info = {
            'name': app_name,
            'config_paths': [],
            'dotfiles': [],
            'stow_package': app_name,
            'priority': self._get_priority(app_name),
            'source_dir': str(app_dir.relative_to(self.source_path))
        }

        # Try to extract config details from index.nix
        index_file = app_dir / 'index.nix'
        if index_file.exists():
            self._extract_config_paths(index_file, app_info)

        # Infer standard paths for known apps
        self._infer_standard_paths(app_name, app_info)

        self.dotfiles_apps[app_name] = app_info

    def _scan_shell_configs(self, shell_dir: Path):
        """Scan shell configuration"""
        shell_apps = ['zsh', 'bash', 'starship', 'tmux', 'neovim']

        for shell_app in shell_apps:
            app_dir = shell_dir / shell_app
            if app_dir.exists():
                self._scan_app_module(app_dir)

    def _extract_config_paths(self, file_path: Path, app_info: Dict):
        """Extract configuration file paths from Nix config"""
        try:
            with open(file_path, 'r') as f:
                content = f.read()

            # Look for programs.APP configuration
            app_name = app_info['name']

            # Check if it's a programs.* config
            if re.search(rf'programs\.{app_name}\s*=', content):
                app_info['config_paths'].append(f"~/.config/{app_name}")

            # Check for specific file paths
            xdg_match = re.findall(r'xdg\.configFile\."([^"]+)"', content)
            for path in xdg_match:
                app_info['config_paths'].append(f"~/.config/{path}")

            # Check for home.file references
            home_file_match = re.findall(r'home\.file\."([^"]+)"', content)
            for path in home_file_match:
                app_info['dotfiles'].append(f"~/{path}")

        except Exception as e:
            self.log(f"Error extracting paths from {file_path}: {e}")

    def _infer_standard_paths(self, app_name: str, app_info: Dict):
        """Infer standard config paths for known applications"""
        # Map of app name to their standard config locations
        standard_paths = {
            'hyprland': ['~/.config/hypr/hyprland.conf'],
            'waybar': ['~/.config/waybar/config', '~/.config/waybar/style.css'],
            'kitty': ['~/.config/kitty/kitty.conf'],
            'neovim': ['~/.config/nvim'],
            'tmux': ['~/.config/tmux/tmux.conf', '~/.tmux.conf'],
            'zsh': ['~/.zshrc', '~/.zshenv'],
            'starship': ['~/.config/starship.toml'],
            'git': ['~/.gitconfig'],
            'chromium': ['~/.config/chromium'],
            'librewolf': ['~/.librewolf'],
            'aerc': ['~/.config/aerc'],
            'neomutt': ['~/.config/neomutt'],
            'gpg': ['~/.gnupg/gpg.conf'],
            'obsidian': ['~/.config/obsidian'],
            'yazi': ['~/.config/yazi'],
            'thunar': ['~/.config/Thunar'],
        }

        if app_name in standard_paths:
            # Add to config_paths if not already there
            for path in standard_paths[app_name]:
                if path not in app_info['config_paths']:
                    app_info['config_paths'].append(path)

    def _get_priority(self, app_name: str) -> int:
        """Get extraction priority (higher = more important)"""
        # Critical dotfiles (shell, editor, terminal)
        if app_name in ['zsh', 'bash', 'neovim', 'tmux', 'git', 'starship']:
            return 100

        # Desktop environment
        if app_name in ['hyprland', 'waybar', 'kitty', 'rofi', 'wofi']:
            return 90

        # Important apps
        if app_name in ['chromium', 'librewolf', 'obsidian', 'aerc', 'neomutt']:
            return 80

        # Other apps
        return 50

    def _categorize_apps(self) -> Dict[str, List[str]]:
        """Categorize apps by type"""
        categories = {
            'shell': [],
            'editor': [],
            'terminal': [],
            'desktop': [],
            'browser': [],
            'mail': [],
            'productivity': [],
            'other': []
        }

        for app_name, app_info in self.dotfiles_apps.items():
            if app_name in ['zsh', 'bash', 'fish', 'starship']:
                categories['shell'].append(app_name)
            elif app_name in ['neovim', 'vim', 'emacs']:
                categories['editor'].append(app_name)
            elif app_name in ['kitty', 'alacritty', 'wezterm']:
                categories['terminal'].append(app_name)
            elif app_name in ['hyprland', 'waybar', 'rofi', 'wofi', 'swaync']:
                categories['desktop'].append(app_name)
            elif app_name in ['chromium', 'librewolf', 'firefox']:
                categories['browser'].append(app_name)
            elif app_name in ['aerc', 'neomutt', 'thunderbird', 'betterbird']:
                categories['mail'].append(app_name)
            elif app_name in ['obsidian', 'onlyoffice', 'libreoffice']:
                categories['productivity'].append(app_name)
            else:
                categories['other'].append(app_name)

        # Remove empty categories
        return {k: v for k, v in categories.items() if v}

    def generate_stow_manifest(self, apps: List[Dict]) -> Dict:
        """Generate a manifest for GNU Stow structure"""
        manifest = {
            'stow_packages': [],
            'instructions': []
        }

        # Sort by priority
        sorted_apps = sorted(apps, key=lambda x: x.get('priority', 0), reverse=True)

        for app in sorted_apps:
            package = {
                'name': app['stow_package'],
                'priority': app['priority'],
                'files': app['config_paths'] + app['dotfiles']
            }
            manifest['stow_packages'].append(package)

            # Generate installation instruction
            instruction = f"stow {app['stow_package']}"
            manifest['instructions'].append(instruction)

        return manifest
