# Home Domain

## Purpose & Scope

The **Home Domain** provides **user environment configuration** via Home Manager integration. This domain manages user-scoped applications, configurations, theming, and personal productivity tools. It handles everything that runs in userspace and personalizes the computing experience.

**Key Principle**: If it's user-scoped configuration, user applications, or personal environment setup → home domain. The home domain is the "user personalization layer" that makes the system individually useful.

## Domain Architecture

The home domain follows Home Manager patterns with **universal domain organization**:

```
domains/home/
├── index.nix                    # Domain aggregator (HM entry point)
├── core/                        # Essential user environment
│   ├── theme.nix               # System-wide theming
│   ├── shell.nix               # Shell environment (zsh, starship)
│   └── behavior.nix            # User input behavior and preferences
├── apps/                        # User applications
│   ├── index.nix               # Apps aggregator
│   ├── hyprland/               # Wayland compositor
│   ├── waybar/                 # Status bar  
│   ├── kitty/                  # Terminal emulator
│   ├── chromium/               # Web browser
│   ├── betterbird/             # Email client
│   └── ...                     # More applications
└── parts/                       # Shared configuration components
    ├── appearance.nix          # Visual theming components
    ├── behavior.nix            # Input/interaction behavior
    └── session.nix             # Session management helpers
```

## Universal Domain Pattern

Each application follows the **Universal Domain Pattern** with standardized parts:

```
domains/home/apps/<app>/
├── index.nix                   # Main HM configuration
├── sys.nix                     # System integration (imported by profiles/sys.nix)
└── parts/                      # Universal domain components
    ├── appearance.nix          # App theming and visual config
    ├── behavior.nix            # App behavior and keybindings
    └── session.nix             # App session management
```

### Universal Domain Components

**Appearance** (`parts/appearance.nix`):
- Theming integration (colors, fonts, icons)
- Visual configuration (window decorations, layouts)
- Style consistency across applications

**Behavior** (`parts/behavior.nix`):
- Keybindings and shortcuts
- Input method configuration
- Application-specific behavior settings

**Session** (`parts/session.nix`):
- Startup/shutdown behavior
- Session persistence
- Integration with session managers

## Core Modules (`core/`)

### 🎨 Theme (`theme.nix`)
**System-wide theming and visual consistency**

**Provides:**
- Color palette management (Nord, Dracula, etc.)
- Font configuration and fallbacks
- Icon theme integration
- GTK/Qt theming coordination

**Option Pattern:**
```nix
hwc.home.theme = {
  enable = true;
  palette = "nord" | "dracula" | "gruvbox" | "deep-nord";
  fonts = {
    system = "Inter";
    mono = "JetBrains Mono";
    size = {
      small = 10;
      normal = 11;
      large = 12;
    };
  };
  icons = "papirus" | "adwaita";
  cursor = {
    theme = "Adwaita";
    size = 24;
  };
};
```

**Implementation:**
```nix
# GTK theming
gtk = {
  enable = true;
  theme = themeConfig.gtkTheme;
  iconTheme = themeConfig.iconTheme;
  font = themeConfig.systemFont;
};

# Qt theming  
qt = {
  enable = true;
  platformTheme = "gtk";
  style = themeConfig.qtStyle;
};

# Cursor theming
home.pointerCursor = themeConfig.cursorConfig;
```

### 🐚 Shell (`shell.nix`)
**Shell environment and command-line experience**

**Provides:**
- ZSH configuration with modern features
- Starship prompt customization
- Modern Unix tool integration (bat, exa, fd, rg)
- Shell aliases and functions
- Git integration and aliases

**Option Pattern:**
```nix
hwc.home.shell = {
  enable = true;
  modernUnix = true;      # bat, exa, fd, ripgrep, etc.
  git = {
    enable = true;
    username = "Eric";
    email = "eric@example.com";
  };
  zsh = {
    enable = true;
    starship = true;
    autosuggestions = true;
    syntaxHighlighting = true;
    historySize = 10000;
  };
};
```

### ⌨️ Behavior (`behavior.nix`)
**User input behavior and interaction preferences**

**Provides:**
- Global keybinding preferences
- Input method configuration
- Accessibility settings
- User interaction patterns

**Option Pattern:**
```nix
hwc.home.behavior = {
  enable = true;
  keyboard = {
    repeatDelay = 200;
    repeatRate = 50;
  };
  mouse = {
    accelProfile = "adaptive";
    sensitivity = 0.5;
  };
  accessibility = {
    enable = false;
    largerText = false;
    highContrast = false;
  };
};
```

## Application Architecture

### Application Template Structure

Each application follows a consistent structure:

