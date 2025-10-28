# WinApps Excel Setup Guide

**Goal**: Set up WinApps to run Microsoft Excel with full Power Query support on Linux, appearing as a native application.

**Current Status**: NixOS with virtualization infrastructure enabled (libvirtd, QEMU/KVM, virt-manager available)

---

## Prerequisites ✅ (Already Complete)

- [x] KVM/QEMU virtualization enabled
- [x] virt-manager, virsh, qemu-system-x86_64 available
- [x] libvirtd service running
- [x] User in libvirt group (handled by NixOS configuration)

---

## Phase 1: Install WinApps and Dependencies

### 1.1 Install Required Packages

Add the following packages to your NixOS configuration:

```nix
# Add to environment.systemPackages in machines/laptop/config.nix
environment.systemPackages = with pkgs; [
  # WinApps dependencies
  git
  freerdp3  # RDP client for connecting to Windows VM
  xdg-utils # For desktop integration
];

# Ensure FreeRDP is properly configured
programs.xfreeRDP.enable = true;
```

### 1.2 Clone and Install WinApps

```bash
# Clone WinApps repository
cd ~/03-tech/local-storage
git clone https://github.com/winapps-org/winapps.git
cd winapps

# Make installer executable
chmod +x install.sh

# Install WinApps (will install to ~/.local/bin)
./install.sh
```

---

## Phase 2: Create Windows VM for WinApps

### 2.1 Download Windows 10/11 ISO

**Required**: Windows 10 Pro or Windows 11 Pro (RDP support needed)

```bash
# Download Windows 11 ISO (example - use official Microsoft links)
cd ~/03-tech/local-storage
wget "https://software-download.microsoft.com/..." -O windows11.iso
```

### 2.2 Create VM with virt-manager

```bash
# Launch virt-manager
virt-manager
```

**VM Configuration Requirements**:
- **Name**: `RDPWindows` (CRITICAL: WinApps requires this exact name)
- **RAM**: 8GB minimum (16GB recommended for Excel + Power Query)
- **Storage**: 60GB minimum (100GB recommended)
- **Network**: Default NAT network
- **Display**: QXL or VirtIO-GPU

**Step-by-step VM creation**:
1. Click "Create a new virtual machine"
2. Choose "Local install media (ISO image or CDROM)"
3. Browse and select your Windows ISO
4. Set RAM: 8192 MB (8GB) minimum
5. Set disk: 60GB minimum
6. **IMPORTANT**: Name the VM exactly `RDPWindows`
7. Check "Customize configuration before install"
8. In customization:
   - **CPU**: Set to 4 cores minimum
   - **Display**: Set to "QXL" or "VirtIO-GPU"
   - **Network**: Ensure NAT mode

### 2.3 Install Windows in VM

1. Start the VM and install Windows 10/11 Pro
2. Complete Windows setup with a user account
3. **CRITICAL**: Note the username and password - you'll need these for WinApps

**Windows Configuration Requirements**:
- Use Windows 10/11 **Pro** (RDP support required)
- Create a user account (remember credentials)
- Connect to internet during setup

---

## Phase 3: Configure Windows for RDP Access

### 3.1 Enable RDP in Windows

In the Windows VM:

1. **Enable RDP**:
   - Right-click "This PC" → Properties
   - Click "Advanced system settings"
   - Go to "Remote" tab
   - Check "Enable Remote Desktop"
   - Click "OK"

2. **Configure Windows User**:
   - Go to Settings → Accounts → Sign-in options
   - Set up a PIN or password (required for RDP)

3. **Disable Network Level Authentication** (if needed):
   - In Remote settings → Advanced
   - Uncheck "Require Network Level Authentication"

### 3.2 Configure Windows Firewall

```cmd
# In Windows Command Prompt (Run as Administrator)
netsh advfirewall firewall set rule group="Remote Desktop" new enable=yes
```

### 3.3 Get Windows VM IP Address

In Windows VM:
```cmd
ipconfig
```
Note the IP address (usually 192.168.122.x)

---

## Phase 4: Install Microsoft Office in Windows VM

### 4.1 Download and Install Office

In the Windows VM:

1. **Download Office**:
   - Go to office.com
   - Sign in with Microsoft account
   - Download Office 365 or Office 2021

2. **Install Office**:
   - Run the installer
   - Choose "Install Office"
   - Wait for download and installation
   - **IMPORTANT**: Install the full desktop version, not web apps

3. **Activate Office**:
   - Open Excel
   - Sign in with your Microsoft account
   - Activate your Office license

### 4.2 Test Excel Power Query

In Excel:
1. Go to **Data** tab
2. Click **Get Data** → should see Power Query options
3. Test a simple query to ensure Power Query is working

---

## Phase 5: Configure WinApps Connection

### 5.1 Create WinApps Configuration

```bash
# Create WinApps config directory
mkdir -p ~/.config/winapps

# Create configuration file
cat > ~/.config/winapps/winapps.conf << 'EOF'
# RDP Connection Settings
RDP_USER="YourWindowsUsername"     # Replace with your Windows username
RDP_PASS="YourWindowsPassword"     # Replace with your Windows password
RDP_DOMAIN=""                      # Usually leave empty for local accounts
RDP_IP="192.168.122.X"            # Replace X with your VM's IP address

# Display Settings
RDP_SCALE=100                      # Scale percentage (100 = no scaling)
RDP_FLAGS="/cert-ignore /dynamic-resolution /audio-mode:1"

# VM Settings
MULTIMON="true"                    # Enable multi-monitor support
DEBUG="false"                      # Set to true for troubleshooting
EOF
```

