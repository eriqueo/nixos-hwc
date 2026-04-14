# [Domain Name] Domain

## Purpose & Scope

**The [Domain Name] Domain** provides [primary purpose]. This domain manages [what it manages] and handles [what it handles]. It serves as [role in system].

**Key Principle**: If it's [decision criteria] → [domain name] domain. The [domain name] domain is the "[short description]" that [core value proposition].

## Domain Architecture

The [domain name] domain follows [architectural pattern] with **[organizing principle]**:

```
domains/[domain]/
├── index.nix                    # Domain aggregator
├── core/                        # Essential [domain] functionality
│   ├── [module1].nix           # [Description]
│   ├── [module2].nix           # [Description]
│   └── [module3].nix           # [Description]
├── [category1]/                 # [Category description]
│   ├── index.nix               # [Category] aggregator
│   ├── [item1]/                # [Item description]
│   ├── [item2]/                # [Item description]
│   └── ...                     # More [items]
├── [category2]/                 # [Category description]
└── parts/                      # Shared [domain] components
    ├── [helper1].nix           # [Helper description]
    ├── [helper2].nix           # [Helper description]
    └── [helper3].nix           # [Helper description]
```

## Domain Boundaries

### ✅ **This Domain Manages**
- [Responsibility 1]: [Detailed description]
- [Responsibility 2]: [Detailed description]
- [Responsibility 3]: [Detailed description]

### ❌ **This Domain Does NOT Manage**
- [Not responsible 1]: → Goes to `domains/[other-domain]/`
- [Not responsible 2]: → Goes to `domains/[other-domain]/`
- [Not responsible 3]: → Goes to `domains/[other-domain]/`

### 🔗 **Integration Points**
- **Consumes from**: `domains/[dependency1]/`, `domains/[dependency2]/`
- **Provides to**: `domains/[consumer1]/`, `domains/[consumer2]/`
- **Coordination**: [How this domain coordinates with others]

## Module Standards

### Standard Module Structure
```
domains/[domain]/[category]/[module]/
├── index.nix                   # Main [module] implementation
├── options.nix                 # API definition (REQUIRED)
├── sys.nix                     # System-lane integration (if needed)
└── parts/                      # Implementation details
    ├── config.nix              # Core configuration
    ├── lib.nix                 # Helper functions
    ├── scripts.nix             # Script generation
    └── [custom].nix            # Module-specific parts
```

### Option Namespace Pattern
```nix
# domains/[domain]/[category]/[module]/options.nix
options.hwc.[domain].[category].[module] = {
  enable = mkEnableOption "[Module description]";

  # Module-specific options following folder structure
  [option1] = mkOption { ... };
  [option2] = mkOption { ... };
};
```

### Implementation Pattern
```nix
# domains/[domain]/[category]/[module]/index.nix
{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.[domain].[category].[module];
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./options.nix
    ./sys.nix            # Only if system integration needed
    ./parts/config.nix   # Core implementation
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Module implementation here
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  assertions = [
    {
      assertion = !cfg.enable || config.hwc.[dependency].enable;
      message = "[Module] requires [dependency] to be enabled";
    }
  ];
}
```

## Core Modules

### 🔧 [Core Module 1] (`core/[module1].nix`)
**[Module description]**

**Provides:**
- [Capability 1]
- [Capability 2]
- [Capability 3]

**Configuration:**
```nix
hwc.[domain].[module1] = {
  enable = true;
  [option1] = [value];
  [option2] = [value];
};
```

### ⚙️ [Core Module 2] (`core/[module2].nix`)
**[Module description]**

**Provides:**
- [Capability 1]
- [Capability 2]
- [Capability 3]

## Best Practices

### ✅ **Do**
- **[Practice 1]**: [Detailed explanation]
- **[Practice 2]**: [Detailed explanation]
- **[Practice 3]**: [Detailed explanation]

### ❌ **Don't**
- **[Anti-pattern 1]**: [Why not and what to do instead]
- **[Anti-pattern 2]**: [Why not and what to do instead]
- **[Anti-pattern 3]**: [Why not and what to do instead]

### 🔍 **Common Patterns**
```nix
# Pattern 1: [Pattern name]
# Use case: [When to use]
[pattern1] = {
  # Implementation
};

# Pattern 2: [Pattern name]
# Use case: [When to use]
[pattern2] = {
  # Implementation
};
```

## Development Workflow

### Adding New [Items]
1. **Create [item] directory**: `mkdir -p domains/[domain]/[category]/[item]/`
2. **Follow module standards**: Create `index.nix`, `options.nix`, `parts/config.nix`
3. **Define namespace**: `hwc.[domain].[category].[item].*`
4. **Add to aggregator**: Include in `domains/[domain]/[category]/index.nix`
5. **Enable in profiles**: Add enable options to appropriate profiles

### Testing Changes
```bash
# Build domain changes
sudo nixos-rebuild build --flake .#hwc-[machine]

# Test specific module
nix eval .#nixosConfigurations.hwc-[machine].config.hwc.[domain].[category].[item].enable

# Verify implementation
[domain-specific verification commands]
```

## Profile Integration

### Profile Enablement
```nix
# profiles/[profile].nix
hwc.[domain].[category].[item].enable = true;
```

### Cross-Domain Dependencies
```nix
# This domain provides capabilities consumed by:
# domains/[consumer1]/ - [How it's consumed]
# domains/[consumer2]/ - [How it's consumed]

# This domain consumes capabilities from:
# domains/[provider1]/ - [What it consumes]
# domains/[provider2]/ - [What it consumes]
```

## Validation & Troubleshooting

### Verify Configuration
```bash
# Check domain module status
systemctl status [domain-service]

# Verify options evaluated correctly
nix eval .#nixosConfigurations.hwc-[machine].config.hwc.[domain]

# Check for conflicts
nixos-rebuild build --flake .#hwc-[machine] --show-trace
```

### Common Issues
- **Issue 1**: [Description and solution]
- **Issue 2**: [Description and solution]
- **Issue 3**: [Description and solution]

## Reference Links

- **Charter**: `charter.md` - Complete HWC architecture
- **Filesystem**: `FILESYSTEM-CHARTER.md` - Home directory organization
- **Related Domains**:
  - `domains/[related1]/README.md` - [Relationship]
  - `domains/[related2]/README.md` - [Relationship]

---

**Domain Version**: [version] - [Description of current state]
**Charter Compliance**: [compliance level] with HWC Charter v6.0
**Last Updated**: [date]