```nix
# domains/home/apps/<app>/index.nix
{ lib, pkgs, config, ... }:

let 
  cfg = config.features.<app>;
  themeCfg = config.hwc.home.theme;
in {
  #============================================================================
  # OPTIONS - Application Configuration
  #============================================================================
  options.features.<app> = {
    enable = lib.mkEnableOption "<App> application";
    
    # App-specific options
    fontSize = lib.mkOption {
      type = lib.types.int;
      default = themeCfg.fonts.size.normal;
      description = "Application font size";
    };
  };

  #============================================================================  
  # IMPLEMENTATION - Home Manager Configuration
  #============================================================================
  config = lib.mkIf cfg.enable {
    
    # Package installation
    home.packages = [ pkgs.<app> ];
    
    # Configuration files
    home.file.".config/<app>/config.toml".text = ''
      # App configuration here
    '';
    
    # XDG desktop integration
    xdg.desktopEntries.<app> = {
      name = "<App>";
      genericName = "Application";
      exec = "<app>";
      categories = [ "Application" ];
    };
    
    # Future: Universal domain integration
    # appearance = import ./parts/appearance.nix { inherit lib pkgs config; };
    # behavior = import ./parts/behavior.nix { inherit lib pkgs config; };  
    # session = import ./parts/session.nix { inherit lib pkgs config; };
  };
}
```

### System Integration Pattern

Each application also provides system integration:

```nix
# domains/home/apps/<app>/sys.nix  
{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.infrastructure.session.<app>;
in {
  options.hwc.infrastructure.session.<app> = {
    enable = lib.mkEnableOption "<App> system integration";
  };
  
  config = lib.mkIf cfg.enable {
    # System services needed by the app
    services.dbus.enable = lib.mkDefault true;
    programs.dconf.enable = lib.mkDefault true;
    
    # No user packages - HM handles those
  };
}
```

## Current Application Implementations

### 🌊 Hyprland Compositor
**Wayland compositor with advanced features**

**Key Features:**
- Advanced window management and workspaces  
- GPU acceleration integration
- Multi-monitor support with per-monitor workspaces
- Custom keybindings and window rules
- Integration with waybar and other tools

**Configuration Highlights:**
```nix
programs.hyprland = {
  enable = true;
  settings = {
    # GPU integration from infrastructure
    env = "WLR_NO_HARDWARE_CURSORS,1";
    
    # Keybindings with gpu-launch integration
    bind = [
      "SUPER, B, exec, gpu-launch chromium"
      "SUPER, Return, exec, kitty"
    ];
    
    # Workspace management
    workspace = [
      "1, monitor:DP-1"
      "2, monitor:DP-2"  
    ];
  };
};
```

### 📊 Waybar Status Bar  
**Highly customizable status bar**

**Key Features:**
- System monitoring (CPU, memory, GPU)
- Custom modules and scripts
- Click actions for system control
- Theme integration with CSS styling
- Multi-monitor support

### 🖥️ Kitty Terminal
**GPU-accelerated terminal emulator**

**Key Features:**
- GPU acceleration for smooth rendering
- Advanced text rendering with ligatures
- Tab and window management
- Theme integration
- Shell integration

### 🌐 Chromium Browser
**Open-source web browser**

**Integration Pattern:**
- **HM Side**: `features.chromium.enable = true` → installs `home.packages = [ pkgs.chromium ]`
- **System Side**: `hwc.infrastructure.session.chromium.enable = true` → provides dbus/dconf
- **Result**: Browser works with system integration + available for `gpu-launch chromium`

## Home Domain Integration Patterns

### Theme Propagation
Themes flow from core to applications:

```nix
# Core theme configuration  
hwc.home.theme.palette = "nord";

# Applications consume theme
config.programs.kitty.settings.foreground = themeCfg.colors.foreground;
config.programs.waybar.style = themeCfg.waybar.css;
```

### Shell Environment Integration  
```nix
# Core shell provides tools
hwc.home.shell.modernUnix = true;  # bat, exa, fd, rg

# Applications can assume tools exist
programs.git.delta.enable = true;  # Uses bat for syntax highlighting
```

### Cross-Application Coordination
```nix
# Hyprland launches other HM applications
bind = [
  "SUPER, Return, exec, ${config.programs.kitty.package}/bin/kitty"
  "SUPER, B, exec, gpu-launch chromium"  # System + HM integration
];

# Waybar shows status from other applications
modules-right = [ "custom/gpu" "network" "audio" ];
```

## Profile Integration

Home domain integrates with the system via specific profiles:

