# Agenix Integration Fix Blueprint

**Problem**: Agenix secrets decrypt during build but sudo authentication fails  
**Charter Violations**: System domain user management, service dependencies  
**Status**: Critical - User authentication broken despite secret availability

---

## **Root Cause Analysis**

### **Current Broken State**
```bash
# Agenix decryption works during build
[agenix] decrypting 'user-initial-password.age' ✓
[agenix] symlinking new secrets ✓

# BUT sudo fails with password prompts
sudo nixos-rebuild switch
# Prompts for password, configured password doesn't work
```

### **Charter v3 Issues**

#### **System Domain Incomplete** (Charter §3.2)
- **User authentication chain broken**: Secret → User password linkage not working
- **Service dependency violation**: User creation may occur before secret availability  
- **Fallback mechanism unreliable**: Emergency access not properly configured

#### **Secret Integration Pattern Wrong**
```nix
# ❌ CURRENT STATE - modules/home/eric.nix
users.users.eric = {
  hashedPasswordFile = config.age.secrets.user-initial-password.path;
  # Secret path may not exist during user creation
};
```

---

## **Fix Strategy**

### **Proper Secret → User Linkage** (System Domain)

#### **Phase 1: Service Ordering** (Charter §5.2)
```nix
# ✅ CORRECT - Ensure agenix runs before user creation
systemd.services.agenix.before = [ "systemd-user-sessions.service" ];
systemd.services.agenix.wantedBy = [ "multi-user.target" ];

# User creation depends on secret availability
users.users.eric = {
  hashedPasswordFile = 
    lib.mkIf config.hwc.home.user.useSecrets 
      config.age.secrets.user-initial-password.path;
  initialPassword = 
    lib.mkIf (!config.hwc.home.user.useSecrets && cfg.user.fallbackPassword != null)
      cfg.user.fallbackPassword;
};
```

#### **Phase 2: Fallback Chain** (System Domain Safety)
```nix
# ✅ CORRECT - Layered authentication fallbacks
assertions = [
  {
    assertion = cfg.user.useSecrets -> (config.age.secrets ? "user-initial-password");
    message = "useSecrets enabled but user-initial-password secret not found";
  }
  {
    assertion = (!cfg.user.useSecrets) -> (cfg.user.fallbackPassword != null);  
    message = "useSecrets disabled but no fallbackPassword configured";
  }
];
```

### **Emergency Access Pattern** (Machine Domain)
```nix
# ✅ CORRECT - Machine-level emergency override
# machines/laptop/config.nix
hwc.security.emergencyAccess = {
  enable = true;                    # Temporary during migration
  rootPassword = "il0wwlm?";       # Known working password
  userPassword = "il0wwlm?";       # Same for consistency
};
```

---

## **Implementation Steps**

### **Step 1: Fix System Domain User Management**
**File**: `modules/home/eric.nix` (should be `modules/system/users.nix`)
**Issues**: 
- User management in wrong domain (home vs system)
- Inadequate service dependency management
- Weak assertion validation

#### **Domain Correction**
```nix
# MOVE FROM: modules/home/eric.nix  
# MOVE TO: modules/system/users.nix (proper domain)

options.hwc.system.users.primary = {
  name = mkOption { default = "eric"; };
  useSecrets = mkEnableOption "agenix secret authentication";
  fallbackPassword = mkOption { default = null; };
};
```

### **Step 2: Strengthen Service Dependencies**
```nix
# ✅ CORRECT - modules/system/users.nix
config = {
  # Ensure agenix completes before user sessions
  systemd.services."user@".after = [ "agenix.service" ];
  systemd.services."user@".wants = [ "agenix.service" ];
  
  # User configuration with proper secret handling
  users.users.${cfg.primary.name} = {
    isNormalUser = true;
    hashedPasswordFile = mkIf cfg.primary.useSecrets 
      config.age.secrets.user-initial-password.path;
    initialPassword = mkIf (!cfg.primary.useSecrets && cfg.primary.fallbackPassword != null)
      cfg.primary.fallbackPassword;
  };
};
```

### **Step 3: Enhanced Emergency Access**
**File**: `modules/system/emergency.nix` (new)
```nix
# Emergency access for migration/recovery scenarios
options.hwc.system.emergency = {
  enable = mkEnableOption "emergency root and user access";
  rootPassword = mkOption { type = types.str; };
  userPassword = mkOption { type = types.str; };
};

config = mkIf cfg.enable {
  users.users.root.initialPassword = cfg.rootPassword;
  users.users.${config.hwc.system.users.primary.name}.initialPassword = 
    mkForce cfg.userPassword;  # Override secret-based auth temporarily
};
```

### **Step 4: Machine-Level Safety Configuration**
```nix
# machines/laptop/config.nix - Enable emergency access during migration
hwc.system.emergency = {
  enable = true;                # Temporary safety measure
  rootPassword = "il0wwlm?";
  userPassword = "il0wwlm?";
};

hwc.system.users.primary = {
  useSecrets = true;           # Primary authentication method
  fallbackPassword = "il0wwlm?"; # Secondary if secrets fail
};
```

---

## **Charter Compliance Verification**

### **Domain Correction** (Domain Rules §2)
✅ **User management moved to system domain**: `modules/system/users.nix`  
✅ **Emergency access in system domain**: `modules/system/emergency.nix`  
✅ **Home domain clean**: Only UI/environment configuration remains

### **Service Dependencies** (Charter §5.2)
✅ **Proper ordering**: agenix → user creation → user sessions  
✅ **Dependency declarations**: systemd wants/after relationships configured  
✅ **Failure handling**: Fallback mechanisms for secret unavailability

### **Single Source of Truth** (Charter §4.2)
✅ **User authentication logic**: Only in system domain  
✅ **Emergency access logic**: Only in emergency module  
✅ **Machine overrides**: Only configuration values, no logic

---

## **Diagnostic & Validation**

### **Secret Availability Check**
```bash
# Verify secret decryption
sudo ls -la /run/agenix/
ls -la /run/agenix/user-initial-password
file /run/agenix/user-initial-password

# Check secret content (hashed password format)
sudo cat /run/agenix/user-initial-password
```

### **User Authentication Validation**  
```bash
# Test user password authentication
sudo -k  # Clear sudo cache
sudo whoami  # Should prompt for password

# Check user configuration
sudo grep eric /etc/passwd
sudo grep eric /etc/shadow
```

### **Service Dependencies**
```bash
# Verify service ordering
systemctl list-dependencies agenix.service
systemctl show agenix.service | grep -E "(Before|After|Wants|RequiredBy)"

# Check if secrets exist before user creation
systemctl show user@$(id -u eric).service | grep -E "(After|Wants)"
```

---

## **Expected Outcomes**

### **Authentication Chain Working**
1. **Agenix decrypts secrets**: `/run/agenix/user-initial-password` contains valid hash
2. **User creation uses secret**: `hashedPasswordFile` points to decrypted secret  
3. **Sudo authentication works**: Password from secret unlocks sudo access
4. **Emergency access available**: Root password works as backup

### **Migration Safety**
- ✅ **Multiple auth paths**: Secret-based + fallback + emergency
- ✅ **Service recovery**: Root access available if user auth fails  
- ✅ **Rollback capability**: Can disable secrets, use fallback passwords

### **System Integrity**
- ✅ **Domain compliance**: User management in system domain
- ✅ **Service ordering**: Dependencies prevent race conditions
- ✅ **Charter adherence**: Single source of truth maintained

---

**This fix ensures reliable user authentication by properly integrating agenix secrets with system-domain user management and establishing robust fallback mechanisms.**