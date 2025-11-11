#!/usr/bin/env bash
# HARDENED Enhanced grebuild function - Fast git workflow + rebuild, then AI processing
# HARDENED: Git push error handling with notifications

set -e

if [ $# -eq 0 ]; then
    echo "Usage: grebuild \"commit message\""
    exit 1
fi

COMMIT_MESSAGE="$1"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo "🚀 Starting hardened grebuild workflow..."
echo "📝 Commit message: $COMMIT_MESSAGE"

# Step 1: Git operations (fast)
echo "📦 Adding changes to git..."
sudo git add .

echo "💾 Committing changes..."
sudo git commit -m "$COMMIT_MESSAGE"

# Capture commit hash for notifications
COMMIT_HASH=$(git rev-parse HEAD)
SHORT_HASH="${COMMIT_HASH:0:8}"

# Step 2: Test rebuild first (safety check)
echo "🧪 Testing NixOS configuration..."
if sudo nixos-rebuild test --flake .#hwc-server; then
    echo "✅ Test successful!"
    
    # Step 3: Apply rebuild
    echo "🔄 Applying NixOS rebuild..."
    if sudo nixos-rebuild switch --flake .#hwc-server; then
        echo "✅ Rebuild successful!"
        
        # HARDENED Step 4: Git push with error handling
        echo "📤 Pushing to remote repository..."
        if sudo git push; then
            echo "✅ Git push successful!"
            PUSH_STATUS="✅ Pushed to remote"
        else
            echo "⚠️ Warning: Git push failed!"
            PUSH_STATUS="⚠️ Push failed - local changes only"
            
            # Send warning notification about push failure
            curl -s -H "Title: ⚠️ Git Push Failed" -H "Priority: default" \
                 -d "NixOS rebuild succeeded but git push failed. Changes are local only. Commit: $SHORT_HASH" \
                 https://hwc.ocelot-wahoo.ts.net/notify/hwc-alerts 2>/dev/null || true
        fi
        
        # Step 5: Trigger AI documentation (non-blocking)
        echo "🤖 Triggering AI documentation processing..."
        sudo systemctl start post-rebuild-ai-docs &
        
        # Send completion notification with push status
        curl -s -H "Title: ✅ NixOS Rebuild Complete" \
             -d "Successfully rebuilt and deployed: $COMMIT_MESSAGE ($SHORT_HASH)
             
$PUSH_STATUS
AI documentation processing started..." \
             https://hwc.ocelot-wahoo.ts.net/notify/hwc-alerts 2>/dev/null || true
        
        echo "🎉 Grebuild complete! AI documentation running in background."
        echo "📱 You'll receive a notification when AI docs are updated."
        echo "📍 Commit: $SHORT_HASH"
        echo "📤 Push status: $PUSH_STATUS"
        
    else
        echo "❌ Rebuild failed!"
        
        # Send failure notification
        curl -s -H "Title: ❌ NixOS Rebuild Failed" -H "Priority: urgent" \
             -d "NixOS rebuild failed for commit: $COMMIT_MESSAGE ($SHORT_HASH). Check system logs." \
             https://hwc.ocelot-wahoo.ts.net/notify/hwc-alerts 2>/dev/null || true
        
        exit 1
    fi
else
    echo "❌ Test failed! Not proceeding with rebuild."
    
    # Send test failure notification  
    curl -s -H "Title: ❌ NixOS Test Failed" -H "Priority: high" \
         -d "NixOS configuration test failed for: $COMMIT_MESSAGE ($SHORT_HASH). Changes not applied." \
         https://hwc.ocelot-wahoo.ts.net/notify/hwc-alerts 2>/dev/null || true
    
    exit 1
fi
