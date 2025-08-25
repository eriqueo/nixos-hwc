# Laptop Configuration Comparison Report

## Critical Differences Found

### Hardware Configuration
- ✅ **FIXED**: Hardware configuration copied from production

### Missing in Refactor

### Services Status
| Service | Production | Refactor | Status |
|---------|------------|----------|--------|
| greetd | ❌ | ❌ | ℹ️  N/A |
| nvidia | ✅ | ✅ | ✅ OK |
| libvirtd | ❌ | ❌ | ℹ️  N/A |
| samba | ❌ | ❌ | ℹ️  N/A |
| printing | ❌ | ❌ | ℹ️  N/A |
| tlp | ✅ | ✅ | ✅ OK |
| thermald | ✅ | ✅ | ✅ OK |
| pipewire | ❌ | ❌ | ℹ️  N/A |

## Action Items Required

### 🔥 Critical (System Won't Work)
- [ ] Enable NVIDIA GPU configuration with PRIME
- [ ] Configure greetd login manager
- [ ] Fix container runtime (switch to Podman)

### 🚨 Important (Core Functionality)
- [ ] Enable libvirtd for VM support
- [ ] Configure Samba for SketchUp share
- [ ] Set up printing drivers
- [ ] Enable SOPS secrets management

### ⚠️ Nice-to-Have (Quality of Life)
- [ ] Add missing system packages
- [ ] Verify Home Manager equivalency
- [ ] Test all hardware features