### HM Profile (`profiles/hm.nix`)
```nix
home-manager.users.eric = {
  imports = [ ../domains/home/index.nix ];
  
  # Application enables
  features = {
    hyprland.enable = true;
    waybar.enable = true; 
    kitty.enable = true;
    chromium.enable = true;
    betterbird.enable = true;
  };
  
  # Core environment
  hwc.home.theme.palette = "deep-nord";
  hwc.home.shell.enable = true;
};
```

### System Integration (`profiles/sys.nix`)
```nix
# Auto-imports all domains/home/apps/*/sys.nix files
gatherSys ../domains/home/apps;

# Results in system integration for:
# - hwc.infrastructure.session.chromium.*
# - hwc.infrastructure.session.kitty.*
# - etc.
```

## Development Workflow

### Adding New Applications

1. **Create application directory**:
   ```bash
   mkdir -p domains/home/apps/myapp/parts/
   ```

2. **Create main HM configuration**:
   ```nix
   # domains/home/apps/myapp/index.nix
   options.features.myapp.enable = lib.mkEnableOption "MyApp";
   config = lib.mkIf cfg.enable {
     home.packages = [ pkgs.myapp ];
   };
   ```

3. **Create system integration**:
   ```nix  
   # domains/home/apps/myapp/sys.nix
   options.hwc.infrastructure.session.myapp.enable = lib.mkEnableOption "MyApp system integration";
   config = lib.mkIf cfg.enable {
     services.dbus.enable = true;
   };
   ```

4. **Enable in profiles**:
   ```nix
   # profiles/hm.nix
   features.myapp.enable = true;
   
   # profiles/workstation.nix  
   hwc.infrastructure.session.myapp.enable = true;
   ```

### Theme Development
```nix
# Add new color palette
hwc.home.theme.palettes.custom = {
  foreground = "#ffffff";
  background = "#000000";
  # ... full color specification
};

# Applications automatically consume new palette
```

## Validation & Troubleshooting

### Check HM Configuration
```bash
# Verify HM generation
home-manager generations

# Check specific app configuration
nix eval .#homeConfigurations.eric.config.programs.hyprland.enable
```

### Check Application Integration  
```bash
# Verify packages installed
nix-env -q | grep chromium

# Check system integration
nix eval .#nixosConfigurations.hwc-laptop.config.hwc.infrastructure.session.chromium.enable
```

### Check Theme Application
```bash
# Verify theme files
ls -la ~/.config/gtk-3.0/
cat ~/.config/waybar/style.css
```

## Anti-Patterns

**❌ Don't implement system services in home domain**:
```nix
# Wrong - system services belong in system/services
systemd.services.myservice = { ... };
```

**❌ Don't configure hardware in home domain**:
```nix
# Wrong - hardware belongs in infrastructure  
hardware.pulseaudio.enable = true;
```

**❌ Don't install system packages in home domain**:
```nix
# Wrong - system tools belong in system packages
home.packages = [ pkgs.docker ];  # System-level tool
```

**✅ Do manage user applications and config**:
```nix
# Correct - user-scoped applications
home.packages = [ pkgs.chromium pkgs.kitty ];
programs.git.enable = true;
```

**✅ Do provide user environment personalization**:
```nix
# Correct - user preferences and theming
programs.hyprland.settings.bind = [ ... ];
gtk.theme = themeCfg.gtkTheme;
```

**✅ Do integrate with system capabilities**:
```nix
# Correct - consuming system/infrastructure capabilities  
programs.hyprland.settings.bind = [
  "SUPER, B, exec, gpu-launch chromium"  # Uses system gpu-launch
];
```

---

The home domain provides **comprehensive user environment management** through Home Manager, delivering a personalized, themed, and well-integrated desktop experience while maintaining clean separation from system and infrastructure concerns.

<function_calls>
<invoke name="TodoWrite">
<parameter name="todos">[{"content": "Create infrastructure domain README.md with 3-bucket architecture", "status": "completed", "activeForm": "Creating infrastructure domain README"}, {"content": "Create hardware bucket README.md (GPU, permissions, peripherals, storage)", "status": "completed", "activeForm": "Creating hardware bucket README"}, {"content": "Create session bucket README.md (services, commands, chromium)", "status": "completed", "activeForm": "Creating session bucket README"}, {"content": "Create mesh bucket README.md (container networking)", "status": "completed", "activeForm": "Creating mesh bucket README"}, {"content": "Create system domain README.md", "status": "completed", "activeForm": "Creating system domain README"}, {"content": "Create services domain README.md", "status": "completed", "activeForm": "Creating services domain README"}, {"content": "Create home domain README.md", "status": "completed", "activeForm": "Creating home domain README"}]