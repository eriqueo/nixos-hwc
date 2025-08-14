# Day 6: Complex Services & GPU (5-6 hours)

## Morning Session (3 hours)
### 9:00 AM - GPU Infrastructure ✅

```bash
cd /etc/nixos-next

# Step 1: Create comprehensive GPU module
cat > modules/infrastructure/gpu.nix << 'EOF'
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.gpu;
in {
  options.hwc.gpu = {
    nvidia = {
      enable = lib.mkEnableOption "NVIDIA GPU support";
      
      driver = lib.mkOption {
        type = lib.types.enum [ "stable" "beta" "production" ];
        default = "stable";
        description = "Driver version";
      };
      
      cuda = {
        enable = lib.mkEnableOption "CUDA support";
        version = lib.mkOption {
          type = lib.types.str;
          default = "12";
          description = "CUDA version";
        };
      };
      
      containerRuntime = lib.mkEnableOption "Container GPU support";
      
      powerManagement = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable power management";
      };
    };
    
    allocation = lib.mkOption {
      type = lib.types.attrsOf lib.types.attrs;
      default = {};
      description = "GPU resource allocation per service";
      example = {
        frigate = { memory = "4GB"; priority = "high"; };
        jellyfin = { memory = "2GB"; priority = "medium"; };
        ollama = { memory = "8GB"; priority = "low"; };
      };
    };
  };
  
  config = lib.mkIf cfg.nvidia.enable {
    # GPU implementation goes here
  };
}
EOF
```
