# NixOS Vault Sync System
# Automatically syncs ~/.nixos to /home/eric/99-vaults/03_nixos as markdown
{ config, lib, pkgs, ... }:

let
  vaultPath = "/home/eric/99-vaults/03_nixos";
  nixosPath = "/home/eric/.nixos";
  
  # Script to convert .nix files to .md format
  nixToMarkdown = pkgs.writeShellScript "nix-to-markdown" ''
    #!/bin/bash
    
    SOURCE_FILE="$1"
    TARGET_FILE="$2"
    
    # Get relative path for context
    REL_PATH=$(realpath --relative-to="${nixosPath}" "$SOURCE_FILE")
    
    # Create markdown wrapper
    cat > "$TARGET_FILE" << EOF
# $REL_PATH
\`\`\`nix
$(cat "$SOURCE_FILE")
\`\`\`
EOF
    
    echo "Synced: $REL_PATH -> $(basename "$TARGET_FILE")"
  '';
  
  # Main sync script
  syncNixosVault = pkgs.writeShellScript "sync-nixos-vault" ''
    #!/bin/bash
    
    echo "🔄 Syncing NixOS configuration to Obsidian vault..."
    echo "Source: ${nixosPath}"
    echo "Target: ${vaultPath}"
    echo ""
    
    # Create vault directory if it doesn't exist
    mkdir -p "${vaultPath}"
    
    # Create .obsidian directory for proper vault recognition
    mkdir -p "${vaultPath}/.obsidian"
    
    # Sync all .nix files
    find "${nixosPath}" -name "*.nix" -type f | while read -r nixfile; do
      # Get relative path from nixos root
      relpath=$(realpath --relative-to="${nixosPath}" "$nixfile")
      
      # Convert path to markdown filename (replace / with -)
      mdname=$(echo "$relpath" | sed 's/\//-/g' | sed 's/\.nix$/.md/')
      
      # Target markdown file
      target="${vaultPath}/$mdname"
      
      # Create target directory if needed
      target_dir=$(dirname "$target")
      mkdir -p "$target_dir"
      
      # Convert to markdown
      ${nixToMarkdown} "$nixfile" "$target"
    done
    
    # Create index file
    cat > "${vaultPath}/00-INDEX.md" << 'EOF'
# NixOS Configuration Vault

This vault contains a dynamically synced, markdown version of the NixOS configuration from `~/.nixos`.

## 🔄 Auto-Sync System

- **Source**: `~/.nixos`
- **Target**: `~/99-vaults/03_nixos/`
- **Format**: `.nix` files converted to `.md` with syntax highlighting
- **Sync Trigger**: Manual via `sync-nixos-vault` or systemd service

## 📁 File Naming Convention

Files are named using their relative path with `/` replaced by `-`:
- `domains/home/apps/firefox/index.nix` → `domains-home-apps-firefox-index.md`
- `machines/laptop/config.nix` → `machines-laptop-config.md`
- `flake.nix` → `flake.md`

## 🧠 LLM-Friendly Features

- **Markdown format** - Can be read by any LLM
- **Syntax highlighting** - Code is properly formatted
- **File context** - Each file shows its original path
- **Obsidian integration** - Can be browsed and linked within Obsidian

## 🔧 Management Commands

- `sync-nixos-vault` - Manual sync from ~/.nixos
- `watch-nixos-changes` - Watch for changes and auto-sync
- `vault-status` - Show sync status and file counts

Last synced: $(date)
EOF
    
    # Count files
    NIX_COUNT=$(find "${nixosPath}" -name "*.nix" -type f | wc -l)
    MD_COUNT=$(find "${vaultPath}" -name "*.md" -type f | wc -l)
    
    echo ""
    echo "✅ Sync completed!"
    echo "📊 Files: $NIX_COUNT .nix files → $MD_COUNT .md files"
    echo "📂 Vault location: ${vaultPath}"
    echo ""
    echo "💡 Open in Obsidian: obsidian://open?vault=03_nixos"
  '';
  
  # Watch script for continuous sync
  watchNixosChanges = pkgs.writeShellScript "watch-nixos-changes" ''
    #!/bin/bash
    
    echo "👁️  Watching ${nixosPath} for changes..."
    echo "Will auto-sync to ${vaultPath}"
    echo "Press Ctrl+C to stop"
    echo ""
    
    ${pkgs.inotify-tools}/bin/inotifywait -m -r -e modify,create,delete,move "${nixosPath}" --format '%w%f %e' | while read file event; do
      # Only sync .nix files
      if [[ "$file" == *.nix ]]; then
        echo "$(date): $event detected in $file"
        echo "🔄 Triggering sync..."
        ${syncNixosVault}
        echo ""
      fi
    done
  '';
  
  # Status script
  vaultStatus = pkgs.writeShellScript "vault-status" ''
    #!/bin/bash
    
    echo "📊 NixOS Vault Status"
    echo "===================="
    echo ""
    
    if [[ -d "${nixosPath}" ]]; then
      NIX_COUNT=$(find "${nixosPath}" -name "*.nix" -type f | wc -l)
      echo "📄 Source files (.nix): $NIX_COUNT"
    else
      echo "❌ Source directory not found: ${nixosPath}"
    fi
    
    if [[ -d "${vaultPath}" ]]; then
      MD_COUNT=$(find "${vaultPath}" -name "*.md" -type f | wc -l)
      echo "📄 Vault files (.md): $MD_COUNT"
      
      if [[ -f "${vaultPath}/00-INDEX.md" ]]; then
        LAST_SYNC=$(grep "Last synced:" "${vaultPath}/00-INDEX.md" | cut -d: -f2-)
        echo "🕐 Last sync:$LAST_SYNC"
      fi
    else
      echo "❌ Vault directory not found: ${vaultPath}"
    fi
    
    echo ""
    echo "🔧 Available commands:"
    echo "  sync-nixos-vault     - Manual sync"
    echo "  watch-nixos-changes  - Auto-sync on changes"
    echo "  vault-status         - This status display"
  '';

in {
  # Make scripts available system-wide
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "sync-nixos-vault" ''exec ${syncNixosVault}'')
    (pkgs.writeShellScriptBin "watch-nixos-changes" ''exec ${watchNixosChanges}'')
    (pkgs.writeShellScriptBin "vault-status" ''exec ${vaultStatus}'')
  ];
  
  # Systemd service for automatic sync
  systemd.services.nixos-vault-sync = {
    description = "Sync NixOS configuration to Obsidian vault";
    serviceConfig = {
      Type = "oneshot";
      User = "eric";
      ExecStart = syncNixosVault;
    };
  };
  
  # Timer to sync every hour (can be adjusted)
  systemd.timers.nixos-vault-sync = {
    description = "Hourly NixOS vault sync";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
      RandomizedDelaySec = "10m"; # Add some randomization
    };
  };
  
  # User service for manual watching
  systemd.user.services.nixos-vault-watch = {
    description = "Watch NixOS changes and auto-sync to vault";
    serviceConfig = {
      Type = "simple";
      ExecStart = watchNixosChanges;
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
  
  # Ensure vault directory exists
  systemd.tmpfiles.rules = [
    "d ${vaultPath} 0755 eric users -"
    "d ${vaultPath}/.obsidian 0755 eric users -"
  ];
}