### 5.2 Test RDP Connection

```bash
# Test manual RDP connection
xfreerdp3 /v:192.168.122.X /u:YourUsername /p:YourPassword /cert:ignore
```

If this works, you should see the Windows desktop. Close it and proceed.

---

## Phase 6: Configure WinApps Applications

### 6.1 Install Excel Application Definition

```bash
# Run WinApps installer for specific apps
cd ~/03-tech/local-storage/winapps
./winapps install excel

# This should create:
# - ~/.local/share/applications/Excel.desktop
# - Icons and menu entries
```

### 6.2 Test WinApps Excel

```bash
# Launch Excel through WinApps
winapps excel

# Or use the desktop launcher
# Should appear in your applications menu as "Microsoft Excel"
```

---

## Phase 7: Desktop Integration and Optimization

### 7.1 Verify Desktop Integration

After successful setup:
- Excel should appear in your application launcher
- Excel icon should be in your desktop environment
- Files should open with Excel when double-clicked (if configured)

### 7.2 Optimize Performance

**Windows VM Optimizations**:
1. **Disable Windows visual effects**:
   - Control Panel → System → Advanced → Performance Settings
   - Choose "Adjust for best performance"

2. **Disable Windows updates** (optional):
   - Settings → Update & Security → Windows Update
   - Pause updates for development VM

3. **Install Windows Guest Tools**:
   - In virt-manager: Virtual Machine → Install Guest Tools
   - Improves performance and clipboard sharing

**Linux Host Optimizations**:
```nix
# Add to your NixOS configuration for better VM performance
boot.kernelModules = [ "kvm-intel" ]; # or "kvm-amd"
virtualisation.libvirtd.qemu.verbatimConfig = ''
  cpu_map = 1
'';
```

---

## Phase 8: Troubleshooting Common Issues

### 8.1 RDP Connection Issues

**Problem**: Cannot connect to Windows VM
**Solutions**:
1. Check VM IP: `virsh domifaddr RDPWindows`
2. Verify RDP enabled in Windows
3. Check Windows firewall settings
4. Try disabling Network Level Authentication

### 8.2 Excel Won't Launch

**Problem**: Excel opens but crashes or doesn't appear
**Solutions**:
1. Check RDP connection manually: `xfreerdp3 /v:IP /u:user /p:pass`
2. Verify Office is properly installed and activated
3. Check WinApps logs: `winapps check`

### 8.3 Performance Issues

**Problem**: Excel runs slowly
**Solutions**:
1. Increase VM RAM (16GB recommended)
2. Assign more CPU cores to VM
3. Enable hardware acceleration in VM
4. Close unnecessary Windows services

### 8.4 Power Query Issues

**Problem**: Power Query features missing or not working
**Solutions**:
1. Ensure you installed Office 365 or Office 2021 (not older versions)
2. Check Excel license activation
3. Test Power Query in Windows VM directly first
4. Verify internet connection in VM for cloud data sources

---

## Phase 9: Usage and Workflow

### 9.1 Daily Usage

**Starting Excel**:
```bash
# Command line
winapps excel

# Desktop launcher
# Look for "Microsoft Excel" in applications menu
```

**File Management**:
- Excel files opened from Linux file manager will launch in WinApps Excel
- Save files to locations accessible from both Linux and Windows
- Use shared folders or cloud storage for seamless access

### 9.2 Power Query Workflow

**Typical Power Query usage**:
1. Open Excel through WinApps
2. Data → Get Data → Choose your data source
3. Use Power Query Editor for transformations
4. Load data back to Excel
5. Create pivot tables, charts, etc.
6. Save workbook to shared location

---

## Phase 10: Backup and Maintenance

### 10.1 VM Backup

```bash
# Create VM snapshot
virsh snapshot-create-as RDPWindows "clean-office-install" "Fresh Office installation"

# List snapshots
virsh snapshot-list RDPWindows

# Restore snapshot if needed
virsh snapshot-revert RDPWindows "clean-office-install"
```

### 10.2 WinApps Updates

```bash
# Update WinApps
cd ~/03-tech/local-storage/winapps
git pull
./install.sh
```

---

## Success Criteria

You'll know the setup is complete and working when:

- [x] Excel launches from Linux application menu
- [x] Excel appears as a native Linux window
- [x] Power Query functionality works (Data → Get Data)
- [x] Can save/open Excel files from Linux file system
- [x] Performance is acceptable for daily use
- [x] No RDP connection issues

---

## Estimated Time Investment

- **Phase 1-2**: 30 minutes (packages, VM creation)
- **Phase 3**: 45 minutes (Windows install and configuration)
- **Phase 4**: 30 minutes (Office installation)
- **Phase 5-6**: 45 minutes (WinApps configuration and testing)
- **Phase 7-8**: 30 minutes (optimization and troubleshooting)

**Total**: ~3-4 hours for complete setup

---

## Alternative Quick Setup (If Available)

If you have access to a pre-configured Windows VM with Office:
1. Import existing VM and rename to "RDPWindows"
2. Skip to Phase 5 (WinApps configuration)
3. Total setup time: ~1 hour

---

*This document will be updated as you progress through the setup. Keep it as reference for troubleshooting and future maintenance.*